import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/calls/application/call_controller.dart';
import 'package:pulse/features/calls/data/call_repository.dart';
import 'package:pulse/features/calls/domain/call_session.dart';

/// Phase 8: the state machine and the "no fake connected" rule.
///
/// The call row is the referee. Media is only a veto: the UI may claim
/// "Connected" when the row says `active` **and** the media layer is up.
void main() {
  group('CallState', () {
    test('every state in the machine is reachable', () {
      // Walk the graph from idle and collect what can be reached.
      final seen = <CallState>{CallState.idle};
      final queue = <CallState>[CallState.idle];
      while (queue.isNotEmpty) {
        final from = queue.removeAt(0);
        for (final to in CallState.values) {
          if (CallMachine.canTransition(from, to) && seen.add(to)) {
            queue.add(to);
          }
        }
      }
      expect(seen, containsAll(CallState.values));
    });

    test('terminal states can only go back to idle', () {
      for (final terminal in [
        CallState.ended,
        CallState.declined,
        CallState.missed,
        CallState.failed,
      ]) {
        expect(CallMachine.canTransition(terminal, CallState.idle), isTrue);
        expect(CallMachine.canTransition(terminal, CallState.active), isFalse);
        expect(
          CallMachine.canTransition(terminal, CallState.connecting),
          isFalse,
        );
      }
    });

    test('no shortcut from ringing straight to active', () {
      expect(
        CallMachine.canTransition(CallState.ringing, CallState.active),
        isFalse,
      );
      expect(
        CallMachine.canTransition(CallState.calling, CallState.active),
        isFalse,
      );
      expect(
        CallMachine.canTransition(CallState.connecting, CallState.active),
        isTrue,
      );
    });

    test('an active call cannot silently restart', () {
      expect(
        CallMachine.canTransition(CallState.active, CallState.calling),
        isFalse,
      );
      expect(
        CallMachine.canTransition(CallState.active, CallState.ringing),
        isFalse,
      );
    });

    test('the DB state maps onto the UI state for both sides', () {
      expect(CallState.fromRow('ringing', iAmCaller: true), CallState.calling);
      expect(CallState.fromRow('ringing', iAmCaller: false), CallState.ringing);
      expect(
        CallState.fromRow('connecting', iAmCaller: true),
        CallState.connecting,
      );
      expect(CallState.fromRow('active', iAmCaller: false), CallState.active);
      expect(
        CallState.fromRow('reconnecting', iAmCaller: false),
        CallState.reconnecting,
      );
      expect(
        CallState.fromRow('declined', iAmCaller: true),
        CallState.declined,
      );
      expect(CallState.fromRow('missed', iAmCaller: true), CallState.missed);
      expect(CallState.fromRow('ended', iAmCaller: true), CallState.ended);
      expect(
        CallState.fromRow('something_new', iAmCaller: true),
        CallState.failed,
      );
    });

    test('every UI state round-trips through the row value the DB accepts', () {
      for (final state in CallState.values) {
        final row = state.rowValue;
        if (row == null) continue; // idle is not stored
        expect([
          'ringing',
          'connecting',
          'active',
          'reconnecting',
          'ended',
          'declined',
          'missed',
          'failed',
        ], contains(row));
      }
    });

    test('live and finished sets do not overlap', () {
      for (final state in CallState.values) {
        expect(state.isLive && state.isFinished, isFalse);
      }
      expect(CallState.connecting.isLive, isTrue);
      expect(CallState.ended.isFinished, isTrue);
    });
  });

  group('no fake "connected"', () {
    test('the row saying active is not enough while media is down', () {
      final next = CallMachine.next(
        current: CallState.connecting,
        rowState: 'active',
        iAmCaller: true,
        mediaUp: false,
      );
      expect(next, CallState.connecting);
      expect(next.label, isNot('Connected'));
    });

    test('media up plus an active row is what produces Connected', () {
      final next = CallMachine.next(
        current: CallState.connecting,
        rowState: 'active',
        iAmCaller: true,
        mediaUp: true,
      );
      expect(next, CallState.active);
      expect(next.label, 'Connected');
    });

    test(
      'a media layer that never comes up fails the call, it does not connect',
      () {
        final next = CallMachine.next(
          current: CallState.active,
          rowState: 'active',
          iAmCaller: false,
          mediaUp: false,
        );
        expect(next, CallState.failed);
      },
    );

    test('the mock media reports the truth about its own channel', () async {
      final dead = MockCallMedia(connect: false);
      await dead.join(callId: 'c1', kind: CallKind.audio);
      expect(dead.joined, isFalse);

      final live = MockCallMedia();
      await live.join(callId: 'c1', kind: CallKind.video);
      expect(live.joined, isTrue);
      await live.setMuted(true);
      await live.leave();
      expect(live.log, ['join:c1:video', 'muted:true', 'leave']);
    });
  });

  group('controller — driven by a fake server', () {
    test('the call screen never says Connected on the row alone', () async {
      final repo = _FakeCallRepo(row: _row(state: 'connecting'));
      final media = MockCallMedia(connect: false);
      final container = ProviderContainer(
        overrides: [
          callRepositoryProvider.overrideWithValue(repo),
          callMediaProvider.overrideWithValue(media),
        ],
      );
      addTearDown(container.dispose);

      await container.read(callControllerProvider('call-1').future);
      final controller = container.read(
        callControllerProvider('call-1').notifier,
      );

      await controller.mediaReady();

      final session = container.read(callControllerProvider('call-1')).value!;
      expect(session.state, CallState.failed);
      expect(media.joined, isFalse);
      // The server was never told the media came up.
      expect(repo.confirmed, 0);
    });

    test(
      'a working media layer confirms, and only then is the call active',
      () async {
        final repo = _FakeCallRepo(row: _row(state: 'connecting'));
        final media = MockCallMedia();
        final container = ProviderContainer(
          overrides: [
            callRepositoryProvider.overrideWithValue(repo),
            callMediaProvider.overrideWithValue(media),
          ],
        );
        addTearDown(container.dispose);

        await container.read(callControllerProvider('call-1').future);
        repo.row = _row(
          state: 'active',
          answeredAt: DateTime.now().toUtc().toIso8601String(),
        );
        await container
            .read(callControllerProvider('call-1').notifier)
            .mediaReady();

        expect(repo.confirmed, 1);
        final session = container.read(callControllerProvider('call-1')).value!;
        expect(session.state, CallState.active);
        expect(session.answeredAt, isNotNull);
      },
    );

    test('accepting joins media and reports connected once', () async {
      final repo = _FakeCallRepo(row: _row(state: 'ringing', iAmCaller: false));
      final media = MockCallMedia();
      final container = ProviderContainer(
        overrides: [
          callRepositoryProvider.overrideWithValue(repo),
          callMediaProvider.overrideWithValue(media),
        ],
      );
      addTearDown(container.dispose);

      await container.read(callControllerProvider('call-1').future);
      await container.read(callControllerProvider('call-1').notifier).accept();

      expect(repo.accepted, 1);
      expect(media.joined, isTrue);
    });

    test('hanging up while dialling cancels the call', () async {
      final repo = _FakeCallRepo(row: _row(state: 'ringing'));
      final container = ProviderContainer(
        overrides: [
          callRepositoryProvider.overrideWithValue(repo),
          callMediaProvider.overrideWithValue(MockCallMedia()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(callControllerProvider('call-1').future);
      await container.read(callControllerProvider('call-1').notifier).hangup();

      expect(repo.endReasons, ['cancelled']);
    });

    test('mute and speaker are applied to the media layer', () async {
      final repo = _FakeCallRepo(row: _row(state: 'active'));
      final media = MockCallMedia();
      final container = ProviderContainer(
        overrides: [
          callRepositoryProvider.overrideWithValue(repo),
          callMediaProvider.overrideWithValue(media),
        ],
      );
      addTearDown(container.dispose);

      await container.read(callControllerProvider('call-1').future);
      final controller = container.read(
        callControllerProvider('call-1').notifier,
      );
      await controller.toggleMute();
      await controller.toggleSpeaker();

      expect(media.log, containsAll(['muted:true', 'speaker:true']));
      final session = container.read(callControllerProvider('call-1')).value!;
      expect(session.muted, isTrue);
      expect(session.speaker, isTrue);
    });
  });

  group('CallSession', () {
    test('the timer only runs once the call is active', () {
      final now = DateTime(2026, 11, 14, 12, 0, 0);
      final connecting = _session(state: CallState.connecting, answeredAt: now);
      expect(
        connecting.elapsed(now.add(const Duration(seconds: 9))),
        Duration.zero,
      );

      final active = _session(state: CallState.active, answeredAt: now);
      expect(
        active.elapsedLabel(now.add(const Duration(seconds: 65))),
        '01:05',
      );
      expect(
        active.elapsedLabel(now.add(const Duration(hours: 1, minutes: 2))),
        '1:02:00',
      );
    });

    test('a row is read the right way round for both parties', () {
      final row = {
        'id': 'call-1',
        'conversation_id': 'conv-1',
        'caller_id': 'me',
        'callee_id': 'you',
        'kind': 'video',
        'state': 'ringing',
        'answered_at': null,
        'ended_at': null,
        'end_reason': null,
      };
      final mine = CallSession.fromRow(row, myId: 'me', peerName: 'Bela');
      expect(mine.state, CallState.calling);
      expect(mine.peerId, 'you');

      final theirs = CallSession.fromRow(row, myId: 'you', peerName: 'Arif');
      expect(theirs.state, CallState.ringing);
      expect(theirs.peerId, 'me');
      expect(theirs.kind, CallKind.video);
    });
  });
}

Map<String, dynamic> _row({
  required String state,
  bool iAmCaller = true,
  String? answeredAt,
}) => {
  'id': 'call-1',
  'conversation_id': 'conv-1',
  'caller_id': iAmCaller ? _me : 'other-user',
  'callee_id': iAmCaller ? 'other-user' : _me,
  'kind': 'audio',
  'state': state,
  'answered_at': answeredAt,
  'ended_at': null,
  'end_reason': null,
};

CallSession _session({required CallState state, DateTime? answeredAt}) =>
    CallSession(
      id: 'call-1',
      conversationId: 'conv-1',
      peerName: 'Bela',
      peerId: 'other-user',
      kind: CallKind.audio,
      state: state,
      answeredAt: answeredAt,
    );

class _FakeCallRepo implements CallRepository {
  _FakeCallRepo({required this.row});

  Map<String, dynamic> row;
  int confirmed = 0;
  int accepted = 0;
  final endReasons = <String>[];

  @override
  String? get currentUserId => _me;

  @override
  Future<Map<String, dynamic>?> byId(String callId) async => row;

  @override
  Future<String> peerName(String userId) async => 'Bela';

  @override
  Future<void> confirmConnected(String callId) async => confirmed++;

  @override
  Future<void> accept(String callId) async {
    accepted++;
    row = {...row, 'state': 'connecting'};
  }

  @override
  Future<void> decline(String callId) async {
    row = {...row, 'state': 'declined', 'end_reason': 'declined'};
  }

  @override
  Future<void> end(String callId, {String reason = 'hangup'}) async {
    endReasons.add(reason);
    row = {...row, 'state': 'ended', 'end_reason': reason};
  }

  @override
  Future<void> setReconnecting(String callId, {required bool on}) async {
    row = {...row, 'state': on ? 'reconnecting' : 'active'};
  }

  @override
  Future<String> start(String conversationId, CallKind kind) async => 'call-1';

  @override
  Future<Map<String, dynamic>?> myIncoming() async => null;

  @override
  Stream<Map<String, dynamic>> watch(String callId) => const Stream.empty();
}

const _me = 'aaaaaaaa-0000-4000-8000-000000000001';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../data/call_repository.dart';
import '../domain/call_session.dart';

final _log = AppLogger('calls');

/// One live call, driven by the database row plus the media layer.
///
/// The DB row is the only source of truth for the call's *phase*; the media
/// layer only gets a vote on whether we may call it "Connected".
class CallController extends AsyncNotifier<CallSession?> {
  CallController(this._callId);

  /// Riverpod 3 families pass the argument to the constructor, not to build().
  final String _callId;
  String? _peerName;
  bool _mediaUp = false;
  bool _subscribed = false;

  @override
  Future<CallSession?> build() async {
    final row = await ref.watch(callRepositoryProvider).byId(_callId);
    if (row == null) return null;
    _watchRow();
    return _session(row);
  }

  String? get _myId => ref.read(callRepositoryProvider).currentUserId;

  void _watchRow() {
    if (_subscribed) return;
    _subscribed = true;
    ref.listen(callRowStreamProvider(_callId), (_, next) {
      next.whenData((row) async {
        final merged = CallMachine.next(
          current: state.value?.state ?? CallState.idle,
          rowState: row['state'] as String,
          iAmCaller: row['caller_id'] == _myId,
          mediaUp: _mediaUp,
        );
        final session = await _session(row);
        state = AsyncData(session.copyWith(state: merged));
        if (merged.isFinished) {
          ref.read(callMediaProvider).leave();
          _mediaUp = false;
        }
      });
    });
  }

  Future<CallSession> _session(Map<String, dynamic> row) async {
    final name = _peerName ??= await _peerDisplayName(row);
    return CallSession.fromRow(row, myId: _myId ?? '', peerName: name);
  }

  Future<String> _peerDisplayName(Map<String, dynamic> row) async {
    final peerId = row['caller_id'] == _myId
        ? row['callee_id'] as String
        : row['caller_id'] as String;
    try {
      return await ref.read(callRepositoryProvider).peerName(peerId);
    } on AppFailure {
      // The call must not fail over a name.
      return 'Pulse user';
    }
  }

  /// Joins the media layer, then tells the server media is up. The row only
  /// becomes `active` after both — the screen can never show a fake "Connected".
  Future<void> mediaReady() async {
    final session = state.value;
    if (session == null) return;
    final media = ref.read(callMediaProvider);
    await media.join(callId: _callId, kind: session.kind);
    final up = media is MockCallMedia ? media.joined : true;
    if (!up) {
      _log.warning('media_join_failed', error: _callId);
      state = AsyncData(session.copyWith(state: CallState.failed));
      return;
    }
    _mediaUp = true;
    try {
      await ref.read(callRepositoryProvider).confirmConnected(_callId);
    } on AppFailure catch (e) {
      _log.warning('confirm_connected_failed', error: e.code);
    }
    final row = await ref.read(callRepositoryProvider).byId(_callId);
    if (row != null) {
      final merged = CallMachine.next(
        current: session.state,
        rowState: row['state'] as String,
        iAmCaller: row['caller_id'] == _myId,
        mediaUp: _mediaUp,
      );
      state = AsyncData((await _session(row)).copyWith(state: merged));
    }
  }

  Future<void> accept() async {
    await _guard(() => ref.read(callRepositoryProvider).accept(_callId));
    await mediaReady();
  }

  Future<void> decline() async {
    await _guard(() => ref.read(callRepositoryProvider).decline(_callId));
  }

  Future<void> hangup() async {
    final session = state.value;
    final reason =
        session?.state == CallState.ringing ||
            session?.state == CallState.calling
        ? (session!.state == CallState.calling ? 'cancelled' : 'hangup')
        : 'hangup';
    await _guard(() async {
      await ref.read(callRepositoryProvider).end(_callId, reason: reason);
    });
    await ref.read(callMediaProvider).leave();
    _mediaUp = false;
  }

  Future<void> toggleMute() async {
    final session = state.value;
    if (session == null) return;
    final muted = !session.muted;
    await ref.read(callMediaProvider).setMuted(muted);
    state = AsyncData(session.copyWith(muted: muted));
  }

  Future<void> toggleSpeaker() async {
    final session = state.value;
    if (session == null) return;
    final speaker = !session.speaker;
    await ref.read(callMediaProvider).setSpeaker(speaker);
    state = AsyncData(session.copyWith(speaker: speaker));
  }

  /// Called when the socket drops: the row is the referee, we only report.
  Future<void> reportReconnecting({required bool on}) async {
    await _guard(
      () => ref.read(callRepositoryProvider).setReconnecting(_callId, on: on),
    );
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
      final row = await ref.read(callRepositoryProvider).byId(_callId);
      if (row != null) {
        state = AsyncData(await _session(row));
      }
    } on AppFailure catch (e) {
      _log.warning('call_action_failed', error: e.code);
      final session = state.value;
      if (session != null) {
        state = AsyncData(session.copyWith(state: CallState.failed));
      }
    }
  }
}

final callControllerProvider = AsyncNotifierProvider.autoDispose
    .family<CallController, CallSession?, String>(CallController.new);

/// Realtime row stream for one call.
final callRowStreamProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) {
      return ref.watch(callRepositoryProvider).watch(id);
    });

/// Starts a call and returns its id (used by the chat screen button).
final startCallProvider = FutureProvider.autoDispose
    .family<String, ({String conversationId, CallKind kind})>((
      ref,
      args,
    ) async {
      final id = await ref
          .read(callRepositoryProvider)
          .start(args.conversationId, args.kind);
      return id;
    });

/// The call I should be answering right now, if any.
final incomingCallProvider = FutureProvider.autoDispose<String?>((ref) async {
  final repo = ref.watch(callRepositoryProvider);
  if (repo.currentUserId == null) return null;
  final row = await repo.myIncoming();
  return row?['id'] as String?;
});

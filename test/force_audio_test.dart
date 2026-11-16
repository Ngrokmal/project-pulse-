import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/force_audio/application/force_audio_controllers.dart';
import 'package:pulse/features/force_audio/application/force_audio_providers.dart';
import 'package:pulse/features/force_audio/data/force_audio_downloader.dart';
import 'package:pulse/features/force_audio/domain/force_audio_alert.dart';
import 'package:pulse/features/force_audio/domain/force_audio_played_store.dart';
import 'package:pulse/features/force_audio/domain/force_audio_repository.dart';

class _FakeRepo implements ForceAudioRepository {
  _FakeRepo({this.alert});
  final ForceAudioAlert? alert;
  int fetches = 0;
  final List<String> played = [];
  final List<String> delivered = [];

  @override
  Future<ForceAudioAlert?> fetch(String alertId) async {
    fetches++;
    return alert;
  }

  @override
  Future<ForceAudioAlert?> fetchByMessage(String messageId) async => alert;

  @override
  Future<void> markDelivered(String alertId) async => delivered.add(alertId);

  @override
  Future<void> markPlayed(String alertId) async => played.add(alertId);

  @override
  Future<ForceAudioAlert> createAlert({
    required String requestId,
    required String conversationId,
    required String recipientId,
    required String mediaUrl,
    required int durationMs,
    required int sizeBytes,
    String? messageId,
    String mimeType = 'audio/mp4',
  }) async => throw UnimplementedError();
}

class _FakeDownloader implements ForceAudioDownloader {
  int calls = 0;

  @override
  Future<Never> download(
    ForceAudioAlert alert, {
    void Function(double progress)? onProgress,
  }) async {
    calls++;
    throw StateError('should not download');
  }
}

ForceAudioAlert _alert({
  String id = 'alert-1',
  ForceAudioState state = ForceAudioState.created,
  DateTime? expiresAt,
  int durationMs = 42000,
}) => ForceAudioAlert(
  id: id,
  requestId: 'request-1',
  conversationId: 'conv-1',
  senderId: 'sender-1',
  recipientId: 'recipient-1',
  mediaUrl: 'https://res.cloudinary.com/demo/video/upload/v1/a.m4a',
  durationMs: durationMs,
  sizeBytes: 240000,
  state: state,
  createdAt: DateTime.now(),
  expiresAt: expiresAt ?? DateTime.now().add(const Duration(hours: 23)),
);

void main() {
  group('limits — the 70 s / 10 MiB rules (§5)', () {
    test('the cap is exactly 70 s', () {
      expect(ForceAudioLimits.reachedDurationCap(69999), isFalse);
      expect(ForceAudioLimits.reachedDurationCap(70000), isTrue);
      expect(ForceAudioLimits.reachedDurationCap(70001), isTrue);
    });

    test('the byte cap is exactly 10 MiB', () {
      expect(ForceAudioLimits.isTooLarge(10 * 1024 * 1024), isFalse);
      expect(ForceAudioLimits.isTooLarge(10 * 1024 * 1024 + 1), isTrue);
    });

    test('a click shorter than half a second is not a recording', () {
      expect(ForceAudioLimits.isTooShort(499), isTrue);
      expect(ForceAudioLimits.isTooShort(500), isFalse);
    });

    test('the countdown never goes negative', () {
      expect(ForceAudioLimits.secondsLeft(0), 70);
      expect(ForceAudioLimits.secondsLeft(42000), 28);
      expect(ForceAudioLimits.secondsLeft(70000), 0);
      expect(ForceAudioLimits.secondsLeft(99000), 0);
    });

    test('durations are formatted mm:ss', () {
      expect(ForceAudioLimits.format(0), '0:00');
      expect(ForceAudioLimits.format(9000), '0:09');
      expect(ForceAudioLimits.format(70000), '1:10');
    });
  });

  group('alert model', () {
    test('parses the row the server returns', () {
      final alert = ForceAudioAlert.fromMap({
        'id': 'a1',
        'request_id': 'r1',
        'conversation_id': 'c1',
        'message_id': 'm1',
        'sender_id': 's1',
        'recipient_id': 'p1',
        'media_url': 'https://res.cloudinary.com/x/video/upload/v1/a.m4a',
        'duration_ms': 42000,
        'size_bytes': 240000,
        'mime_type': 'audio/mp4',
        'state': 'created',
        'created_at': '2026-11-14T10:00:00Z',
        // Relative, not a fixed date — a hardcoded future timestamp turns
        // into a failing test the day it passes.
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 24))
            .toIso8601String(),
        'played_at': null,
      });
      expect(alert.state, ForceAudioState.created);
      expect(alert.durationLabel, '0:42');
      expect(alert.isExpired, isFalse);
      expect(alert.messageId, 'm1');
    });

    test('an old expires_at counts as expired even in state created', () {
      final alert = _alert(
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(alert.isExpired, isTrue);
    });

    test('an unknown state from the server does not explode the UI', () {
      expect(ForceAudioState.parse('who_knows'), ForceAudioState.created);
      expect(ForceAudioState.parse(null), ForceAudioState.created);
    });

    test('played and expired are terminal', () {
      expect(ForceAudioState.played.isTerminal, isTrue);
      expect(ForceAudioState.expired.isTerminal, isTrue);
      expect(ForceAudioState.created.isTerminal, isFalse);
      expect(ForceAudioState.delivered.isTerminal, isFalse);
    });
  });

  group('duplicate-playback guard (§5)', () {
    test('the store remembers an alert across calls', () async {
      final store = InMemoryPlayedAlertStore();
      expect(await store.isPlayed('a1'), isFalse);
      await store.markPlayed('a1');
      expect(await store.isPlayed('a1'), isTrue);
      expect(await store.isPlayed('a2'), isFalse);
    });

    test(
      'an alert already played on this device is never fetched again',
      () async {
        final repo = _FakeRepo(alert: _alert());
        final downloader = _FakeDownloader();
        final container = ProviderContainer(
          overrides: [
            forceAudioRepositoryProvider.overrideWithValue(repo),
            forceAudioDownloaderProvider.overrideWithValue(downloader),
            playedAlertStoreProvider.overrideWithValue(
              InMemoryPlayedAlertStore({'alert-1'}),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(forceAudioPlaybackProvider('alert-1').notifier)
            .play();

        expect(
          container.read(forceAudioPlaybackProvider('alert-1')).stage,
          ForceAudioReceiveStage.played,
        );
        expect(
          repo.fetches,
          0,
          reason: 'no network for an already-played alert',
        );
        expect(downloader.calls, 0);
      },
    );

    test(
      'an unknown alert id is reported as unavailable, not played',
      () async {
        final repo = _FakeRepo(alert: null);
        final container = ProviderContainer(
          overrides: [
            forceAudioRepositoryProvider.overrideWithValue(repo),
            forceAudioDownloaderProvider.overrideWithValue(_FakeDownloader()),
            playedAlertStoreProvider.overrideWithValue(
              InMemoryPlayedAlertStore(),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(forceAudioPlaybackProvider('ghost').notifier)
            .play();
        expect(
          container.read(forceAudioPlaybackProvider('ghost')).stage,
          ForceAudioReceiveStage.unauthorized,
        );
      },
    );

    test('an expired alert is refused before any download', () async {
      final repo = _FakeRepo(
        alert: _alert(
          state: ForceAudioState.expired,
          expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );
      final downloader = _FakeDownloader();
      final container = ProviderContainer(
        overrides: [
          forceAudioRepositoryProvider.overrideWithValue(repo),
          forceAudioDownloaderProvider.overrideWithValue(downloader),
          playedAlertStoreProvider.overrideWithValue(
            InMemoryPlayedAlertStore(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(forceAudioPlaybackProvider('alert-1').notifier)
          .play();
      expect(
        container.read(forceAudioPlaybackProvider('alert-1')).stage,
        ForceAudioReceiveStage.expired,
      );
      expect(downloader.calls, 0);
    });
  });

  group('composer state', () {
    test('a recording shows the time left before the cap', () {
      const state = ForceAudioComposerState(
        stage: ComposerStage.recording,
        elapsedMs: 30000,
      );
      expect(state.isRecording, isTrue);
      expect(state.secondsLeft, 40);
      expect(state.canSend, isFalse);
    });

    test('a recorded take can be sent', () {
      const state = ForceAudioComposerState(
        stage: ComposerStage.recorded,
        elapsedMs: 12000,
        sizeBytes: 96000,
      );
      expect(state.canSend, isTrue);
      expect(state.isBusy, isFalse);
    });

    test('uploading is not a send yet', () {
      const state = ForceAudioComposerState(
        stage: ComposerStage.uploading,
        progress: 0.4,
      );
      expect(state.isBusy, isTrue);
      expect(state.canSend, isFalse);
    });
  });
}

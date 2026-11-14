import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/features/force_audio/application/force_audio_providers.dart';
import 'package:pulse/features/force_audio/data/force_audio_downloader.dart';
import 'package:pulse/features/force_audio/domain/force_audio_alert.dart';
import 'package:pulse/features/force_audio/domain/force_audio_played_store.dart';
import 'package:pulse/features/force_audio/domain/force_audio_repository.dart';
import 'package:pulse/features/force_audio/presentation/force_audio_screen.dart';

class _Repo implements ForceAudioRepository {
  _Repo(this.alert);
  final ForceAudioAlert? alert;
  int fetches = 0;

  @override
  Future<ForceAudioAlert?> fetch(String alertId) async {
    fetches++;
    return alert;
  }

  @override
  Future<ForceAudioAlert?> fetchByMessage(String messageId) async => alert;
  @override
  Future<void> markDelivered(String alertId) async {}
  @override
  Future<void> markPlayed(String alertId) async {}
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

class _Downloader implements ForceAudioDownloader {
  int calls = 0;

  @override
  Future<File> download(
    ForceAudioAlert alert, {
    void Function(double progress)? onProgress,
  }) async {
    calls++;
    throw StateError('must not download');
  }
}

ForceAudioAlert _alert({
  ForceAudioState state = ForceAudioState.created,
  DateTime? expiresAt,
}) => ForceAudioAlert(
  id: 'a1',
  requestId: 'r1',
  conversationId: 'c1',
  senderId: 's1',
  recipientId: 'r1',
  mediaUrl: 'https://res.cloudinary.com/demo/video/upload/v1/a.m4a',
  durationMs: 42000,
  sizeBytes: 240000,
  state: state,
  createdAt: DateTime.now(),
  expiresAt: expiresAt ?? DateTime.now().add(const Duration(hours: 20)),
);

/// The takeover screen must never claim progress it cannot prove: an unknown, an
/// already-played and an expired alert are all terminal without touching audio.
void main() {
  // Riverpod 3 does not export the `Override` type, so each test builds its own
  // ProviderScope inline instead of passing a typed list around.
  Widget wrap(Widget child, ProviderContainer container) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: child),
      );

  testWidgets('an unknown alert id is reported as unavailable', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ForceAudioScreen(alertId: 'ghost'),
        ProviderContainer(
          overrides: [
            forceAudioRepositoryProvider.overrideWithValue(_Repo(null)),
            forceAudioDownloaderProvider.overrideWithValue(_Downloader()),
            playedAlertStoreProvider.overrideWithValue(
              InMemoryPlayedAlertStore(),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('This alert is not available'), findsOneWidget);
    expect(find.text('Checking for new messages'), findsNothing);
  });

  testWidgets('an already played alert says Played and offers Close', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const ForceAudioScreen(alertId: 'a1'),
        ProviderContainer(
          overrides: [
            forceAudioRepositoryProvider.overrideWithValue(_Repo(_alert())),
            forceAudioDownloaderProvider.overrideWithValue(_Downloader()),
            playedAlertStoreProvider.overrideWithValue(
              InMemoryPlayedAlertStore({'a1'}),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Played'), findsOneWidget);
    expect(find.text('You have already heard this one.'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('an expired alert is refused before any download', (
    tester,
  ) async {
    final downloader = _Downloader();
    await tester.pumpWidget(
      wrap(
        const ForceAudioScreen(alertId: 'a1'),
        ProviderContainer(
          overrides: [
            forceAudioRepositoryProvider.overrideWithValue(
              _Repo(
                _alert(
                  state: ForceAudioState.expired,
                  expiresAt: DateTime.now().subtract(const Duration(hours: 2)),
                ),
              ),
            ),
            forceAudioDownloaderProvider.overrideWithValue(downloader),
            playedAlertStoreProvider.overrideWithValue(
              InMemoryPlayedAlertStore(),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('This alert expired'), findsOneWidget);
    expect(downloader.calls, 0);
  });
}

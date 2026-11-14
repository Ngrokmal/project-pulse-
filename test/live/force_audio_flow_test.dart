// End-to-end Force Audio media path against the REAL Cloudinary account:
// synthesize audio → upload as the `video` resource → download it back with real
// byte progress → verify the file. Skips itself without --dart-define.
//
//   flutter test test/live/force_audio_flow_test.dart \
//     --dart-define=CLOUDINARY_CLOUD_NAME=<cloud>
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/config/app_config.dart';
import 'package:pulse/features/force_audio/data/force_audio_downloader.dart';
import 'package:pulse/features/force_audio/domain/force_audio_alert.dart';
import 'package:pulse/features/media/data/cloudinary_uploader.dart';
import 'package:pulse/features/media/domain/media_asset.dart';

/// Minimal 16-bit mono PCM WAV, so the test does not need an audio encoder.
Uint8List wavTone({int seconds = 3, int sampleRate = 16000, double hz = 440}) {
  final samples = sampleRate * seconds;
  final data = BytesBuilder();
  for (var i = 0; i < samples; i++) {
    final v = (12000 * math.sin(2 * math.pi * hz * i / sampleRate)).round();
    data.add([v & 0xFF, (v >> 8) & 0xFF]);
  }
  final pcm = data.toBytes();
  final byteRate = sampleRate * 2;
  final header = BytesBuilder()
    ..add(ascii.encode('RIFF'))
    ..add(_le32(36 + pcm.length))
    ..add(ascii.encode('WAVE'))
    ..add(ascii.encode('fmt '))
    ..add(_le32(16))
    ..add(_le16(1)) // PCM
    ..add(_le16(1)) // mono
    ..add(_le32(sampleRate))
    ..add(_le32(byteRate))
    ..add(_le16(2)) // block align
    ..add(_le16(16)) // bits
    ..add(ascii.encode('data'))
    ..add(_le32(pcm.length));
  return (header..add(pcm)).toBytes();
}

List<int> _le32(int v) => [
  v & 0xFF,
  (v >> 8) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 24) & 0xFF,
];
List<int> _le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];

void main() {
  const cloud = AppConfig.cloudinaryCloudName;
  if (cloud.isEmpty) {
    test(
      'force audio live flow',
      () {},
      skip: 'no --dart-define=CLOUDINARY_CLOUD_NAME',
    );
    return;
  }

  late Directory tmp;
  late String url;
  late int size;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('pulse_fa');
  });

  test('an audio recording uploads to the video resource type', () async {
    final bytes = wavTone();
    size = bytes.length;
    final file = File('${tmp.path}/recording.wav');
    await file.writeAsBytes(bytes);

    final progress = <double>[];
    final asset = await CloudinaryUploader().upload(
      PickedMedia(
        path: file.path,
        fileName: 'recording.wav',
        sizeBytes: size,
        // Audio goes to Cloudinary's `video` resource: raw stores no
        // content-type, which breaks streaming players.
        resourceType: MediaResourceType.video,
      ),
      onProgress: progress.add,
    );
    url = asset.secureUrl;

    // ignore: avoid_print
    print(
      'audio upload: $url (${asset.bytes} bytes, duration=${asset.durationMs} ms, ${progress.length} progress events)',
    );
    expect(url, contains('/video/upload/'));
    expect(asset.bytes, size);
    expect(
      asset.durationMs,
      greaterThanOrEqualTo(2000),
      reason: 'Cloudinary must recognise this as 3 s of audio',
    );
    expect(progress.last, 1.0);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the receiver downloads it back with real progress', () async {
    final alert = ForceAudioAlert(
      id: 'live-${DateTime.now().millisecondsSinceEpoch}',
      requestId: 'live-request',
      conversationId: 'c',
      senderId: 's',
      recipientId: 'r',
      mediaUrl: url,
      durationMs: 3000,
      sizeBytes: size,
      state: ForceAudioState.created,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    );

    final progress = <double>[];
    final file = await ForceAudioDownloader(directory: () async => tmp)
        .download(alert, onProgress: progress.add);

    // ignore: avoid_print
    print(
      'download: ${file.path} ${await file.length()} bytes, ${progress.length} progress events, last=${progress.last}',
    );
    expect(await file.exists(), isTrue);
    expect(await file.length(), size);
    expect(progress, isNotEmpty);
    expect(progress.last, 1.0);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'a second play reuses the downloaded file instead of re-fetching',
    () async {
      final alert = ForceAudioAlert(
        id: 'live-cached',
        requestId: 'live-request-2',
        conversationId: 'c',
        senderId: 's',
        recipientId: 'r',
        mediaUrl: url,
        durationMs: 3000,
        sizeBytes: size,
        state: ForceAudioState.delivered,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );
      final downloader = ForceAudioDownloader(directory: () async => tmp);
      await downloader.download(alert);
      final progress = <double>[];
      final again = await downloader.download(alert, onProgress: progress.add);
      // ignore: avoid_print
      print(
        'cached download: ${await again.length()} bytes, progress=$progress',
      );
      expect(progress, [1.0], reason: 'cache hit reports 100% immediately');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  tearDownAll(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });
}

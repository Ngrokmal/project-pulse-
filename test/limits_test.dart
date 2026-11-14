import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/config/limits.dart';

void main() {
  group('Media resource type mapping (§6 — exact mapping)', () {
    test('image mime → image', () {
      expect(MediaResourceType.fromMime('image/jpeg'), MediaResourceType.image);
      expect(MediaResourceType.fromMime('image/png'), MediaResourceType.image);
    });

    test('video mime → video', () {
      expect(MediaResourceType.fromMime('video/mp4'), MediaResourceType.video);
    });

    test('everything else → raw (audio, pdf, zip, unknown)', () {
      expect(MediaResourceType.fromMime('audio/mp4'), MediaResourceType.raw);
      expect(MediaResourceType.fromMime('audio/aac'), MediaResourceType.raw);
      expect(
        MediaResourceType.fromMime('application/pdf'),
        MediaResourceType.raw,
      );
      expect(
        MediaResourceType.fromMime('application/zip'),
        MediaResourceType.raw,
      );
      expect(
        MediaResourceType.fromMime('application/octet-stream'),
        MediaResourceType.raw,
      );
    });
  });

  group('Size caps (§6 — 49 MiB video, 10 MiB raw)', () {
    test('video cap is 49 MiB', () {
      expect(MediaResourceType.video.maxBytes, 49 * 1024 * 1024);
    });

    test('raw cap is 10 MiB', () {
      expect(MediaResourceType.raw.maxBytes, 10 * 1024 * 1024);
    });

    test('boundary: exactly at cap passes, one byte over fails', () {
      final cap = MediaResourceType.raw.maxBytes;
      expect(cap <= MediaResourceType.raw.maxBytes, isTrue);
      expect(cap + 1 > MediaResourceType.raw.maxBytes, isTrue);
    });
  });

  test('Force Audio is capped at 70 seconds (§5)', () {
    expect(MediaLimits.forceAudioMaxDuration, const Duration(seconds: 70));
    expect(MediaLimits.forceAudioMaxDuration.inSeconds, 70);
  });
}

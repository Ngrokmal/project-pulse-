import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/config/app_config.dart';
import 'package:pulse/features/media/domain/media_asset.dart';

void main() {
  group('resource type routing (image → image, video → video, else → raw)', () {
    test('image extensions route to image', () {
      for (final name in ['a.jpg', 'b.JPEG', 'c.png', 'd.webp', 'e.heic']) {
        expect(
          PickedMedia.resourceTypeFor(name),
          MediaResourceType.image,
          reason: name,
        );
      }
    });

    test('video extensions route to video', () {
      for (final name in ['clip.mp4', 'CLIP.MOV', 'v.m4v', 'x.3gp', 'y.webm']) {
        expect(
          PickedMedia.resourceTypeFor(name),
          MediaResourceType.video,
          reason: name,
        );
      }
    });

    test('everything else routes to raw', () {
      for (final name in [
        'doc.pdf',
        'notes.txt',
        'archive.zip',
        'song.mp3',
        'noextension',
        'weird.',
      ]) {
        expect(
          PickedMedia.resourceTypeFor(name),
          MediaResourceType.raw,
          reason: name,
        );
      }
    });
  });

  group('size limits match the spec (video ≤ 49 MiB, raw ≤ 10 MiB)', () {
    test('video limit is 49 MiB', () {
      expect(
        PickedMedia.validateSize(MediaResourceType.video, 49 << 20),
        isNull,
      );
      expect(
        PickedMedia.validateSize(MediaResourceType.video, (49 << 20) + 1),
        contains('49 MB'),
      );
    });

    test('raw limit is 10 MiB', () {
      expect(PickedMedia.validateSize(MediaResourceType.raw, 10 << 20), isNull);
      expect(
        PickedMedia.validateSize(MediaResourceType.raw, (10 << 20) + 1),
        contains('10 MB'),
      );
    });

    test('image limit is 10 MiB', () {
      expect(
        PickedMedia.validateSize(MediaResourceType.image, 10 << 20),
        isNull,
      );
      expect(
        PickedMedia.validateSize(MediaResourceType.image, (10 << 20) + 1),
        isNotNull,
      );
    });

    test('empty files are rejected before any upload', () {
      expect(PickedMedia.validateSize(MediaResourceType.image, 0), isNotNull);
    });
  });

  test('humanSize is readable', () {
    expect(PickedMedia.humanSize(512), '512 B');
    expect(PickedMedia.humanSize(2048), '2 KB');
    expect(PickedMedia.humanSize(5 * 1024 * 1024), '5.0 MB');
  });

  group('CloudinaryAsset.fromJson', () {
    test('reads the fields the bubble needs', () {
      final asset = CloudinaryAsset.fromJson({
        'secure_url': 'https://res.cloudinary.com/x/image/upload/v1/a.jpg',
        'public_id': 'pulse/messages/a',
        'resource_type': 'image',
        'bytes': 148568,
        'format': 'jpg',
        'width': 1080,
        'height': 1350,
      }, MediaResourceType.image);
      expect(asset.resourceType, MediaResourceType.image);
      expect(asset.bytes, 148568);
      expect(asset.width, 1080);
      expect(asset.secureUrl, startsWith('https://res.cloudinary.com/'));
    });

    test('video uploads carry a duration (Cloudinary reports seconds)', () {
      final asset = CloudinaryAsset.fromJson({
        'secure_url': 'https://res.cloudinary.com/x/video/upload/v1/a.mp4',
        'public_id': 'pulse/messages/a',
        'resource_type': 'video',
        'bytes': 1000,
        'duration': 12.6,
      }, MediaResourceType.video);
      expect(asset.resourceType, MediaResourceType.video);
      expect(asset.durationMs, 12600);
    });

    test('unknown resource_type falls back to what we asked for', () {
      final asset = CloudinaryAsset.fromJson({
        'secure_url': 'https://res.cloudinary.com/x/raw/upload/v1/a.txt',
        'public_id': 'pulse/messages/a',
        'resource_type': 'surprise',
        'bytes': 10,
      }, MediaResourceType.raw);
      expect(asset.resourceType, MediaResourceType.raw);
    });
  });

  test('the build knows its Cloudinary cloud name', () {
    // Empty in unit tests (no dart-define); this pins the accessor's contract.
    expect(AppConfig.cloudinaryCloudName, isA<String>());
  });
}

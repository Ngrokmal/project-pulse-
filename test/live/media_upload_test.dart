// Real upload to the real Cloudinary account, with the real progress stream.
//   flutter test test/live/media_upload_test.dart --dart-define=CLOUDINARY_CLOUD_NAME=xxx
// Skips itself when the cloud name is not defined (so CI stays green).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/config/app_config.dart';
import 'package:pulse/features/media/data/cloudinary_uploader.dart';
import 'package:pulse/features/media/domain/media_asset.dart';

void main() {
  const cloud = AppConfig.cloudinaryCloudName;
  if (cloud.isEmpty) {
    test(
      'live media upload',
      () {},
      skip: 'no --dart-define=CLOUDINARY_CLOUD_NAME',
    );
    return;
  }

  test('a real JPEG goes to the image resource', () async {
    // Cloudinary validates image bytes, so use a genuine JPEG from the bundle.
    final file = File('assets/images/welcome_hero.jpg');
    expect(await file.exists(), isTrue, reason: 'run from the repo root');
    final asset = await CloudinaryUploader().upload(
      PickedMedia(
        path: file.path,
        fileName: 'welcome_hero.jpg',
        sizeBytes: await file.length(),
        resourceType: MediaResourceType.image,
      ),
    );
    // ignore: avoid_print
    print('image: ${asset.secureUrl} (${asset.bytes} bytes)');
    expect(asset.secureUrl, startsWith('https://res.cloudinary.com/$cloud/'));
    expect(asset.secureUrl, contains('/image/upload/'));
    expect(asset.resourceType, MediaResourceType.image);
    expect(asset.width, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('progress is real bytes: monotonic, ends at 1.0', () async {
    final tempDir = await Directory.systemTemp.createTemp('pulse');
    final file = File('${tempDir.path}/big.txt');
    // ~4 MB forces many chunks through openRead().
    final sink = file.openWrite();
    for (var i = 0; i < 4096; i++) {
      sink.add(List<int>.filled(1024, 97));
    }
    await sink.close();
    final size = await file.length();

    final progress = <double>[];
    final asset = await CloudinaryUploader().upload(
      PickedMedia(
        path: file.path,
        fileName: 'big.txt',
        sizeBytes: size,
        resourceType: MediaResourceType.raw,
      ),
      onProgress: progress.add,
    );
    // ignore: avoid_print
    print(
      'progress events: ${progress.length} over $size bytes, last=${progress.isEmpty ? 'none' : progress.last}',
    );
    expect(
      progress.length,
      greaterThan(1),
      reason: 'a real stream reports chunks',
    );
    expect(progress.last, 1.0);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
    expect(asset.bytes, size);
    await tempDir.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a text file goes to the raw resource', () async {
    final tempDir = await Directory.systemTemp.createTemp('pulse');
    final file = File('${tempDir.path}/notes.txt');
    await file.writeAsString('Pulse raw-upload probe');
    final asset = await CloudinaryUploader().upload(
      PickedMedia(
        path: file.path,
        fileName: 'notes.txt',
        sizeBytes: await file.length(),
        resourceType: MediaResourceType.raw,
      ),
    );
    // ignore: avoid_print
    print('raw: ${asset.secureUrl}');
    expect(asset.secureUrl, contains('/raw/upload/'));
    await tempDir.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

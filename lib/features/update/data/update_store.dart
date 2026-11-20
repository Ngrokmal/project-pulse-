import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The APK on disk, and the small facts around it.
///
/// The point of this class is the user's rule: **download once**. A finished
/// download is remembered in a sidecar file next to the APK that records the
/// hash it was verified against, so the next launch can prove the file is still
/// the right one by size and sidecar instead of hashing 30 MB on the splash
/// screen — and never downloads it again.
///
/// Only the *download* is remembered. A dismissed prompt is deliberately not
/// written here: "later" has to mean "not this time", not "not ever".
class UpdateStore {
  UpdateStore(this.directory);

  final Directory directory;

  static Future<UpdateStore> open() async {
    // Application *support*, not documents: on Android that is `filesDir`, which
    // is the one directory the app's FileProvider is allowed to hand out — and
    // the installer needs a `content://` URI, never a plain path.
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/updates');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return UpdateStore(dir);
  }

  // The ABI is part of every name: two files for the same build are two
  // different binaries, and reusing the wrong one would be an install of the
  // wrong architecture.
  File apkFile(int versionCode, String abi) =>
      File('${directory.path}/pulse-$versionCode-$abi.apk');

  File _partFile(int versionCode, String abi) =>
      File('${directory.path}/pulse-$versionCode-$abi.apk.part');

  File _stampFile(int versionCode, String abi) =>
      File('${directory.path}/pulse-$versionCode-$abi.apk.ok');

  /// A previously finished download, if it is still exactly what the manifest
  /// describes.
  Future<String?> reusableApk({
    required int versionCode,
    required String abi,
    required String sha256,
    required int sizeBytes,
  }) async {
    final apk = apkFile(versionCode, abi);
    final stamp = _stampFile(versionCode, abi);
    if (!apk.existsSync() || !stamp.existsSync()) return null;
    if (apk.lengthSync() != sizeBytes) return null;
    final verified = (stamp.readAsStringSync()).trim().toLowerCase();
    return verified == sha256.toLowerCase() ? apk.path : null;
  }

  File partFile(int versionCode, String abi) => _partFile(versionCode, abi);

  /// Marks a verified download as good and clears the partial.
  File commit({
    required int versionCode,
    required String abi,
    required String sha256,
  }) {
    final part = _partFile(versionCode, abi);
    final finalFile = apkFile(versionCode, abi);
    if (finalFile.existsSync()) finalFile.deleteSync();
    final moved = part.renameSync(finalFile.path);
    _stampFile(versionCode, abi).writeAsStringSync(sha256.toLowerCase());
    _clearOthers(keep: versionCode);
    return moved;
  }

  void discard(int versionCode, String abi) {
    for (final file in <File>[
      apkFile(versionCode, abi),
      _partFile(versionCode, abi),
      _stampFile(versionCode, abi),
    ]) {
      if (file.existsSync()) file.deleteSync();
    }
  }

  void _clearOthers({required int keep}) {
    if (!directory.existsSync()) return;
    for (final entity in directory.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('pulse-')) continue;
      // Keep this build's files (every ABI of it), drop the rest.
      if (name.startsWith('pulse-$keep-')) continue;
      entity.deleteSync();
    }
  }

}

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The APK on disk, and the small facts around it.
///
/// The point of this class is the user's rule: **download once**. A finished
/// download is remembered in a sidecar file next to the APK that records the
/// hash it was verified against, so the next launch can prove the file is still
/// the right one by size and sidecar instead of hashing 30 MB on the splash
/// screen — and never downloads it again.
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

  File apkFile(int versionCode) =>
      File('${directory.path}/pulse-$versionCode.apk');

  File _partFile(int versionCode) =>
      File('${directory.path}/pulse-$versionCode.apk.part');

  File _stampFile(int versionCode) =>
      File('${directory.path}/pulse-$versionCode.apk.ok');

  File get _stateFile => File('${directory.path}/state.json');

  /// A previously finished download, if it is still exactly what the manifest
  /// describes.
  Future<String?> reusableApk({
    required int versionCode,
    required String sha256,
    required int sizeBytes,
  }) async {
    final apk = apkFile(versionCode);
    final stamp = _stampFile(versionCode);
    if (!apk.existsSync() || !stamp.existsSync()) return null;
    if (apk.lengthSync() != sizeBytes) return null;
    final verified = (stamp.readAsStringSync()).trim().toLowerCase();
    return verified == sha256.toLowerCase() ? apk.path : null;
  }

  File partFile(int versionCode) => _partFile(versionCode);

  /// Marks a verified download as good and clears the partial.
  File commit({required int versionCode, required String sha256}) {
    final part = _partFile(versionCode);
    final finalFile = apkFile(versionCode);
    if (finalFile.existsSync()) finalFile.deleteSync();
    final moved = part.renameSync(finalFile.path);
    _stampFile(versionCode).writeAsStringSync(sha256.toLowerCase());
    _clearOthers(keep: versionCode);
    return moved;
  }

  void discard(int versionCode) {
    for (final file in <File>[
      apkFile(versionCode),
      _partFile(versionCode),
      _stampFile(versionCode),
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
      if (name.startsWith('pulse-$keep.apk')) continue;
      entity.deleteSync();
    }
  }

  Future<int?> skippedVersionCode() async {
    final state = await _readState();
    final value = state['skippedVersionCode'];
    return value is num ? value.toInt() : null;
  }

  Future<void> skipVersion(int versionCode) async {
    final state = await _readState();
    state['skippedVersionCode'] = versionCode;
    await _stateFile.writeAsString(jsonEncode(state));
  }

  Future<void> clearSkip() async {
    final state = await _readState();
    state.remove('skippedVersionCode');
    await _stateFile.writeAsString(jsonEncode(state));
  }

  Future<Map<String, Object?>> _readState() async {
    try {
      if (!_stateFile.existsSync()) return <String, Object?>{};
      final decoded = jsonDecode(_stateFile.readAsStringSync());
      return decoded is Map<String, dynamic>
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
    } on Object {
      return <String, Object?>{};
    }
  }
}

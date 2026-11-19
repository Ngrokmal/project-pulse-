/// One published build, exactly as the release manifest describes it.
///
/// Everything here comes from `latest.json` in the GitHub Release: the version
/// the app should become, where the binary is, how big it is, and the SHA-256 it
/// must hash to before a single byte is handed to the installer. Nothing is
/// guessed and nothing is optional except the changelog.
class AppUpdate {
  const AppUpdate({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.sizeBytes,
    required this.sha256,
    this.notes = const <String>[],
    this.publishedAt,
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;
  final int sizeBytes;

  /// Lowercase hex, 64 characters.
  final String sha256;
  final List<String> notes;
  final DateTime? publishedAt;

  /// A manifest is only usable if it can be downloaded and verified.
  bool get isUsable =>
      versionCode > 0 &&
      apkUrl.startsWith('https://') &&
      sha256.length == 64 &&
      sizeBytes > 0;

  /// Is this build newer than the one running?
  bool isNewerThan(int installedCode) => versionCode > installedCode;

  /// `4.2 MB` — the size a human can reason about.
  String get sizeLabel {
    const kb = 1024;
    const mb = kb * 1024;
    if (sizeBytes >= mb) {
      return '${(sizeBytes / mb).toStringAsFixed(1)} MB';
    }
    if (sizeBytes >= kb) {
      return '${(sizeBytes / kb).round()} KB';
    }
    return '$sizeBytes B';
  }

  static AppUpdate? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final versionName = raw['versionName'];
    final versionCode = raw['versionCode'];
    final apkUrl = raw['apkUrl'];
    final sizeBytes = raw['sizeBytes'];
    final sha256 = raw['sha256'];
    if (versionName is! String ||
        versionCode is! num ||
        apkUrl is! String ||
        sizeBytes is! num ||
        sha256 is! String) {
      return null;
    }

    final notes = <String>[];
    final rawNotes = raw['notes'];
    if (rawNotes is List) {
      for (final note in rawNotes) {
        if (note is String && note.trim().isNotEmpty) notes.add(note.trim());
      }
    }

    final update = AppUpdate(
      versionName: versionName.trim(),
      versionCode: versionCode.toInt(),
      apkUrl: apkUrl.trim(),
      sizeBytes: sizeBytes.toInt(),
      sha256: sha256.trim().toLowerCase(),
      notes: notes,
      publishedAt: DateTime.tryParse('${raw['publishedAt'] ?? ''}'),
    );

    return update.isUsable ? update : null;
  }

  @override
  String toString() => 'AppUpdate($versionName+$versionCode, $sizeLabel)';
}

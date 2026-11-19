/// One downloadable file for one kind of CPU.
///
/// A universal APK carries the native libraries of every architecture; a phone
/// uses exactly one of them. Splitting the build per ABI turns a 67 MB download
/// into a 27 MB one, and this class is the half of that decision the app makes:
/// which file, how big, and which hash it must match.
class UpdateVariant {
  const UpdateVariant({
    required this.apkUrl,
    required this.sizeBytes,
    required this.sha256,
  });

  final String apkUrl;
  final int sizeBytes;

  /// Lowercase hex, 64 characters.
  final String sha256;

  bool get isUsable =>
      apkUrl.startsWith('https://') && sha256.length == 64 && sizeBytes > 0;

  /// `26.4 MB` — a number a person can decide about.
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

  static UpdateVariant? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final apkUrl = raw['apkUrl'];
    final sizeBytes = raw['sizeBytes'];
    final sha256 = raw['sha256'];
    if (apkUrl is! String || sizeBytes is! num || sha256 is! String) {
      return null;
    }
    final variant = UpdateVariant(
      apkUrl: apkUrl.trim(),
      sizeBytes: sizeBytes.toInt(),
      sha256: sha256.trim().toLowerCase(),
    );
    return variant.isUsable ? variant : null;
  }
}

/// One published build, exactly as the release manifest describes it.
///
/// The manifest may carry several files (`arm64`, `arm32`, `x64`) or a single
/// flat one — older releases shipped a universal APK and are still understood,
/// so an installed build never has to be reinstalled by hand just because the
/// channel got smarter.
class AppUpdate {
  const AppUpdate({
    required this.versionName,
    required this.versionCode,
    required this.variants,
    this.notes = const <String>[],
    this.publishedAt,
  });

  final String versionName;
  final int versionCode;

  /// Keyed by ABI: `arm64`, `arm32`, `x64`, or `universal`.
  final Map<String, UpdateVariant> variants;
  final List<String> notes;
  final DateTime? publishedAt;

  bool get isUsable => versionCode > 0 && variants.isNotEmpty;

  /// The file this device should download.
  ///
  /// A universal build serves everyone; otherwise the exact ABI.
  ///
  /// There is deliberately no "nearest match" fallback: an APK built for another
  /// CPU cannot be installed, so offering it would only produce a download that
  /// ends in an Android error.
  UpdateVariant? variantFor(String abi) {
    final exact = variants[abi];
    if (exact != null) return exact;
    return variants['universal'];
  }

  bool isNewerThan(int installedCode) => versionCode > installedCode;

  /// The largest file in the manifest — only used before a device is known.
  String get sizeLabel {
    if (variants.isEmpty) {
      return '—';
    }
    final sizes = variants.values.map((v) => v.sizeBytes).toList()..sort();
    return UpdateVariant(
      apkUrl: 'https://placeholder',
      sizeBytes: sizes.last,
      sha256: '0' * 64,
    ).sizeLabel;
  }

  static AppUpdate? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final versionName = raw['versionName'];
    final versionCode = raw['versionCode'];
    if (versionName is! String || versionCode is! num) return null;

    final variants = <String, UpdateVariant>{};

    // Multi-ABI form: { "abis": { "arm64": {…}, "arm32": {…} } }
    final rawAbis = raw['abis'] ?? raw['variants'];
    if (rawAbis is Map) {
      for (final entry in rawAbis.entries) {
        final variant = UpdateVariant.tryParse(entry.value);
        if (variant != null) variants['${entry.key}'] = variant;
      }
    }

    // Flat form (universal APK, what every release before per-ABI splitting
    // looked like).
    if (variants.isEmpty) {
      final flat = UpdateVariant.tryParse(raw);
      if (flat != null) variants['universal'] = flat;
    }

    if (variants.isEmpty) return null;

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
      variants: variants,
      notes: notes,
      publishedAt: DateTime.tryParse('${raw['publishedAt'] ?? ''}'),
    );

    return update.isUsable ? update : null;
  }

  @override
  String toString() =>
      'AppUpdate($versionName+$versionCode, ${variants.keys.join('/')})';
}

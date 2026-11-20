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
    this.versionCode,
  });

  final String apkUrl;
  final int sizeBytes;

  /// The `versionCode` this exact file declares in its manifest — read out of
  /// the built APK by CI, never computed.
  ///
  /// It is **not** the build number: Android's per-ABI split rule rewrites it to
  /// `ABI_INDEX * 1000 + build`, so an arm64 build 50 really is 2050. Publishing
  /// it lets the app recognise "this is the file I am already running" without
  /// doing that arithmetic itself.
  final int? versionCode;

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
    final versionCode = raw['versionCode'];
    final variant = UpdateVariant(
      apkUrl: apkUrl.trim(),
      sizeBytes: sizeBytes.toInt(),
      sha256: sha256.trim().toLowerCase(),
      versionCode: versionCode is num ? versionCode.toInt() : null,
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
    required this.channelBuild,
    required this.variants,
    this.notes = const <String>[],
    this.publishedAt,
  });

  final String versionName;

  /// The `versionCode` this release is *named* after — for builds published by
  /// CI that is the run number, and it is the number a person reads as "build
  /// 50".
  ///
  /// It is deliberately **not** what the update decision uses: the APK in a
  /// hand carries `ABI_INDEX * 1000 + build` of this value (2050 for arm64), so
  /// comparing the two directly is exactly the bug that made every installed
  /// copy believe it was newer than the channel. See [channelBuild].
  final int versionCode;

  /// The one number that means the same thing on both sides: the build the
  /// channel is on, and the build the app is. Compared by [isNewerThan].
  final int channelBuild;

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

  /// Is this release newer than the build the person is running?
  ///
  /// Three answers, cheapest first:
  ///
  ///  • **channel builds differ** — the normal case, and the only one that
  ///    matters: both numbers are run numbers compiled in by CI, so they cannot
  ///    drift apart the way a raw `versionCode` can;
  ///  • **the same channel build, but a different file** — the APK's own
  ///    `versionCode` for this ABI tells us we are already running this exact
  ///    release, so there is nothing to offer;
  ///  • **nothing known** — say no. Never interrupting someone with an update
  ///    they already have is worth more than guessing.
  bool isNewerThan(
    int installedChannelBuild, {
    String? abi,
    int? installedVersionCode,
  }) {
    if (channelBuild > installedChannelBuild) return true;
    if (channelBuild < installedChannelBuild) return false;
    // Same channel build. Equal files are equal; anything else is not our call.
    return false;
  }

  /// True when [installedVersionCode] is literally one of the files in this
  /// release — the "you already have it" check, by the APK's own identity.
  bool carriesVersionCode(int installedVersionCode) =>
      variants.values.any((v) => v.versionCode == installedVersionCode);

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

    // `channelBuild` is the explicit, unambiguous field. Older manifests (and
    // every build published before this was understood) only carry
    // `versionCode`, which for those *was* the run number — so it is the
    // correct fallback, not a guess.
    final rawChannel = raw['channelBuild'];
    final update = AppUpdate(
      versionName: versionName.trim(),
      versionCode: versionCode.toInt(),
      channelBuild: rawChannel is num
          ? rawChannel.toInt()
          : versionCode.toInt(),
      variants: variants,
      notes: notes,
      publishedAt: DateTime.tryParse('${raw['publishedAt'] ?? ''}'),
    );

    return update.isUsable ? update : null;
  }

  @override
  String toString() =>
      'AppUpdate($versionName, build $channelBuild, '
      '${variants.keys.join('/')})';
}

/// Runtime configuration. Secrets never live in source: values are injected
/// at build time with `--dart-define` (CI: GitHub Actions secrets).
class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const String cloudinaryCloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
  );

  /// True when the minimum backend config is present.
  static bool get isBackendConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Visible in the app (Profile → About, connection check) so a tester can
  /// tell exactly which CI artifact is installed.
  static const String buildLabel = String.fromEnvironment(
    'BUILD_LABEL',
    defaultValue: 'dev',
  );

  /// Which flavour of Supabase key this build carries. New projects use
  /// `sb_publishable_…`; older ones use an anon JWT. Shown in diagnostics.
  static String get keyKind => supabaseAnonKey.startsWith('sb_publishable_')
      ? 'publishable key'
      : supabaseAnonKey.startsWith('eyJ')
      ? 'anon JWT'
      : 'unknown key';

  /// The build this APK *is*, compiled in by CI from the same number that names
  /// the release (`--dart-define=CHANNEL_BUILD=<run number>`).
  ///
  /// This exists because the `versionCode` Android reports is not that number:
  /// a per-ABI split build rewrites it to `ABI_INDEX * 1000 + build`, so an
  /// arm64 build 50 installs as 2050. Comparing the published build number
  /// against 2050 is how every installed copy came to believe it was newer than
  /// the channel and quietly never updated. The app now knows its own build
  /// outright instead of inferring it. `0` means "not built by CI" — see
  /// `InstalledBuild.channelBuild` for the fallback.
  static const int channelBuild = int.fromEnvironment('CHANNEL_BUILD');

  /// Where the app finds out whether it is old.
  ///
  /// A GitHub Release asset, published by CI on every push to `main`: a tiny
  /// JSON written next to the APK in the same release, so the manifest and the
  /// binary it describes can never be out of step. `releases/latest` is resolved
  /// by GitHub, so no server of our own is involved.
  static const String updateManifestUrl =
      'https://github.com/Ngrokmal/project-pulse-/releases/latest/download/latest.json';

  /// Master switch, so a build without a release channel simply never asks.
  static const bool updatesEnabled = true;

  static const String appName = 'Pulse';
  static const String tagline = 'Chat · Call · Connect';
  static const String promise = 'Stay closer, Feel connected';
}

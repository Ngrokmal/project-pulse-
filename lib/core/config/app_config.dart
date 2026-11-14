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

  static const String appName = 'Pulse';
  static const String tagline = 'Chat · Call · Connect';
  static const String promise = 'Stay closer, Feel connected';
}

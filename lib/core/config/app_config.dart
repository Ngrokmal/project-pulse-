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

  static const String appName = 'Pulse';
  static const String tagline = 'Chat · Call · Connect';
  static const String promise = 'Stay closer, Feel connected';
}

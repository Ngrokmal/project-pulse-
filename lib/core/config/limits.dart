/// SINGLE SOURCE OF TRUTH for media limits (master prompt §6 / §19.13).
///
/// Units: binary (MiB). The server (Edge Function) re-validates the same
/// numbers — a client-side check is never trusted on its own.
class MediaLimits {
  MediaLimits._();

  /// 10 MiB — images
  static const int imageMaxBytes = 10 * 1024 * 1024;

  /// 49 MiB — videos
  static const int videoMaxBytes = 49 * 1024 * 1024;

  /// 10 MiB — every other file (audio, pdf, zip, …)
  static const int rawMaxBytes = 10 * 1024 * 1024;

  /// Force Audio is hard-capped at 1m10s (70 s).
  static const Duration forceAudioMaxDuration = Duration(seconds: 70);

  static String humanMiB(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';

  static const Map<String, int> byResourceType = {
    'image': imageMaxBytes,
    'video': videoMaxBytes,
    'raw': rawMaxBytes,
  };
}

/// Cloudinary resource_type mapping — EXACT, never guess (§6).
enum MediaResourceType {
  image,
  video,
  raw;

  /// image → image, video → video, EVERYTHING ELSE → raw.
  static MediaResourceType fromMime(String mime) {
    if (mime.startsWith('image/')) return MediaResourceType.image;
    if (mime.startsWith('video/')) return MediaResourceType.video;
    return MediaResourceType.raw;
  }

  int get maxBytes => switch (this) {
    MediaResourceType.image => MediaLimits.imageMaxBytes,
    MediaResourceType.video => MediaLimits.videoMaxBytes,
    MediaResourceType.raw => MediaLimits.rawMaxBytes,
  };
}

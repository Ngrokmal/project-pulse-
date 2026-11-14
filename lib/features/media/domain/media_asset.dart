/// Cloudinary resource types. The rule from the spec:
///   image → `image`, video → `video`, everything else → `raw`.
enum MediaResourceType { image, video, raw }

/// What the user picked, validated before a single byte is uploaded.
class PickedMedia {
  const PickedMedia({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    required this.resourceType,
  });

  final String path;
  final String fileName;
  final int sizeBytes;
  final MediaResourceType resourceType;

  static const int imageLimit = 10 * 1024 * 1024; // 10 MiB
  static const int videoLimit = 49 * 1024 * 1024; // 49 MiB (spec)
  static const int rawLimit = 10 * 1024 * 1024; // 10 MiB (spec)

  static const Set<String> imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'heic',
    'heif',
    'bmp',
  };
  static const Set<String> videoExtensions = {
    'mp4',
    'mov',
    'm4v',
    '3gp',
    'webm',
    'mkv',
    'avi',
  };

  /// The routing rule, in one place, unit-tested.
  static MediaResourceType resourceTypeFor(String fileName) {
    final ext = extensionOf(fileName);
    if (imageExtensions.contains(ext)) return MediaResourceType.image;
    if (videoExtensions.contains(ext)) return MediaResourceType.video;
    return MediaResourceType.raw;
  }

  static String extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  static int limitFor(MediaResourceType type) => switch (type) {
    MediaResourceType.image => imageLimit,
    MediaResourceType.video => videoLimit,
    MediaResourceType.raw => rawLimit,
  };

  /// Returns null when the file may be uploaded, or a human-readable reason.
  static String? validateSize(MediaResourceType type, int bytes) {
    if (bytes <= 0) return 'That file is empty';
    final limit = limitFor(type);
    if (bytes > limit) {
      final mb = (limit / (1024 * 1024)).round();
      return switch (type) {
        MediaResourceType.video => 'Videos must be $mb MB or smaller',
        MediaResourceType.image => 'Images must be $mb MB or smaller',
        MediaResourceType.raw => 'Files must be $mb MB or smaller',
      };
    }
    return null;
  }

  /// 12.4 MB — used in error text and file cards.
  static String humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// The result of a successful upload.
class CloudinaryAsset {
  const CloudinaryAsset({
    required this.secureUrl,
    required this.publicId,
    required this.resourceType,
    required this.bytes,
    this.format,
    this.width,
    this.height,
    this.durationMs,
  });

  final String secureUrl;
  final String publicId;
  final MediaResourceType resourceType;
  final int bytes;
  final String? format;
  final int? width;
  final int? height;
  final int? durationMs;

  factory CloudinaryAsset.fromJson(
    Map<String, dynamic> json,
    MediaResourceType requested,
  ) => CloudinaryAsset(
    secureUrl: json['secure_url'] as String,
    publicId: json['public_id'] as String,
    resourceType: switch (json['resource_type']) {
      'image' => MediaResourceType.image,
      'video' => MediaResourceType.video,
      'raw' => MediaResourceType.raw,
      _ => requested,
    },
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    format: json['format'] as String?,
    width: (json['width'] as num?)?.toInt(),
    height: (json['height'] as num?)?.toInt(),
    // Cloudinary reports `duration` in **seconds** (a float), not ms.
    durationMs: (json['duration'] as num?) == null
        ? null
        : ((json['duration'] as num) * 1000).round(),
  );
}

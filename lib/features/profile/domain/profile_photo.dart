import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

/// Where a photo came from. Kept as a value so the sheet's "Camera / Gallery"
/// pair is data, not two copied handlers.
enum PhotoSource { camera, gallery }

/// The bytes a person chose, plus the guards the storage bucket enforces.
///
/// Nothing here talks to the network: the domain decides whether a file is
/// acceptable, the repository decides how to send it.
class ProfilePhoto {
  const ProfilePhoto({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;

  /// Mirrors `storage.buckets.file_size_limit` for the avatars bucket (0013).
  static const int maxBytes = 5 * 1024 * 1024;

  /// Mirrors `storage.buckets.allowed_mime_types` (0013).
  static const Set<String> allowedMimeTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  /// A 16×16 crop is never a portrait; below this a photo would be mush.
  static const int minEdge = 64;

  int get sizeBytes => bytes.length;

  /// Null when the file is acceptable, otherwise a sentence for the sheet.
  static String? validate({
    required Uint8List bytes,
    required String mimeType,
  }) {
    if (bytes.isEmpty) return 'That file is empty.';
    if (bytes.length > maxBytes) {
      return 'That photo is larger than 5 MB. Pick a smaller one.';
    }
    if (!allowedMimeTypes.contains(mimeType.toLowerCase())) {
      return 'Pulse accepts JPEG, PNG or WebP photos.';
    }
    return null;
  }

  /// `avatars/<uid>/avatar-<millis>.<ext>` — the first folder must be the
  /// owner's id, because that is exactly what the bucket policy checks.
  static String objectPath({
    required String userId,
    required String mimeType,
    required DateTime at,
  }) {
    return '$userId/avatar-${at.millisecondsSinceEpoch}.${extensionFor(mimeType)}';
  }

  static String extensionFor(String mimeType) =>
      switch (mimeType.toLowerCase()) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };
}

/// The crop a person sets in the studio: a zoom and a pan over a square window.
///
/// The same numbers drive the live preview and the 512×512 image that is
/// uploaded, so what they see is what everyone else gets.
class PhotoCrop {
  const PhotoCrop({this.zoom = minZoom, this.offset = Offset.zero});

  /// The square window the crop is taken through, in logical pixels. The sheet
  /// sizes its stage from this constant so preview and result can never drift.
  static const double window = 184;

  static const double minZoom = 1;
  static const double maxZoom = 2.6;

  /// What is actually written to storage. One square, every surface happy.
  static const int outputEdge = 512;

  final double zoom;
  final Offset offset;

  static const PhotoCrop identity = PhotoCrop();

  PhotoCrop copyWith({double? zoom, Offset? offset}) =>
      PhotoCrop(zoom: zoom ?? this.zoom, offset: offset ?? this.offset);

  PhotoCrop zoomedTo(double value) =>
      copyWith(zoom: value.clamp(minZoom, maxZoom).toDouble());

  /// Pans the photo, keeping the window covered: at zoom 1 there is nowhere to
  /// slide, and the further in you go the further the edges allow.
  PhotoCrop pannedBy(Offset delta, {required Size imageSize}) {
    if (imageSize.isEmpty) return this;
    final limit = _panLimit(imageSize);
    final dx = (offset.dx + delta.dx).clamp(-limit.dx, limit.dx).toDouble();
    final dy = (offset.dy + delta.dy).clamp(-limit.dy, limit.dy).toDouble();
    return copyWith(offset: Offset(dx, dy));
  }

  /// How far the image may slide on each axis, in window pixels.
  Offset _panLimit(Size imageSize) {
    final fit = coverScale(imageSize);
    final scaled = Size(
      imageSize.width * fit * zoom,
      imageSize.height * fit * zoom,
    );
    return Offset(
      math.max(0, (scaled.width - window) / 2),
      math.max(0, (scaled.height - window) / 2),
    );
  }

  /// The scale that makes the image cover the square window.
  static double coverScale(Size imageSize) {
    if (imageSize.isEmpty) return 1;
    return math.max(window / imageSize.width, window / imageSize.height);
  }

  /// The square of the source image that this crop shows, in image pixels.
  ///
  /// Always inside the image, so [ImageShader] and `drawImageRect` both accept
  /// it even after a wild pan.
  Rect sourceRect(Size imageSize) {
    if (imageSize.isEmpty) return Rect.zero;
    final edge = window / (coverScale(imageSize) * zoom);
    final center = Offset(
      imageSize.width / 2 - offset.dx / (coverScale(imageSize) * zoom),
      imageSize.height / 2 - offset.dy / (coverScale(imageSize) * zoom),
    );
    final left = (center.dx - edge / 2).clamp(
      0.0,
      math.max(0.0, imageSize.width - edge),
    );
    final top = (center.dy - edge / 2).clamp(
      0.0,
      math.max(0.0, imageSize.height - edge),
    );
    return Rect.fromLTWH(left.toDouble(), top.toDouble(), edge, edge);
  }

  /// Keeps a crop valid for a new image (a fresh pick always starts at 1× and
  /// re-validates the pan, so switching photos cannot inherit a bad offset).
  PhotoCrop rebasedFor(Size imageSize) => PhotoCrop(
    zoom: zoom.clamp(minZoom, maxZoom).toDouble(),
    offset: Offset(
      offset.dx
          .clamp(-_panLimit(imageSize).dx, _panLimit(imageSize).dx)
          .toDouble(),
      offset.dy
          .clamp(-_panLimit(imageSize).dy, _panLimit(imageSize).dy)
          .toDouble(),
    ),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'zoom': zoom,
    'dx': offset.dx,
    'dy': offset.dy,
  };

  factory PhotoCrop.fromJson(Map<String, Object?> json) => PhotoCrop(
    zoom:
        (json['zoom'] as num?)?.toDouble().clamp(minZoom, maxZoom).toDouble() ??
        minZoom,
    offset: Offset(
      (json['dx'] as num?)?.toDouble() ?? 0,
      (json['dy'] as num?)?.toDouble() ?? 0,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is PhotoCrop && other.zoom == zoom && other.offset == offset;

  @override
  int get hashCode => Object.hash(zoom, offset);
}

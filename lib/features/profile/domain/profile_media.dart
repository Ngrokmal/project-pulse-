/// One attachment pulled from a conversation, for the Media lens.
///
/// This is what the account actually has, not a placeholder mosaic: the lens is
/// empty until the person has sent something.
class ProfileMedia {
  const ProfileMedia({
    required this.id,
    required this.url,
    this.thumbUrl,
    this.kind = 'image',
    this.createdAt,
  });

  final String id;
  final String url;
  final String? thumbUrl;

  /// `image`, `video`, `audio`/`voice`, or anything else → a file.
  final String kind;
  final DateTime? createdAt;

  bool get isImage => kind == 'image';
  bool get isVideo => kind == 'video';
  bool get isAudio => kind == 'audio' || kind == 'voice';

  /// The thumbnail to paint, falling back to the full file for images.
  String? get previewUrl => thumbUrl ?? (isImage ? url : null);

  String get label => switch (kind) {
    'image' => 'Photo',
    'video' => 'Clip',
    'audio' || 'voice' => 'Voice note',
    _ => 'File',
  };

  factory ProfileMedia.fromMap(Map<String, dynamic> map) => ProfileMedia(
    id: map['id'] as String,
    url: (map['media_url'] as String?) ?? '',
    thumbUrl: map['media_thumb_url'] as String?,
    kind: (map['kind'] as String?) ?? 'image',
    createdAt: map['created_at'] == null
        ? null
        : DateTime.tryParse(map['created_at'] as String)?.toLocal(),
  );
}

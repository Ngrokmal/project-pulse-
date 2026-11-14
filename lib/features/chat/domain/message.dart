/// Message kinds, mirroring the `message_kind` enum in 0004_chat.sql.
enum MessageKind { text, image, video, file, audio, forceAudio }

MessageKind messageKindFromDb(String? raw) => switch (raw) {
  'image' => MessageKind.image,
  'video' => MessageKind.video,
  'file' => MessageKind.file,
  'audio' => MessageKind.audio,
  'force_audio' => MessageKind.forceAudio,
  _ => MessageKind.text,
};

String messageKindToDb(MessageKind kind) => switch (kind) {
  MessageKind.text => 'text',
  MessageKind.image => 'image',
  MessageKind.video => 'video',
  MessageKind.file => 'file',
  MessageKind.audio => 'audio',
  MessageKind.forceAudio => 'force_audio',
};

/// Local delivery state. `sent` rows come from the server; `pending` and
/// `failed` rows exist only on this device (the offline outbox).
enum DeliveryState { sent, pending, failed }

class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.kind,
    required this.createdAt,
    this.body,
    this.mediaUrl,
    this.mediaThumbUrl,
    this.mediaBytes,
    this.durationMs,
    this.clientId,
    this.isDeleted = false,
    this.delivery = DeliveryState.sent,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final MessageKind kind;
  final DateTime createdAt;
  final String? body;
  final String? mediaUrl;
  final String? mediaThumbUrl;
  final int? mediaBytes;
  final int? durationMs;
  final String? clientId;
  final bool isDeleted;
  final DeliveryState delivery;

  static const int bodyMax = 4000;

  factory Message.fromMap(Map<String, dynamic> map) => Message(
    id: map['id'] as String,
    conversationId: map['conversation_id'] as String,
    senderId: map['sender_id'] as String,
    kind: messageKindFromDb(map['kind'] as String?),
    createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    body: map['body'] as String?,
    mediaUrl: map['media_url'] as String?,
    mediaThumbUrl: map['media_thumb_url'] as String?,
    mediaBytes: (map['media_bytes'] as num?)?.toInt(),
    durationMs: (map['duration_ms'] as num?)?.toInt(),
    clientId: map['client_id'] as String?,
    isDeleted: map['deleted_at'] != null,
  );

  /// Round-trips through Hive for the offline cache (JSON only, no bindings).
  Map<String, dynamic> toMap() => {
    'id': id,
    'conversation_id': conversationId,
    'sender_id': senderId,
    'kind': messageKindToDb(kind),
    'created_at': createdAt.toUtc().toIso8601String(),
    'body': body,
    'media_url': mediaUrl,
    'media_thumb_url': mediaThumbUrl,
    'media_bytes': mediaBytes,
    'duration_ms': durationMs,
    'client_id': clientId,
    'deleted_at': isDeleted ? createdAt.toUtc().toIso8601String() : null,
  };

  Message copyWith({DeliveryState? delivery, String? id, bool? isDeleted}) =>
      Message(
        id: id ?? this.id,
        conversationId: conversationId,
        senderId: senderId,
        kind: kind,
        createdAt: createdAt,
        body: body,
        mediaUrl: mediaUrl,
        mediaThumbUrl: mediaThumbUrl,
        mediaBytes: mediaBytes,
        durationMs: durationMs,
        clientId: clientId,
        isDeleted: isDeleted ?? this.isDeleted,
        delivery: delivery ?? this.delivery,
      );

  /// What to show in a conversation list preview.
  String get preview => switch (kind) {
    MessageKind.text => body ?? '',
    MessageKind.image => 'Photo',
    MessageKind.video => 'Video',
    MessageKind.audio => 'Voice message',
    MessageKind.forceAudio => 'Force audio alert',
    MessageKind.file => 'Attachment',
  };

  static String? validateBody(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'Message is empty';
    if (value.length > bodyMax) return 'Message is too long (max $bodyMax)';
    return null;
  }
}

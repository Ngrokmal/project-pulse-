import 'package:material_ui/material_ui.dart';

/// Server-enforced limits (§5). The database CHECKs use the same numbers, so a
/// modified client cannot bypass them — these constants exist so the UI can stop
/// recording at 70 s instead of letting the server reject the upload.
class ForceAudioLimits {
  ForceAudioLimits._();

  static const int maxDurationMs = 70000;
  static const int maxBytes = 10 * 1024 * 1024;
  static const int minDurationMs = 500;

  /// True when the recording must be stopped automatically.
  static bool reachedDurationCap(int elapsedMs) => elapsedMs >= maxDurationMs;

  /// Whole seconds left before the cap (never negative).
  static int secondsLeft(int elapsedMs) =>
      ((maxDurationMs - elapsedMs) / 1000).clamp(0, 70).floor();

  static bool isTooShort(int durationMs) => durationMs < minDurationMs;
  static bool isTooLarge(int bytes) => bytes > maxBytes;

  /// mm:ss for the recorder and the bubble.
  static String format(int ms) {
    final total = (ms / 1000).round();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

enum ForceAudioState {
  created,
  delivered,
  played,
  expired;

  static ForceAudioState parse(String? raw) => switch (raw) {
    'delivered' => ForceAudioState.delivered,
    'played' => ForceAudioState.played,
    'expired' => ForceAudioState.expired,
    _ => ForceAudioState.created,
  };

  bool get isTerminal => this == played || this == expired;

  String get wire => name;
}

/// One row of `force_audio_alerts`. The client never trusts a URL from a push:
/// it looks the alert up by id and uses what the server returns.
@immutable
class ForceAudioAlert {
  const ForceAudioAlert({
    required this.id,
    required this.requestId,
    required this.conversationId,
    required this.senderId,
    required this.recipientId,
    required this.mediaUrl,
    required this.durationMs,
    required this.sizeBytes,
    required this.state,
    required this.createdAt,
    required this.expiresAt,
    this.messageId,
    this.mimeType = 'audio/mp4',
    this.playedAt,
  });

  final String id;
  final String requestId;
  final String conversationId;
  final String? messageId;
  final String senderId;
  final String recipientId;
  final String mediaUrl;
  final int durationMs;
  final int sizeBytes;
  final String mimeType;
  final ForceAudioState state;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? playedAt;

  bool get isExpired =>
      state == ForceAudioState.expired || DateTime.now().isAfter(expiresAt);

  String get durationLabel => ForceAudioLimits.format(durationMs);

  factory ForceAudioAlert.fromMap(Map<String, dynamic> map) {
    DateTime read(Object? value, {DateTime? fallback}) {
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value)?.toLocal() ??
            (fallback ?? DateTime.now());
      }
      return fallback ?? DateTime.now();
    }

    return ForceAudioAlert(
      id: map['id'] as String,
      requestId: map['request_id'] as String? ?? '',
      conversationId: map['conversation_id'] as String? ?? '',
      messageId: map['message_id'] as String?,
      senderId: map['sender_id'] as String? ?? '',
      recipientId: map['recipient_id'] as String? ?? '',
      mediaUrl: map['media_url'] as String? ?? '',
      durationMs: (map['duration_ms'] as num?)?.toInt() ?? 0,
      sizeBytes: (map['size_bytes'] as num?)?.toInt() ?? 0,
      mimeType: map['mime_type'] as String? ?? 'audio/mp4',
      state: ForceAudioState.parse(map['state'] as String?),
      createdAt: read(map['created_at']),
      expiresAt: read(
        map['expires_at'],
        fallback: DateTime.now().add(const Duration(hours: 24)),
      ),
      playedAt: map['played_at'] == null ? null : read(map['played_at']),
    );
  }

  ForceAudioAlert copyWith({ForceAudioState? state, DateTime? playedAt}) =>
      ForceAudioAlert(
        id: id,
        requestId: requestId,
        conversationId: conversationId,
        messageId: messageId,
        senderId: senderId,
        recipientId: recipientId,
        mediaUrl: mediaUrl,
        durationMs: durationMs,
        sizeBytes: sizeBytes,
        mimeType: mimeType,
        state: state ?? this.state,
        createdAt: createdAt,
        expiresAt: expiresAt,
        playedAt: playedAt ?? this.playedAt,
      );
}

/// Where the receiver is in the §5 receive pipeline. The UI reads this to show
/// honest text instead of a fake progress bar.
enum ForceAudioReceiveStage {
  idle,
  checking,
  downloading,
  ready,
  playing,
  played,
  expired,
  unauthorized,
  failed,
}

@immutable
class ForceAudioReceiveState {
  const ForceAudioReceiveState({
    this.stage = ForceAudioReceiveStage.idle,
    this.progress = 0,
    this.message,
  });

  final ForceAudioReceiveStage stage;
  final double progress;
  final String? message;

  bool get isBusy =>
      stage == ForceAudioReceiveStage.checking ||
      stage == ForceAudioReceiveStage.downloading;

  ForceAudioReceiveState copyWith({
    ForceAudioReceiveStage? stage,
    double? progress,
    String? message,
  }) => ForceAudioReceiveState(
    stage: stage ?? this.stage,
    progress: progress ?? this.progress,
    message: message ?? this.message,
  );
}

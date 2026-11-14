import 'force_audio_alert.dart';

/// Server side of Force Audio. Alerts are created, read and mutated through
/// PostgREST under RLS; the URL always comes back from the server, never from a
/// push payload.
abstract class ForceAudioRepository {
  Future<ForceAudioAlert> createAlert({
    required String requestId,
    required String conversationId,
    required String recipientId,
    required String mediaUrl,
    required int durationMs,
    required int sizeBytes,
    String? messageId,
    String mimeType,
  });

  Future<ForceAudioAlert?> fetch(String alertId);

  Future<ForceAudioAlert?> fetchByMessage(String messageId);

  Future<void> markDelivered(String alertId);

  /// Idempotent: the DB trigger refuses anything after `played`, so a second
  /// call is treated as success rather than an error to show the user.
  Future<void> markPlayed(String alertId);
}

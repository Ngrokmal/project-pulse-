import 'package:firebase_messaging/firebase_messaging.dart';

/// What the app should do with an incoming push, derived from its payload.
enum PushKind {
  /// A normal chat/call notification.
  message,

  /// The signature Force Audio alert: takes over the screen and plays audio.
  forceAudio,

  /// Anything else the server sends.
  unknown;

  static PushKind fromData(Map<String, dynamic> data) {
    final kind = data['kind']?.toString();
    if (kind == 'force_audio' || data['force_audio_alert_id'] != null) {
      return PushKind.forceAudio;
    }
    if (kind == 'message' || data['chat_id'] != null) return PushKind.message;
    return PushKind.unknown;
  }
}

/// A push reduced to exactly what the UI needs. Kept free of plugin types so it
/// can be unit-tested and rendered without Firebase.
class PushMessage {
  const PushMessage({
    required this.kind,
    required this.title,
    required this.body,
    this.alertId,
    this.chatId,
    this.messageId,
    this.opened = false,
  });

  final PushKind kind;
  final String title;
  final String body;
  final String? alertId;
  final String? chatId;
  final String? messageId;

  /// True when the user tapped the notification (or the app was launched by it).
  /// A foreground push is *not* opened — it only shows the in-app banner.
  final bool opened;

  /// Reads a [RemoteMessage] defensively: pushes can arrive data-only, in which
  /// case the title/body live in `data` instead of `notification`.
  factory PushMessage.fromRemote(RemoteMessage message, {bool opened = false}) {
    final data = message.data;
    final notification = message.notification;
    final title = (notification?.title ?? data['title']?.toString() ?? '')
        .trim();
    final body = (notification?.body ?? data['body']?.toString() ?? '').trim();
    return PushMessage(
      kind: PushKind.fromData(data),
      title: title.isEmpty ? 'Pulse' : title,
      body: body,
      alertId: data['force_audio_alert_id']?.toString(),
      chatId: data['chat_id']?.toString(),
      messageId: message.messageId,
      opened: opened,
    );
  }

  bool get hasBody => body.isNotEmpty;
}

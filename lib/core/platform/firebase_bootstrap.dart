import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';

final _log = AppLogger('firebase');

/// Tracks whether Firebase came up. Push features check this instead of
/// assuming; when it is false the UI shows an honest "notifications
/// unavailable" state rather than a silent no-op.
bool firebaseReady = false;

/// Initialises Firebase once, before the first frame.
///
/// Android reads the generated options from google-services.json. A failure is
/// logged and swallowed: the messenger itself must still work without push
/// (chat is not allowed to depend on notifications).
Future<void> initialiseFirebase() async {
  if (firebaseReady) return;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    firebaseReady = true;
    _log.info('firebase_ready');
  } catch (e) {
    firebaseReady = false;
    _log.error('firebase_init_failed', error: e);
  }
}

/// Must be a top-level, non-anonymous function with a VM entry point: Dart runs
/// it in a separate isolate when a push arrives while the app is in the
/// background.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // Keep this cheap: the isolate is short-lived. Android renders the
  // notification itself from the FCM payload; anything expensive (downloads,
  // Force Audio verification) is rescheduled to the foreground isolate.
  if (kDebugMode) {
    debugPrint('push.background message=${message.messageId}');
  }
}

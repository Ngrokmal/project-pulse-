import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/push_token.dart';

/// Thin, testable wrapper around FirebaseMessaging.
///
/// Every call is guarded: a push failure must degrade the experience (a visible
/// "notifications off" state) and never crash the app or block sign-in.
class PushMessagingService {
  PushMessagingService({FirebaseMessaging? messaging, AppLogger? logger})
    : _messaging = messaging ?? FirebaseMessaging.instance,
      _log = logger ?? AppLogger('push');

  final FirebaseMessaging _messaging;
  final AppLogger _log;

  Future<PushPermission> currentPermission() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      return _map(settings.authorizationStatus);
    } catch (e) {
      _log.warning('push_settings_unavailable');
      return PushPermission.unsupported;
    }
  }

  Future<PushPermission> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      final mapped = _map(settings.authorizationStatus);
      _log.info('push_permission_result', data: {'result': mapped.name});
      return mapped;
    } catch (e) {
      _log.warning('push_permission_failed');
      return PushPermission.unsupported;
    }
  }

  /// The device's FCM registration token, or null when unavailable.
  /// Returning null is explicit — the caller shows a real error, never a fake
  /// "all good" state.
  ///
  /// Deliberate use of the deprecated `getToken()`: FCM's HTTP v1 `token` field
  /// is still fully supported and, per Google's own reference, also accepts a
  /// Firebase Installation ID during the transition to `fid`. The plugin's new
  /// `register()`/`onRegistered` pair only surfaces a FID via a stream, with no
  /// one-shot getter, so a stream race would be introduced for no gain. When the
  /// backend moves to `fid`, this single method changes.
  Future<PushToken?> token() async {
    try {
      // ignore: deprecated_member_use
      final raw = await _messaging.getToken();
      final reason = PushToken.validate(raw);
      if (reason != null) {
        _log.warning('push_token_rejected', data: {'reason': reason});
        return null;
      }
      return PushToken.tryParse(raw);
    } catch (e) {
      _log.error('push_token_unavailable', error: e);
      return null;
    }
  }

  /// Discards the current token. Used when the token is bound to another
  /// account server-side, so a fresh one can be minted and registered.
  Future<PushToken?> renewToken() async {
    try {
      // ignore: deprecated_member_use
      await _messaging.deleteToken();
    } catch (e) {
      _log.warning('push_token_delete_failed');
    }
    return token();
  }

  Stream<PushToken> get tokenRefreshes =>
      // ignore: deprecated_member_use
      _messaging.onTokenRefresh
          .map(PushToken.tryParse)
          .where((t) => t != null)
          .cast<PushToken>();

  /// Foreground messages. Android shows nothing on its own while the app is in
  /// the foreground, so the UI decides what to present (§31).
  Stream<RemoteMessage> get foregroundMessages => FirebaseMessaging.onMessage;

  Future<void> allowForegroundPresentation() async {
    try {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {
      // Non-fatal: the in-app banner still fires.
    }
  }

  /// The plugin reports `deniedPermanently` itself on Android 13+, so the app
  /// never has to guess whether a second permission prompt is worth showing.
  ///
  /// Public and static so the mapping table itself is unit-tested.
  static PushPermission mapStatus(AuthorizationStatus status) =>
      switch (status) {
        AuthorizationStatus.authorized => PushPermission.granted,
        AuthorizationStatus.provisional => PushPermission.granted,
        AuthorizationStatus.denied => PushPermission.denied,
        AuthorizationStatus.deniedPermanently =>
          PushPermission.permanentlyDenied,
        AuthorizationStatus.notDetermined => PushPermission.notRequested,
      };

  PushPermission _map(AuthorizationStatus status) => mapStatus(status);
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notifications/domain/push_token.dart';

/// A thin seam over "what does the OS think about notifications right now".
///
/// Phase 9 needs the *denied* paths to be testable without a device, so the
/// settings screen talks to this interface and never to Firebase directly.
abstract class NotificationSettingsProbe {
  Future<PushPermission> read();
  Future<PushPermission> request();
}

/// Used in tests and whenever Firebase is not available on this build.
class FakeNotificationSettingsProbe implements NotificationSettingsProbe {
  FakeNotificationSettingsProbe(this.permission, {this.afterRequest});

  PushPermission permission;
  PushPermission? afterRequest;
  int reads = 0;
  int requests = 0;

  @override
  Future<PushPermission> read() async {
    reads++;
    return permission;
  }

  @override
  Future<PushPermission> request() async {
    requests++;
    final result = afterRequest ?? permission;
    permission = result;
    return result;
  }
}

/// Set by the app at start-up to the real Firebase-backed implementation.
final notificationProbeProvider = Provider<NotificationSettingsProbe>((ref) {
  return FakeNotificationSettingsProbe(PushPermission.unsupported);
});

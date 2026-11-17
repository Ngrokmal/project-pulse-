import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../data/supabase_presence_repository.dart';
import '../domain/presence.dart';
import '../domain/presence_repository.dart';

final presenceRepositoryProvider = Provider<PresenceRepository>((ref) {
  if (!AppConfig.isBackendConfigured) {
    throw const ConfigurationFailure('Supabase is not configured.');
  }
  return SupabasePresenceRepository(Supabase.instance.client);
});

/// Sends my heartbeat while the app shell is alive.
///
/// Watched once by the shell, so it lasts as long as the signed-in session and
/// stops the moment the user signs out (or the app is torn down). 30 s between
/// beats, with the 90 s window in [Presence] that makes "online" stable.
class PresenceHeartbeat extends Notifier<DateTime?> {
  static const Duration beat = Duration(seconds: 30);

  Timer? _timer;

  @override
  DateTime? build() {
    final auth = ref.watch(authControllerProvider);
    _timer?.cancel();
    _timer = null;
    if (auth is! AuthSignedIn) return null;

    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });

    unawaited(_touch());
    _timer = Timer.periodic(beat, (_) => _touch());
    return DateTime.now();
  }

  Future<void> _touch() async {
    try {
      await ref.read(presenceRepositoryProvider).touch();
    } on AppFailure {
      // Never surface a presence failure to the user; the next beat may work.
    } on Object {
      // Same: presence is a courtesy, not a feature that can break the app.
    }
  }

  /// Asks for an immediate beat (used when the app returns to the foreground).
  Future<void> beatNow() async {
    state = DateTime.now();
    await _touch();
  }
}

final presenceHeartbeatProvider =
    NotifierProvider<PresenceHeartbeat, DateTime?>(PresenceHeartbeat.new);

/// The peer's presence, refreshed while a chat header is on screen.
final peerPresenceProvider = StreamProvider.autoDispose
    .family<Presence, String>((ref, userId) {
      if (userId.isEmpty) return Stream.value(Presence.unknown);
      final repo = ref.watch(presenceRepositoryProvider);
      return _presenceStream(repo, userId);
    });

/// A read failure is not a status: emit one `unknown`, which the UI renders as
/// "offline", and stop — never a stuck spinner, never an invented "online".
Stream<Presence> _presenceStream(
  PresenceRepository repo,
  String userId,
) async* {
  try {
    yield* repo.watch(userId).map((seen) => Presence(lastSeenAt: seen));
  } on Object {
    yield Presence.unknown;
  }
}

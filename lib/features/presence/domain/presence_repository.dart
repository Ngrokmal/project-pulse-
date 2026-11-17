/// Where presence comes from. Implemented over Supabase (`user_presence` +
/// the `touch_presence()` RPC); the UI only ever sees [Presence].
abstract interface class PresenceRepository {
  /// Records that I am alive. Called on start and every 30 s.
  Future<void> touch();

  /// The last heartbeat of [userId], or null when they never sent one.
  Future<DateTime?> lastSeenAt(String userId);

  /// Emits the current value immediately, then keeps emitting while listened to.
  Stream<DateTime?> watch(String userId);
}

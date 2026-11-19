/// The five things a person can be to me, in the vocabulary the reference uses
/// on its result rows. One enum, so a button and a badge can never disagree.
enum FriendState {
  /// Nothing between us yet — the row offers **Add**.
  none,

  /// I asked, they have not answered — **Requested**, tap to cancel.
  requestedByMe,

  /// They asked me — **Asked you**, tap to accept.
  requestedMe,

  /// Accepted — **Friends**, with Message.
  friend,

  /// This row is me — no action, and it says so.
  self;

  static FriendState parse(String? raw) => switch (raw) {
    'requested_by_me' => FriendState.requestedByMe,
    'requested_me' => FriendState.requestedMe,
    'friend' => FriendState.friend,
    'self' => FriendState.self,
    _ => FriendState.none,
  };

  String get wireValue => switch (this) {
    FriendState.requestedByMe => 'requested_by_me',
    FriendState.requestedMe => 'requested_me',
    FriendState.friend => 'friend',
    FriendState.self => 'self',
    FriendState.none => 'none',
  };

  /// Short badge copy; `null` when the action button already says it.
  String? get badge => switch (this) {
    FriendState.requestedMe => 'ASKED YOU',
    FriendState.self => 'THAT’S YOU',
    _ => null,
  };
}

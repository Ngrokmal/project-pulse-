import 'profile_view_mode.dart';

/// Every verb the card can offer.
///
/// The whole point of v4 is that **[ProfileViewMode] decides which of these
/// exist**, not a label string: the owner's card can never show "Block", and a
/// visitor's card can never show "Edit".
enum ProfileAction {
  editCard('Edit your card', ProfileViewMode.owner),
  changePhoto('Change photo', ProfileViewMode.owner),
  shareLink('Share link', ProfileViewMode.owner),
  showCode('Show code', ProfileViewMode.owner),
  copyHandle('Copy handle', ProfileViewMode.owner),
  whoSeesWhat('Who sees what', ProfileViewMode.owner),
  devices('Devices & sessions', ProfileViewMode.owner),
  message('Message', ProfileViewMode.visitor),
  call('Call', ProfileViewMode.visitor),
  video('Video', ProfileViewMode.visitor),
  shareContact('Share contact', ProfileViewMode.visitor),
  pinToTop('Pin to top', ProfileViewMode.visitor),
  quietForToday('Quiet for today', ProfileViewMode.visitor),
  clearChat('Clear this chat', ProfileViewMode.visitor),
  block('Block', ProfileViewMode.visitor),
  report('Report', ProfileViewMode.visitor);

  const ProfileAction(this.label, this.owner);

  final String label;

  /// The one scope this verb belongs to. There is no `both`.
  final ProfileViewMode owner;

  bool allowedFor(ProfileViewMode mode) => owner == mode;

  /// Actions that end something. They are only ever painted in a danger block.
  bool get isDestructive =>
      this == block || this == report || this == clearChat;
}

/// The arrangement of verbs for one scope — the single source the widgets read.
///
/// Tests pin this down: owner and visitor sets must not intersect, and the
/// destructive three must be visitor-only.
abstract final class ProfileScopePlan {
  /// The filled button on the identity card.
  static ProfileAction primary(ProfileViewMode mode) =>
      mode.isVisitor ? ProfileAction.message : ProfileAction.editCard;

  /// The icon buttons beside the primary one.
  static List<ProfileAction> quickActions(ProfileViewMode mode) =>
      mode.isVisitor
      ? const <ProfileAction>[ProfileAction.call, ProfileAction.video]
      : const <ProfileAction>[ProfileAction.shareLink, ProfileAction.showCode];

  /// The rows behind "…", in order.
  static List<ProfileAction> moreSheet(ProfileViewMode mode) => mode.isVisitor
      ? const <ProfileAction>[
          ProfileAction.shareContact,
          ProfileAction.pinToTop,
          ProfileAction.quietForToday,
          ProfileAction.clearChat,
        ]
      : const <ProfileAction>[
          ProfileAction.editCard,
          ProfileAction.changePhoto,
          ProfileAction.shareLink,
          ProfileAction.showCode,
          ProfileAction.whoSeesWhat,
          ProfileAction.devices,
        ];

  /// The block under the danger heading. Empty for the owner, always.
  static List<ProfileAction> dangerRows(ProfileViewMode mode) => mode.isVisitor
      ? const <ProfileAction>[ProfileAction.clearChat, ProfileAction.block]
      : const <ProfileAction>[];

  /// True when this scope may run this verb. Widgets use it as a guard, so a
  /// mis-wired button still cannot do the wrong thing.
  static bool allows(ProfileViewMode mode, ProfileAction action) =>
      action.allowedFor(mode);
}

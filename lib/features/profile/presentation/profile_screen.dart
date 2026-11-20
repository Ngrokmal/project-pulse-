import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../chat/application/chat_controller.dart';
import '../../chat/domain/conversation.dart';
import '../../explore/application/explore_providers.dart';
import '../../explore/domain/person.dart';
import '../../media/presentation/image_viewer.dart';
import '../../notifications/application/push_controller.dart';
import '../../notifications/presentation/push_status_card.dart';
import '../application/profile_controller.dart';
import '../application/profile_view_controller.dart';
import '../domain/profile.dart';
import '../domain/profile_lens.dart';
import '../domain/profile_media.dart';
import '../domain/profile_privacy.dart';
import '../domain/right_now.dart';
import 'sheets/confirm_sheet.dart';
import 'sheets/edit_card_sheet.dart';
import 'sheets/more_with_sheet.dart';
import 'sheets/profile_photo_sheet.dart';
import 'sheets/pulse_sheet.dart';
import 'sheets/qr_code_sheet.dart';
import 'widgets/media_lens.dart';
import 'widgets/people_lens.dart';
import 'widgets/profile_app_bar.dart';
import 'widgets/profile_footer.dart';
import 'widgets/profile_hero.dart';
import 'widgets/profile_identity_card.dart';
import 'widgets/profile_lens_rail.dart';
import 'widgets/pulse_ui.dart';
import 'widgets/settings_lens.dart';
import 'widgets/story_lens.dart';

/// The Profile card — the v3 design, driven entirely by stored values.
///
/// One rule shapes the whole screen: **nothing is inferred**. The Right-now grid
/// captions every value with where it came from, the place is only ever what the
/// owner typed (never GPS, never an IP lookup, never a timezone guess), and there
/// is no listening row because Pulse cannot honestly know what anyone is playing.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final ScrollController _scroll = ScrollController();

  /// The identity card overlaps the hero by exactly this much.
  static const double _overlap = 52;

  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final next = _scroll.hasClients && _scroll.offset > 96;
    if (next != _scrolled) setState(() => _scrolled = next);
  }

  ProfileViewState get _view => ref.read(profileViewProvider);

  Profile? get _profile => ref.read(profileControllerProvider).value;

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileControllerProvider);
    final view = ref.watch(profileViewProvider);
    final profile = profileState.value;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        // A Stack sizes to its non-positioned children — with the bar as the
        // only one, the page below would be clipped to the bar's height.
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: profileState.isLoading && profile == null
                ? const PulseLoading(message: 'Loading your card')
                : profileState.hasError && profile == null
                ? Center(
                    child: PulseErrorState(
                      failure: profileState.error is AppFailure
                          ? profileState.error! as AppFailure
                          : const ServerFailure(),
                      onRetry: () => ref
                          .read(profileControllerProvider.notifier)
                          .refresh(),
                    ),
                  )
                : profile == null
                ? const PulseEmptyState(
                    icon: Icons.lock_outline_rounded,
                    title: 'Not signed in',
                    message: 'Log in to see your card.',
                  )
                : _buildCard(profile, view),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ProfileAppBar(
              scrolled: _scrolled,
              mode: view.mode,
              onBack: () => context.go('/app'),
              onMode: ref.read(profileViewProvider.notifier).setMode,
              onCode: () => _openCode(),
              onMore: () => _openMore(),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────── the card

  Widget _buildCard(Profile profile, ProfileViewState view) {
    final board = RightNowBoard.of(profile: profile, now: DateTime.now());
    final friends = ref.watch(friendsProvider).value ?? const [];
    final conversations = ref.watch(conversationsProvider).value ?? const [];
    final media = ref.watch(profileMediaProvider);
    final auth = ref.watch(authControllerProvider);
    final email = auth is AuthSignedIn ? (auth.user.email ?? '') : '';

    return ListView(
      controller: _scroll,
      padding: EdgeInsets.zero,
      children: [
        ProfileHero(
          initials: profile.initials,
          avatarUrl: profile.avatarUrl,
          isVisitor: view.mode.isVisitor,
          onTapAvatar: _openPhoto,
        ),
        // Paint-only overlap: the card rides up over the hero, while the rail
        // and lenses below keep their own honest spacing.
        Transform.translate(
          offset: const Offset(0, -_overlap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenX,
                ),
                child: ProfileIdentityCard(
                  profile: profile,
                  mode: view.mode,
                  onMessage: () => _toast(
                    view.mode.isVisitor
                        ? 'A message would open here'
                        : 'This is your own card',
                  ),
                  onCall: () => _toast('Calls need a thread to open'),
                  onVideo: () => _toast('Video needs a thread to open'),
                  onMore: _openMore,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenX,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProfileLensRail(
                      lens: view.lens,
                      mode: view.mode,
                      onSelect: ref.read(profileViewProvider.notifier).setLens,
                    ),
                    const SizedBox(height: 18),
                    AnimatedSwitcher(
                      duration: AppMotion.base,
                      switchInCurve: AppMotion.curve,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.015),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: _buildLens(
                        profile: profile,
                        view: view,
                        board: board,
                        email: email,
                        friends: friends,
                        conversations: conversations,
                        media: media,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const ProfileFooter(),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLens({
    required Profile profile,
    required ProfileViewState view,
    required RightNowBoard board,
    required String email,
    required List<Person> friends,
    required List<Conversation> conversations,
    required AsyncValue<List<ProfileMedia>> media,
  }) {
    switch (view.lens) {
      case ProfileLens.story:
        return StoryLens(
          key: const ValueKey('story'),
          profile: profile,
          mode: view.mode,
          board: board,
          maskedEmail: _maskEmail(email),
          onTileTap: _onTileTap,
          onCopyHandle: _copyHandle,
          onCopyLink: _copyLink,
          onAddLabel: _addLabel,
          onRemoveLabel: _removeLabel,
        );

      case ProfileLens.people:
        final faces = <PeopleFace>[
          for (final (index, person) in friends.take(4).indexed)
            PeopleFace(initials: person.initials, tone: index),
        ];
        final circles = <PeopleCircle>[
          for (final conversation
              in conversations.where((c) => c.isGroup).take(3))
            PeopleCircle(
              title: conversation.displayName,
              subtitle: conversation.memberCount == 1
                  ? 'Just you, for now'
                  : '${conversation.memberCount} people in this one',
              initials: conversation.initials,
            ),
        ];
        final knownLine = friends.isEmpty
            ? 'Nobody yet — Explore is where that changes'
            : '${friends.take(3).map((p) => p.displayName.split(RegExp(r'\s+')).first).join(', ')}'
                  '${friends.length > 3 ? ' and others' : ''}';
        return PeopleLens(
          key: const ValueKey('people'),
          faces: faces,
          circles: circles,
          mode: view.mode,
          knownLine: knownLine,
          onOpenCode: _openCode,
        );

      case ProfileLens.media:
        return MediaLens(
          key: const ValueKey('media'),
          state: media,
          onRetry: () => ref.invalidate(profileMediaProvider),
          onOpen: _openMedia,
          onOpenGallery: () => _toast('Opening your shared gallery'),
          onKeepOriginals: () => _toast('Originals export on the way'),
        );

      case ProfileLens.settings:
        return SettingsLens(
          key: const ValueKey('settings'),
          mode: view.mode,
          privacy: profile.privacy,
          onToggle: _togglePrivacy,
          onSaveContact: _shareCard,
          onDanger: _confirmDanger,
          onConnection: () => context.push('/connection'),
          onAbout: _about,
          onLogout: _logout,
          deviceCard: view.mode.isVisitor ? null : const PushStatusCard(),
        );
    }
  }

  // ───────────────────────────────────────────────────────────── actions

  void _onTileTap(RightNowKind kind) {
    switch (kind) {
      case RightNowKind.status:
        if (_view.mode.isVisitor) {
          _toast('They wrote this themselves');
        } else {
          _openEdit();
        }
      case RightNowKind.localTime:
        _toast('Their clock, from the zone on this card');
      case RightNowKind.where:
        _toast('Typed by hand — Pulse never reads GPS');
      case RightNowKind.joined:
        _toast('That is the account date, nothing more');
    }
  }

  Future<void> _openEdit() async {
    final profile = _profile;
    if (profile == null) return;
    final saved = await showPulseSheet<bool>(
      context: context,
      child: EditCardSheet(profile: profile),
    );
    if (!mounted || saved != true) return;
    _toast('Card saved');
  }

  Future<void> _openCode() async {
    final profile = _profile;
    if (profile == null) return;
    await showPulseSheet<bool>(
      context: context,
      child: QrCodeSheet(profile: profile, onCopyLink: _copyLink),
    );
  }

  Future<void> _openPhoto() async {
    final profile = _profile;
    if (profile == null) return;
    await showPulseSheet<bool>(
      context: context,
      child: ProfilePhotoSheet(
        profile: profile,
        onChange: () {
          Navigator.of(context).pop();
          _toast('Photo upload lands with the media pipeline');
        },
      ),
    );
  }

  Future<void> _openMore() async {
    final profile = _profile;
    if (profile == null) return;
    final visiting = _view.mode.isVisitor;
    await showPulseSheet<void>(
      context: context,
      child: MoreWithSheet(
        profile: profile,
        actions: [
          SheetAction(
            icon: Icons.ios_share_rounded,
            title: 'Share contact',
            subtitle: 'Sends a Pulse card, not a number',
            onTap: _shareCard,
          ),
          SheetAction(
            icon: Icons.star_outline_rounded,
            title: 'Pin to the top',
            subtitle: 'Always the first thread you see',
            onTap: () => _toast('Pinned to the top of Home'),
          ),
          SheetAction(
            icon: Icons.dark_mode_outlined,
            title: 'Quiet for today',
            subtitle: 'Messages still arrive, the badge sleeps',
            onTap: () => _toast('Quiet until tomorrow'),
          ),
          if (!visiting)
            SheetAction(
              icon: Icons.edit_outlined,
              title: 'Edit your card',
              subtitle: 'Name, handle, status and where',
              onTap: _openEdit,
            ),
          SheetAction(
            icon: Icons.network_check_rounded,
            title: 'Connection check',
            subtitle: 'What this build can reach',
            onTap: () => context.push('/connection'),
          ),
          SheetAction(
            icon: Icons.delete_outline_rounded,
            title: 'Clear this chat',
            subtitle: 'On this device only',
            danger: true,
            onTap: () => _confirmDanger(
              'Clear this chat?',
              'Every message and file leaves this phone. The other person '
                  'keeps their copy.',
              'Clear',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDanger(String title, String body, String confirm) async {
    final ok = await showPulseSheet<bool>(
      context: context,
      child: ConfirmSheet(title: title, body: body, confirmLabel: confirm),
    );
    if (!mounted || ok != true) return;
    _toast('$confirm done');
  }

  Future<void> _addLabel() async {
    final label = await showDialog<String>(
      context: context,
      builder: (_) => const _LabelDialog(),
    );
    if (!mounted || label == null || label.isEmpty) return;
    final failure = await ref
        .read(profileControllerProvider.notifier)
        .addLabel(label);
    if (!mounted) return;
    _toast(failure == null ? 'Label added' : _describe(failure));
  }

  Future<void> _removeLabel(String label) async {
    await ref.read(profileControllerProvider.notifier).removeLabel(label);
    if (mounted) _toast('$label removed');
  }

  Future<void> _togglePrivacy(PrivacyField field, bool value) async {
    final failure = await ref
        .read(profileControllerProvider.notifier)
        .setPrivacy(field, value);
    if (!mounted) return;
    if (failure != null) _toast(_describe(failure));
  }

  Future<void> _copyHandle() async {
    final handle = _profile?.handle;
    if (handle == null) return;
    await Clipboard.setData(ClipboardData(text: handle));
    _toast('$handle copied');
  }

  Future<void> _copyLink() async {
    final link = _profile?.shareLink;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    _toast('$link copied');
  }

  Future<void> _shareCard() async {
    final profile = _profile;
    if (profile == null) return;
    final link = profile.shareLink;
    if (link == null) {
      _toast('Pick a handle first, so the card has a link');
      return;
    }
    await SharePlus.instance.share(
      ShareParams(text: '${profile.displayName} on Pulse — $link'),
    );
  }

  void _openMedia(ProfileMedia item) {
    if (!item.isImage) {
      _toast('${item.label} — opens in the gallery');
      return;
    }
    ImageViewer.show(context, url: item.url);
  }

  void _about() => showAboutDialog(
    context: context,
    applicationName: 'Pulse',
    applicationVersion: '0.1.0 · build ${AppConfig.buildLabel}',
    children: const [Text('Chat · Call · Connect')],
  );

  Future<void> _logout() async {
    final ok = await showPulseSheet<bool>(
      context: context,
      child: const ConfirmSheet(
        title: 'Log out?',
        body:
            'This phone forgets the session. Your card and your chats stay '
            'exactly as they are.',
        confirmLabel: 'Log out',
      ),
    );
    if (!mounted || ok != true) return;
    await ref.read(pushRegistrationProvider.notifier).handleSignOut();
    await ref.read(authControllerProvider.notifier).signOut();
    if (mounted) context.go('/welcome');
  }

  void _toast(String message) {
    if (mounted) PulseToast.show(context, message);
  }

  static String _maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return email.isEmpty ? 'No address on file' : email;
    final name = email.substring(0, at);
    final keep = name.length <= 2 ? 1 : 2;
    return '${name.substring(0, keep)}••••${email.substring(at)}';
  }

  static String _describe(AppFailure failure) => switch (failure) {
    ValidationFailure(:final userMessage) => userMessage,
    AuthFailure(:final userMessage) => userMessage,
    NetworkFailure() => 'No connection — nothing was lost, try again.',
    _ => 'That did not go through.',
  };
}

class _LabelDialog extends StatefulWidget {
  const _LabelDialog();

  @override
  State<_LabelDialog> createState() => _LabelDialogState();
}

class _LabelDialogState extends State<_LabelDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      title: Text('Add a label', style: AppTypography.titleLarge),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: Profile.labelMax,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'Cricket', counterText: ''),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

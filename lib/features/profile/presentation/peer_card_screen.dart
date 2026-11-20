import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/state_views.dart';
import '../../chat/application/chat_controller.dart';
import '../../explore/domain/person.dart';
import '../../explore/presentation/explore_chat.dart';
import '../../media/presentation/image_viewer.dart';
import '../application/profile_visits_controller.dart';
import '../application/safety_controller.dart';
import '../domain/profile.dart';
import '../domain/profile_scope.dart';
import '../domain/profile_view_mode.dart';
import '../domain/right_now.dart';
import '../domain/safety_action.dart';
import 'sheets/confirm_sheet.dart';
import 'widgets/profile_hero.dart';
import 'widgets/profile_identity_card.dart';
import 'widgets/pulse_ui.dart';
import 'widgets/right_now_grid.dart';

/// **Someone else's card, on its own page.**
///
/// This is the page the Visitor switch on your own card is a preview of: the
/// same hero, the same identity card, the same Right-now grid, read as a visitor
/// reads them. It exists because a name in a search result is a person, not a
/// button — tapping the face or the name should show you who they are before you
/// decide to say anything, and the *Message* button should still do exactly what
/// it says.
///
/// Everything here comes from one read of `profiles` through
/// [peerCardProvider], which is also what records the visit (0015). The photo is
/// dropped server-side when they have switched it off, so a hidden picture
/// cannot leak onto this page.
class PeerCardScreen extends ConsumerWidget {
  const PeerCardScreen({super.key, required this.peerId});

  final String peerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(peerCardProvider(peerId));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: card.when(
        loading: () => const PulseLoading(message: 'Opening the card'),
        error: (error, _) => SafeArea(
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenX,
                  ),
                  child: PulseErrorState(
                    failure: error is AppFailure
                        ? error
                        : const ServerFailure(),
                    onRetry: () => ref.invalidate(peerCardProvider(peerId)),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                left: 12,
                child: _BackButton(
                  onTap: () =>
                      context.canPop() ? context.pop() : context.go('/app'),
                ),
              ),
            ],
          ),
        ),
        data: (profile) => _Card(profile: profile, peerId: peerId),
      ),
    );
  }
}

class _Card extends ConsumerStatefulWidget {
  const _Card({required this.profile, required this.peerId});

  final Profile profile;
  final String peerId;

  @override
  ConsumerState<_Card> createState() => _CardState();
}

class _CardState extends ConsumerState<_Card> {
  /// The identity card rides up over the hero by exactly this much — the same
  /// number the owner's card uses, so both pages look like one product.
  static const double _overlap = 52;

  final ScrollController _scroll = ScrollController();
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

  Profile get _profile => widget.profile;

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navy800,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  /// Opens the real 1:1 thread, through Explore's single entry point, so the
  /// route and the "no conversation yet" case behave exactly as they do
  /// everywhere else.
  Future<void> _message() async {
    await openExploreChat(
      context,
      ref,
      Person(
        id: _profile.id,
        displayName: _profile.displayName,
        handle: _profile.username,
        avatarUrl: _profile.avatarUrl,
      ),
    );
  }

  Future<void> _runSafety(SafetyAction action) async {
    if (action == SafetyAction.block || action == SafetyAction.clearChat) {
      final confirmed = await showPulseConfirm(
        context: context,
        title: action == SafetyAction.block
            ? 'Block ${_profile.givenName}?'
            : 'Clear this chat?',
        message: action == SafetyAction.block
            ? 'Messages and calls stop both ways. They are never told, and you '
                  'can undo it from Blocked people.'
            : 'The thread disappears for you. Nothing is deleted for them.',
        confirmLabel: action == SafetyAction.block ? 'Block' : 'Clear',
      );
      if (confirmed != true || !mounted) return;
    }

    final failure = await ref
        .read(safetyControllerProvider.notifier)
        .run(action, targetUserId: widget.peerId);
    if (!mounted) return;
    if (failure != null) {
      _toast(_describe(failure));
      return;
    }
    switch (action) {
      case SafetyAction.block:
        ref.invalidate(conversationsProvider);
        _toast('Blocked. You can undo this in Blocked people.');
        context.canPop() ? context.pop() : context.go('/app');
      case SafetyAction.clearChat:
        ref.invalidate(conversationsProvider);
        _toast('Cleared for you');
      case SafetyAction.report:
        _toast('Report filed. A human reads every one.');
    }
  }

  static String _describe(AppFailure failure) => switch (failure) {
    NetworkFailure() => 'You are offline. This needs a connection.',
    ServerFailure(:final safeCode) when safeCode == 'already_blocked' =>
      'You had already blocked them.',
    ServerFailure() => 'The server did not accept that. Try again.',
    _ => 'Something went wrong. Try again.',
  };

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final board = RightNowBoard.of(profile: profile, now: DateTime.now());

    return Stack(
      fit: StackFit.expand,
      children: [
        ListView(
          controller: _scroll,
          padding: EdgeInsets.zero,
          children: [
            ProfileHero(
              initials: profile.initials,
              avatarUrl: profile.avatarUrl,
              isVisitor: true,
              onTapAvatar: () {
                final url = profile.avatarUrl;
                if (url == null || url.isEmpty) {
                  _toast('No photo on this card');
                  return;
                }
                ImageViewer.show(
                  context,
                  url: url,
                  title: _profile.displayName,
                );
              },
            ),
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
                      mode: ProfileViewMode.visitor,
                      onAction: _handleAction,
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
                        PulseEyebrow('Right now'),
                        const SizedBox(height: 10),
                        RightNowGrid(
                          board: board,
                          mode: ProfileViewMode.visitor,
                          onTap: (kind) => _toast(_caption(kind)),
                        ),
                        const SizedBox(height: 18),
                        const _QuietActions(),
                        const SizedBox(height: 26),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _Bar(
            scrolled: _scrolled,
            onBack: () => context.canPop() ? context.pop() : context.go('/app'),
            onMore: _openMore,
          ),
        ),
      ],
    );
  }

  static String _caption(RightNowKind kind) => switch (kind) {
    RightNowKind.status => 'They wrote this themselves',
    RightNowKind.localTime => 'Their clock, from the zone on this card',
    RightNowKind.where => 'Typed by hand — Pulse never reads GPS',
    RightNowKind.joined => 'That is the account date, nothing more',
  };

  /// Every verb goes through the same guard the owner's card uses, so a widget
  /// wired to the wrong callback still cannot edit someone else's card.
  void _handleAction(ProfileAction action) {
    if (!ProfileScopePlan.allows(ProfileViewMode.visitor, action)) {
      return;
    }
    switch (action) {
      case ProfileAction.message:
        _message();
      case ProfileAction.call:
      case ProfileAction.video:
        _toast('Calls start from inside a chat');
      case ProfileAction.block:
        _runSafety(SafetyAction.block);
      case ProfileAction.report:
        _runSafety(SafetyAction.report);
      case ProfileAction.clearChat:
        _runSafety(SafetyAction.clearChat);
      case ProfileAction.shareContact:
        _toast('Sharing a contact card is coming from inside a chat');
      case ProfileAction.pinToTop:
      case ProfileAction.quietForToday:
        _toast('That one lives in the chat');
      default:
        _toast('Not something a visitor can do');
    }
  }

  Future<void> _openMore() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x66201C33),
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'More with ${_profile.givenName}',
                style: AppTypography.titleLarge.copyWith(fontSize: 19),
              ),
              const SizedBox(height: 4),
              Text(
                'Everything here acts on this person, right now.',
                style: AppTypography.caption.copyWith(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              PulseRowStack(
                children: [
                  PulseRow(
                    icon: Icons.chat_bubble_outline_rounded,
                    tone: PulseTone.brand,
                    title: 'Message',
                    subtitle: 'Open the thread',
                    trailing: const PulseChevron(),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _message();
                    },
                  ),
                  PulseRow(
                    icon: Icons.block_rounded,
                    tone: PulseTone.bad,
                    title: 'Block',
                    subtitle: 'Quiet, complete, reversible',
                    trailing: const PulseChevron(),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _runSafety(SafetyAction.block);
                    },
                  ),
                  PulseRow(
                    icon: Icons.flag_outlined,
                    tone: PulseTone.bad,
                    title: 'Report',
                    subtitle: 'A human reads every report',
                    trailing: const PulseChevron(),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _runSafety(SafetyAction.report);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuietActions extends StatelessWidget {
  const _QuietActions();

  @override
  Widget build(BuildContext context) {
    return PulseCard(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 15,
            color: AppColors.brand500,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'You are seeing this card the way a visitor does — only what they '
              'chose to share.',
              style: AppTypography.caption.copyWith(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.scrolled,
    required this.onBack,
    required this.onMore,
  });

  final bool scrolled;
  final VoidCallback onBack;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: EdgeInsets.fromLTRB(
        12,
        MediaQuery.paddingOf(context).top + 6,
        12,
        8,
      ),
      color: scrolled
          ? AppColors.bg.withValues(alpha: 0.94)
          : Colors.transparent,
      child: Row(
        children: [
          _BackButton(onTap: onBack, dark: !scrolled),
          const Spacer(),
          Semantics(
            button: true,
            label: 'More options',
            child: Material(
              color: scrolled
                  ? AppColors.card
                  : Colors.white.withValues(alpha: 0.10),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onMore,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.more_horiz_rounded,
                    size: 18,
                    color: scrolled ? AppColors.textPrimary : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap, this.dark = true});

  final VoidCallback onTap;

  /// White glyph on the navy hero, ink on porcelain once scrolled.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: Material(
        color: dark ? Colors.white.withValues(alpha: 0.10) : AppColors.card,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              Icons.arrow_back_rounded,
              size: 18,
              color: dark ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

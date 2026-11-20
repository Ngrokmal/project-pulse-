import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/profile.dart';
import '../../domain/profile_scope.dart';
import '../../domain/profile_view_mode.dart';
import 'pulse_ui.dart';

/// The card that overlaps the hero: who this is, whether they are here, and the
/// things *this* scope may do about it.
///
/// v4 rule: the owner's card reads "Edit your card" and offers share/QR; a
/// visitor's reads "Message" and offers call/video. The three icon buttons are
/// capped at two on purpose — a third squeezed the primary label at 390 px and
/// truncated it to "Edit your ca…".
class ProfileIdentityCard extends StatelessWidget {
  const ProfileIdentityCard({
    super.key,
    required this.profile,
    required this.mode,
    required this.onAction,
  });

  final Profile profile;
  final ProfileViewMode mode;

  /// Every button routes through here; [ProfileScopePlan.allows] is the guard
  /// so a mis-wired widget still cannot edit as a visitor.
  final void Function(ProfileAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final plan = ProfileScopePlan.primary(mode);
    final quick = ProfileScopePlan.quickActions(mode);
    final handle = profile.handle;

    return PulseCard(
      gradientHairline: true,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  profile.displayName.trim().isEmpty
                      ? 'Pulse user'
                      : profile.displayName.trim(),
                  style: AppTypography.headlineMedium.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 7),
              const _VerifiedTick(),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (handle != null) ...[
                Text(
                  handle,
                  style: AppTypography.caption.copyWith(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 3,
                  height: 3,
                  decoration: const BoxDecoration(
                    color: Color(0xFFC9C4DA),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Your own card never claims a presence: you are looking at a
              // record, not at someone who is online.
              if (mode.isVisitor) const _LiveChip() else const _OwnerChip(),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _PrimaryCta(action: plan, onTap: () => onAction(plan)),
              ),
              for (final action in quick) ...[
                const SizedBox(width: 9),
                _GhostCta(
                  icon: _iconFor(action),
                  tip: action.label,
                  onTap: () => onAction(action),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(ProfileAction action) => switch (action) {
    ProfileAction.shareLink => Icons.ios_share_rounded,
    ProfileAction.showCode => Icons.qr_code_2_rounded,
    ProfileAction.call => Icons.call_outlined,
    ProfileAction.video => Icons.videocam_outlined,
    ProfileAction.changePhoto => Icons.photo_camera_rounded,
    ProfileAction.copyHandle => Icons.copy_rounded,
    ProfileAction.editCard => Icons.edit_outlined,
    ProfileAction.whoSeesWhat => Icons.visibility_outlined,
    ProfileAction.devices => Icons.devices_outlined,
    ProfileAction.clearChat => Icons.delete_outline_rounded,
    ProfileAction.block => Icons.block_rounded,
    ProfileAction.report => Icons.flag_outlined,
    ProfileAction.shareContact => Icons.person_add_alt_1_outlined,
    ProfileAction.pinToTop => Icons.push_pin_outlined,
    ProfileAction.quietForToday => Icons.notifications_off_outlined,
    ProfileAction.message => Icons.chat_bubble_outline_rounded,
  };
}

class _VerifiedTick extends StatelessWidget {
  const _VerifiedTick();

  @override
  Widget build(BuildContext context) => Container(
    width: 19,
    height: 19,
    decoration: const BoxDecoration(
      gradient: AppColors.primaryGradient,
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
  );
}

/// A visitor sees the presence bead; it is the only claim of "now" on the card
/// and it comes from the presence service, never from a guess.
class _LiveChip extends StatelessWidget {
  const _LiveChip();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: AppColors.online,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        'Active now',
        style: AppTypography.caption.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.success,
        ),
      ),
    ],
  );
}

/// The owner's chip: a lock, and the plain statement that this is theirs.
class _OwnerChip extends StatelessWidget {
  const _OwnerChip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.brand100,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.lock_outline_rounded,
          size: 12,
          color: AppColors.brand700,
        ),
        const SizedBox(width: 5),
        Text(
          'Only you can edit this',
          style: AppTypography.caption.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.brand700,
          ),
        ),
      ],
    ),
  );
}

class _PrimaryCta extends StatefulWidget {
  const _PrimaryCta({required this.action, required this.onTap});

  final ProfileAction action;
  final VoidCallback onTap;

  @override
  State<_PrimaryCta> createState() => _PrimaryCtaState();
}

class _PrimaryCtaState extends State<_PrimaryCta> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.action == ProfileAction.editCard;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        duration: AppMotion.fast,
        scale: _down ? 0.97 : 1,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(AppRadius.sm + 4),
            boxShadow: AppShadows.glowPrimary,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned.fill(child: _Sheen()),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isEdit
                        ? Icons.edit_outlined
                        : Icons.chat_bubble_outline_rounded,
                    size: 17,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.action.label,
                      style: AppTypography.buttonLabel.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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

class _Sheen extends StatefulWidget {
  const _Sheen();

  @override
  State<_Sheen> createState() => _SheenState();
}

class _SheenState extends State<_Sheen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return FractionallySizedBox(
            alignment: Alignment(-1.6 + t * 3.2, 1),
            widthFactor: 0.45,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: 0.22),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GhostCta extends StatelessWidget {
  const _GhostCta({required this.icon, required this.onTap, required this.tip});

  final IconData icon;
  final VoidCallback onTap;
  final String tip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.sm + 4),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 19, color: AppColors.brand600),
        ),
      ),
    );
  }
}

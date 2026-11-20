import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/profile.dart';
import '../../domain/profile_view_mode.dart';
import 'pulse_ui.dart';

/// The card that overlaps the hero: who this is, whether they are here, and the
/// four things you can do about it.
class ProfileIdentityCard extends StatelessWidget {
  const ProfileIdentityCard({
    super.key,
    required this.profile,
    required this.mode,
    required this.onMessage,
    required this.onCall,
    required this.onVideo,
    required this.onMore,
  });

  final Profile profile;
  final ProfileViewMode mode;
  final VoidCallback onMessage;
  final VoidCallback onCall;
  final VoidCallback onVideo;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
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
              const _HereChip(),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 5,
                child: _PrimaryCta(
                  label: mode.isVisitor ? 'Message' : 'Open my chat',
                  onTap: onMessage,
                ),
              ),
              const SizedBox(width: 9),
              _GhostCta(icon: Icons.call_outlined, onTap: onCall, tip: 'Call'),
              const SizedBox(width: 9),
              _GhostCta(
                icon: Icons.videocam_outlined,
                onTap: onVideo,
                tip: 'Video',
              ),
              const SizedBox(width: 9),
              _GhostCta(
                icon: Icons.more_horiz_rounded,
                onTap: onMore,
                tip: 'More',
              ),
            ],
          ),
        ],
      ),
    );
  }
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

/// "Active now" — the honest one: you are looking at your own card inside the
/// app, so the person is here.
class _HereChip extends StatelessWidget {
  const _HereChip();

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

class _PrimaryCta extends StatefulWidget {
  const _PrimaryCta({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_PrimaryCta> createState() => _PrimaryCtaState();
}

class _PrimaryCtaState extends State<_PrimaryCta> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
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
              // A slow sheen, so the primary button is never quite still.
              const Positioned.fill(child: _Sheen()),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 17,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.label,
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
    return Tooltip(
      message: tip,
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

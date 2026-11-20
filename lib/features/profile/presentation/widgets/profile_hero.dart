import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import 'pulse_waveform.dart';

/// The one saturated surface on the card.
///
/// Everything below it is porcelain; this is the splash navy the app opens
/// with, so the profile is visibly the same product rather than a poster next
/// to it. The avatar sits in a slowly rotating conic ring, and a green ping says
/// the person is here — the only two moving things in the hero.
class ProfileHero extends StatefulWidget {
  const ProfileHero({
    super.key,
    required this.initials,
    required this.avatarUrl,
    required this.onTapAvatar,
    required this.isVisitor,
  });

  final String initials;
  final String? avatarUrl;
  final VoidCallback onTapAvatar;
  final bool isVisitor;

  /// Space the app bar sits in, plus a little air under it.
  static const double appBarInset = 58;

  @override
  State<ProfileHero> createState() => _ProfileHeroState();
}

class _ProfileHeroState extends State<ProfileHero>
    with TickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );
  late final AnimationController _ping = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _ring.stop();
      _ping.stop();
      _ping.value = 0.18;
    } else {
      if (!_ring.isAnimating) _ring.repeat();
      if (!_ping.isAnimating) _ping.repeat();
    }
  }

  @override
  void dispose() {
    _ring.dispose();
    _ping.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: topInset + ProfileHero.appBarInset,
        bottom: 74,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.navy700, AppColors.navy800, AppColors.navy900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0, 0.55, 1],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Two soft blooms, painted not photographed.
          Positioned(
            left: -60,
            top: -30,
            child: _Bloom(
              color: AppColors.brand600.withValues(alpha: 0.55),
              size: 230,
            ),
          ),
          Positioned(
            right: -50,
            top: 40,
            child: _Bloom(
              color: AppColors.blue500.withValues(alpha: 0.42),
              size: 210,
            ),
          ),
          Column(
            children: [
              const SizedBox(height: 6),
              _Orb(
                initials: widget.initials,
                avatarUrl: widget.avatarUrl,
                ring: _ring,
                ping: _ping,
                onTap: widget.onTapAvatar,
              ),
              const SizedBox(height: 18),
              // The trace sits *behind* the orb in the reference; here it is
              // pulled up so the two read as one object.
              Transform.translate(
                offset: const Offset(0, -46),
                child: const PulseWaveform(height: 74),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bloom extends StatelessWidget {
  const _Bloom({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    ),
  );
}

class _Orb extends StatelessWidget {
  const _Orb({
    required this.initials,
    required this.avatarUrl,
    required this.ring,
    required this.ping,
    required this.onTap,
  });

  final String initials;
  final String? avatarUrl;
  final AnimationController ring;
  final AnimationController ping;
  final VoidCallback onTap;

  static const double _size = 118;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: _size + 22,
        height: _size + 22,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The conic ring: brand purple → blue → violet, turning forever.
            AnimatedBuilder(
              animation: ring,
              builder: (context, _) => Transform.rotate(
                angle: ring.value * 2 * math.pi,
                child: Container(
                  width: _size + 20,
                  height: _size + 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const SweepGradient(
                      colors: [
                        AppColors.brand300,
                        AppColors.brand600,
                        AppColors.blue500,
                        AppColors.blue300,
                        AppColors.brand300,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brand500.withValues(alpha: 0.5),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // The dark gap that makes the ring read as a ring.
            Container(
              width: _size + 8,
              height: _size + 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.navy900,
              ),
            ),
            _Face(initials: initials, avatarUrl: avatarUrl, size: _size),
            Positioned(
              right: 4,
              bottom: 8,
              child: _PresencePing(controller: ping),
            ),
          ],
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.initials, required this.avatarUrl, required this.size});

  final String initials;
  final String? avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.brand400, AppColors.brand700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: url == null || url.isEmpty
          ? Text(
              initials,
              style: AppTypography.displaySmall.copyWith(
                color: Colors.white,
                fontSize: size * 0.34,
                fontWeight: FontWeight.w700,
              ),
            )
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Text(
                  initials,
                  style: AppTypography.displaySmall.copyWith(
                    color: Colors.white,
                    fontSize: size * 0.34,
                  ),
                ),
              ),
            ),
    );
  }
}

class _PresencePing extends StatelessWidget {
  const _PresencePing({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        return SizedBox(
          width: 34,
          height: 34,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t) * 0.55,
                child: Container(
                  width: 16 + t * 16,
                  height: 16 + t * 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.online, width: 1.6),
                  ),
                ),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.online,
                  border: Border.all(color: AppColors.navy900, width: 2.4),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.online.withValues(alpha: 0.55),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A frosted hairline used where the hero meets the porcelain.
class HeroSeam extends StatelessWidget {
  const HeroSeam({super.key});

  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 0.01, sigmaY: 0.01),
      child: Container(
        height: 1,
        color: Colors.white.withValues(alpha: 0.16),
      ),
    ),
  );
}

/// The hero's own vertical rhythm, so the screen can reserve it exactly.
const double profileHeroMinHeight = 168 + ProfileHero.appBarInset + 74;

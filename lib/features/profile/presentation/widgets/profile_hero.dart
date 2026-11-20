import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import 'orbit_ring.dart';
import 'pulse_waveform.dart';

/// The one saturated surface on the card.
///
/// Everything below it is porcelain; this is the splash navy the app opens
/// with, so the profile is visibly the same product rather than a poster next
/// to it. The avatar sits in the v4 aperture ring; the only other moving things
/// are the glass sheen and, for a visitor, the presence bead.
class ProfileHero extends StatelessWidget {
  const ProfileHero({
    super.key,
    required this.initials,
    required this.avatarUrl,
    required this.onTapAvatar,
    required this.isVisitor,
    this.onChangePhoto,
    this.party = false,
  });

  final String initials;
  final String? avatarUrl;
  final VoidCallback onTapAvatar;

  /// The camera bead only exists on your own card.
  final VoidCallback? onChangePhoto;

  final bool isVisitor;

  /// Adds the small "preview" veil so a visitor lens never looks like editing.
  final bool party;

  /// Space the app bar sits in, plus a little air under it.
  static const double appBarInset = 58;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(top: topInset + appBarInset, bottom: 54),
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
              OrbitRing(
                faceSize: 118,
                onTap: onTapAvatar,
                face: _Face(
                  initials: initials,
                  avatarUrl: avatarUrl,
                  size: 118,
                ),
                overlay: isVisitor ? const _PresenceBead() : null,
                badge: onChangePhoto == null
                    ? null
                    : _CameraBead(onTap: onChangePhoto!, initials: initials),
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
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}

/// The glass: initials or photo, with a specular sweep crossing it once a cycle.
class _Face extends StatefulWidget {
  const _Face({
    required this.initials,
    required this.avatarUrl,
    required this.size,
  });

  final String initials;
  final String? avatarUrl;
  final double size;

  @override
  State<_Face> createState() => _FaceState();
}

class _FaceState extends State<_Face> with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 7600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _sheen
        ..stop()
        ..value = 0.9;
    } else if (!_sheen.isAnimating) {
      _sheen.repeat();
    }
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.avatarUrl;
    final size = widget.size;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [
            AppColors.brand400,
            AppColors.brand600,
            AppColors.brand800,
            Color(0xFF2E1076),
          ],
          stops: [0, 0.4, 0.78, 1],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.30),
            spreadRadius: 1,
          ),
          BoxShadow(
            color: const Color(0xFF0C062C).withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url == null || url.isEmpty)
              Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.36, -0.68),
                    radius: 1.15,
                    colors: [
                      Color(0x4DFFFFFF),
                      Color(0x00FFFFFF),
                      Color(0x5A1C084A),
                    ],
                    stops: [0, 0.46, 1],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.initials,
                  style: AppTypography.displaySmall.copyWith(
                    color: Colors.white,
                    fontSize: size * 0.34,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: AppColors.brand600,
                  child: Center(
                    child: Text(
                      widget.initials,
                      style: AppTypography.displaySmall.copyWith(
                        color: Colors.white,
                        fontSize: size * 0.34,
                      ),
                    ),
                  ),
                ),
              ),
            // the sheen: one band of light crossing the glass, then a rest
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _sheen,
                builder: (context, _) {
                  final t = _sheen.value;
                  final travel = t < 0.58 ? 0.0 : (t - 0.58) / 0.26;
                  if (t >= 0.84) return const SizedBox.shrink();
                  return Transform.translate(
                    offset: Offset(-size * 1.1 + travel.clamp(0, 1) * size * 2.2, 0),
                    child: Transform.rotate(
                      angle: -0.32,
                      child: Container(
                        width: size * 0.42,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0),
                              Colors.white.withValues(alpha: 0.42),
                              Colors.white.withValues(alpha: 0.05),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The owner's affordance: a camera bead that breathes a halo once a cycle, so
/// "change my photo" is found without opening a menu.
class _CameraBead extends StatefulWidget {
  const _CameraBead({required this.onTap, required this.initials});

  final VoidCallback onTap;
  final String initials;

  @override
  State<_CameraBead> createState() => _CameraBeadState();
}

class _CameraBeadState extends State<_CameraBead>
    with SingleTickerProviderStateMixin {
  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _halo
        ..stop()
        ..value = 0.5;
    } else if (!_halo.isAnimating) {
      _halo.repeat();
    }
  }

  @override
  void dispose() {
    _halo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Change your photo',
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _halo,
                builder: (context, _) {
                  final t = _halo.value;
                  final wave = t < 0.46 ? t / 0.46 : 0.0;
                  return IgnorePointer(
                    child: Opacity(
                      opacity: (1 - wave) * 0.7,
                      child: Container(
                        width: 30 + wave * 12,
                        height: 30 + wave * 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.55),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0E0830).withValues(alpha: 0.42),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.photo_camera_rounded,
                  size: 15,
                  color: AppColors.brand600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresenceBead extends StatelessWidget {
  const _PresenceBead();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.online,
        border: Border.all(color: AppColors.navy900, width: 2.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.online.withValues(alpha: 0.6),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
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
      child: Container(height: 1, color: Colors.white.withValues(alpha: 0.16)),
    ),
  );
}

/// The hero's own vertical rhythm, so the screen can reserve it exactly.
const double profileHeroMinHeight = 168 + ProfileHero.appBarInset + 54;

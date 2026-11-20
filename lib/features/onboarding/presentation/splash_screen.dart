import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/pulse_mark.dart';
import '../../auth/application/auth_controller.dart';
import '../../update/application/update_controller.dart';

/// Splash / brand intro (§26): brief, elegant, skippable in effect — it never
/// blocks a valid session longer than the animation itself.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  Timer? _holdTimer;
  Timer? _safetyTimer;
  bool _routed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _scale = Tween<double>(
      begin: 0.82,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: AppMotion.curve));
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.6, curve: Curves.easeOut),
    );
    _controller.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // Read context-dependent state before any await (no context across gaps).
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // Restore session (never throws) — done in parallel with the animation.
    // Is there a newer build? The question is asked *alongside* the session
    // restore, not after it, and it gives up after 2.5 s: an update may interrupt
    // a launch, but a slow release channel never may.
    final updateCheck = ref
        .read(updateControllerProvider.notifier)
        .checkAtBoot();

    if (AppConfig.isBackendConfigured) {
      await ref.read(authControllerProvider.notifier).restore();
    }
    await updateCheck;
    if (!mounted) return;
    final hold = reduce ? Duration.zero : AppMotion.splashHold;
    _holdTimer = Timer(hold, _routeNext);
    // Safety net: never stay on splash forever.
    _safetyTimer = Timer(const Duration(seconds: 6), _routeNext);
  }

  void _routeNext() {
    if (!mounted || _routed) return;
    _routed = true;
    final auth = ref.read(authControllerProvider);

    // A published update is the first thing the app says, before the shell: it is
    // the only way a sideloaded build ever becomes a newer one.
    if (ref.read(updateControllerProvider).shouldPrompt) {
      context.go('/update');
      return;
    }

    context.go(auth is AuthSignedIn ? '/app' : '/welcome');
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _safetyTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.darkSystemUi,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.splashGradient),
          child: Stack(
            children: [
              // Atmospheric glow — cheap radial painters, no blur filters.
              Positioned(
                top: -140,
                right: -100,
                child: _Glow(
                  color: AppColors.brand500.withValues(alpha: 0.42),
                  size: 420,
                ),
              ),
              Positioned(
                bottom: -160,
                left: -120,
                child: _Glow(
                  color: AppColors.blue500.withValues(alpha: 0.30),
                  size: 380,
                ),
              ),
              Center(
                child: FadeTransition(
                  opacity: _fade,
                  child: ScaleTransition(
                    scale: _scale,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PulseWordmark(
                          markSize: 96,
                          fontSize: 44,
                          showTagline: true,
                        ),
                        SizedBox(height: 30),
                        _PulseHalo(),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 42,
                child: Column(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(
                          Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppConfig.promise,
                      style: AppTypography.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.55),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0, 1],
          ),
        ),
      ),
    );
  }
}

/// A slow heartbeat halo behind the wordmark — the product's motion signature.
class _PulseHalo extends StatefulWidget {
  const _PulseHalo();

  @override
  State<_PulseHalo> createState() => _PulseHaloState();
}

class _PulseHaloState extends State<_PulseHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return const SizedBox(height: 6);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        return Container(
          width: 70 + t * 26,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: AppColors.brand300.withValues(alpha: 0.25 + t * 0.35),
          ),
        );
      },
    );
  }
}

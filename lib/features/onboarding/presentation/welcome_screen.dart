import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/pulse_mark.dart';

/// Welcome screen — the atmospheric reference screen (§4 A).
/// Uses the full viewport: hero photography + navy gradient overlay + brand
/// block + single primary CTA. No phone frame, no miniaturised UI.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Keep the composition readable on very tall and very short devices.
    final heroHeight = size.height * 0.62;
    final compact = size.height < 680;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.navy900,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              SizedBox(
                height: heroHeight,
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(AppRadius.sheet),
                    bottomRight: Radius.circular(AppRadius.sheet),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/images/welcome_hero.jpg',
                        fit: BoxFit.cover,
                        // Decode at display size: keeps memory low and scroll smooth (§10).
                        cacheHeight:
                            (heroHeight *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round(),
                        semanticLabel: 'A calm lake at sunset',
                        errorBuilder: (_, _, _) => const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppColors.splashGradient,
                          ),
                        ),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x33191B73),
                              Color(0x880A0E51),
                              AppColors.navy900,
                            ],
                            stops: [0, 0.55, 1],
                          ),
                        ),
                      ),
                      Align(
                        alignment: const Alignment(0, -0.05),
                        child: PulseWordmark(
                          markSize: compact ? 72 : 88,
                          fontSize: compact ? 38 : 44,
                          showTagline: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        AppConfig.promise,
                        textAlign: TextAlign.center,
                        style: AppTypography.titleLarge.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: compact ? 17 : 19,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Messages, group calls and voice notes — in one calm place.',
                        textAlign: TextAlign.center,
                        style: AppTypography.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
                ),
                child: Column(
                  children: [
                    GradientButton(
                      label: 'Get Started',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: () => context.push('/auth?mode=signup'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => context.push('/auth?mode=login'),
                      child: Text(
                        'I already have an account',
                        style: AppTypography.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w600,
                        ),
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

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/pulse_mark.dart';
import '../../auth/application/auth_controller.dart';

/// Profile. Shows the real signed-in identity and a working sign-out.
/// Profile editing, media and friend counts arrive with Phase 2–3 data.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, required this.email});

  final String email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final name = auth is AuthSignedIn
        ? (auth.user.displayName ?? 'Pulse user')
        : 'Pulse user';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenX,
            18,
            AppSpacing.screenX,
            28,
          ),
          children: [
            Text('Profile', style: AppTypography.headlineMedium),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: AppRadius.cardRadius,
                border: Border.all(color: AppColors.border),
                boxShadow: AppShadows.card,
              ),
              child: Row(
                children: [
                  const PulseMark(size: 60),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: AppTypography.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          email.isEmpty ? 'Signed in' : email,
                          style: AppTypography.caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _Row(
              icon: Icons.info_outline_rounded,
              label: 'About Pulse',
              trailing: 'v0.1.0',
              onTap: () => showAboutDialog(
                context: context,
                applicationName: AppConfig.appName,
                applicationVersion: '0.1.0 (Phase 1)',
                children: const [Text('Chat · Call · Connect')],
              ),
            ),
            if (kDebugMode)
              _Row(
                icon: Icons.palette_outlined,
                label: 'Design system',
                trailing: 'debug',
                onTap: () => context.push('/design'),
              ),
            const SizedBox(height: 24),
            GradientButton(
              label: 'Log out',
              onPressed: () async {
                await ref.read(authControllerProvider.notifier).signOut();
                if (context.mounted) context.go('/welcome');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.card,
        borderRadius: AppRadius.cardRadius,
        child: InkWell(
          borderRadius: AppRadius.cardRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.brand500),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: AppTypography.titleMedium)),
                if (trailing != null)
                  Text(trailing!, style: AppTypography.caption),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../device/application/device_registration_controller.dart';
import '../../notifications/application/push_controller.dart';
import '../../notifications/presentation/push_status_card.dart';
import '../application/profile_controller.dart';
import '../domain/profile.dart';

/// Profile — reads the real row protected by RLS (migrations/0001).
/// Loading, error, retry and signed-out states are all explicit.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(profileControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final email = auth is AuthSignedIn ? (auth.user.email ?? '') : '';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(profileControllerProvider.notifier).refresh(),
          child: profileState.when(
            loading: () => const PulseLoading(message: 'Loading your profile'),
            error: (error, _) => ListView(
              children: [
                const SizedBox(height: 80),
                PulseErrorState(
                  failure: error is AppFailure ? error : const ServerFailure(),
                  onRetry: () =>
                      ref.read(profileControllerProvider.notifier).refresh(),
                ),
              ],
            ),
            data: (profile) => profile == null
                ? const PulseEmptyState(
                    icon: Icons.lock_outline_rounded,
                    title: 'Not signed in',
                    message: 'Log in to see your profile.',
                  )
                : _ProfileBody(profile: profile, email: email),
          ),
        ),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile, required this.email});

  final Profile profile;
  final String email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(deviceRegistrationControllerProvider);
    final joined = profile.joinedAt == null
        ? null
        : DateFormat('MMM yyyy').format(profile.joinedAt!);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenX,
        18,
        AppSpacing.screenX,
        28,
      ),
      children: [
        Row(
          children: [
            Text('Profile', style: AppTypography.headlineMedium),
            const Spacer(),
            IconButton(
              tooltip: 'Edit profile',
              onPressed: () => context.push('/profile/edit'),
              icon: const Icon(Icons.edit_outlined, color: AppColors.brand600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      profile.initials,
                      style: AppTypography.titleLarge.copyWith(
                        color: AppColors.onPrimary,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.displayName.isEmpty
                              ? 'Pulse user'
                              : profile.displayName,
                          style: AppTypography.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          profile.username == null
                              ? email
                              : '@${profile.username}',
                          style: AppTypography.caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (profile.bio.isNotEmpty) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(profile.bio, style: AppTypography.bodyMedium),
                ),
              ],
              if (joined != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text('Joined $joined', style: AppTypography.caption),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (deviceState.hasError) ...[
          PulseInlineNotice(
            message: 'This device could not be registered.',
            tone: NoticeTone.warning,
            actionLabel: 'Retry',
            onAction: () =>
                ref.read(deviceRegistrationControllerProvider.notifier).retry(),
          ),
          const SizedBox(height: 14),
        ],
        const PushStatusCard(),
        const SizedBox(height: 14),
        if (deviceState.hasError) ...[
          _Row(
            icon: Icons.palette_outlined,
            label: 'Design system',
            trailing: 'debug',
            onTap: () => context.push('/design'),
          ),
        ],
        _Row(
          icon: Icons.network_check_rounded,
          label: 'Connection check',
          trailing: 'diagnose',
          onTap: () => context.push('/connection'),
        ),
        _Row(
          icon: Icons.info_outline_rounded,
          label: 'About Pulse',
          trailing: 'build ${AppConfig.buildLabel}',
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'Pulse',
            applicationVersion: '0.1.0 · build ${AppConfig.buildLabel}',
            children: const [Text('Chat · Call · Connect')],
          ),
        ),
        const SizedBox(height: 18),
        GradientButton(
          label: 'Log out',
          onPressed: () async {
            // Deactivate push for this device while the session still exists.
            await ref.read(pushRegistrationProvider.notifier).handleSignOut();
            await ref.read(authControllerProvider.notifier).signOut();
            if (context.mounted) context.go('/welcome');
          },
        ),
      ],
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

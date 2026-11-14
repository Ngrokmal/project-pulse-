import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/platform/firebase_bootstrap.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/state_views.dart';
import '../application/push_controller.dart';
import '../domain/push_token.dart';
import '../domain/push_token_repository.dart';

/// Real notification status, not a placeholder.
///
/// Shows exactly what the OS reported, offers the one action that can change it,
/// and surfaces push-token sync failures with a retry. When Firebase never came
/// up (e.g. a build without google-services.json) it says so instead of
/// pretending notifications work.
class PushStatusCard extends ConsumerWidget {
  const PushStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!firebaseReady) {
      return _Shell(
        icon: Icons.notifications_off_outlined,
        tint: AppColors.textMuted,
        title: 'Notifications unavailable',
        subtitle:
            'Firebase did not initialise on this build, so push cannot be '
            'registered. Chat and calls still work inside the app.',
        action: null,
      );
    }

    final permission = ref.watch(pushPermissionProvider);
    final registration = ref.watch(pushRegistrationProvider);

    return permission.when(
      loading: () => const _Shell(
        icon: Icons.notifications_active_outlined,
        tint: AppColors.brand500,
        title: 'Notifications',
        subtitle: 'Checking your permission…',
        action: null,
      ),
      error: (error, _) => _Shell(
        icon: Icons.notifications_off_outlined,
        tint: AppColors.danger,
        title: 'Notifications',
        subtitle: error is AppFailure
            ? error.userMessage
            : 'Could not read the notification setting.',
        action: _Action(
          label: 'Check again',
          onTap: () => ref.invalidate(pushPermissionProvider),
        ),
      ),
      data: (state) {
        final syncFailure = registration.hasError
            ? asFailure(registration.error!)
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Shell(
              icon: switch (state) {
                PushPermission.granted => Icons.notifications_active_rounded,
                PushPermission.permanentlyDenied =>
                  Icons.notifications_off_rounded,
                _ => Icons.notifications_none_rounded,
              },
              tint: state.canDeliver ? AppColors.success : AppColors.brand500,
              title: 'Notifications',
              subtitle: _subtitle(state),
              action: switch (state) {
                PushPermission.granted => null,
                PushPermission.unsupported => null,
                PushPermission.permanentlyDenied => _Action(
                  label: 'Check again',
                  onTap: () => ref.invalidate(pushPermissionProvider),
                ),
                _ => _Action(
                  label: 'Turn on',
                  onTap: () =>
                      ref.read(pushPermissionProvider.notifier).request(),
                ),
              },
            ),
            if (syncFailure != null) ...[
              const SizedBox(height: 10),
              PulseInlineNotice(
                message:
                    'Push is ${state.canDeliver ? 'allowed' : 'off'} on this '
                    'device, but registering it with the server failed.',
                tone: NoticeTone.warning,
                actionLabel: 'Retry',
                onAction: () =>
                    ref.read(pushRegistrationProvider.notifier).retry(),
              ),
            ],
            if (state.canDeliver && !registration.hasError) ...[
              const SizedBox(height: 10),
              const _SyncLine(),
            ],
          ],
        );
      },
    );
  }

  String _subtitle(PushPermission state) => switch (state) {
    PushPermission.granted =>
      'On — message and call alerts will reach this device.',
    PushPermission.notRequested =>
      'Turn on alerts so messages and calls reach you when Pulse is closed.',
    PushPermission.denied =>
      'Off. You can allow notifications whenever you are ready.',
    PushPermission.permanentlyDenied =>
      'Blocked in Android settings. Open Settings → Apps → Pulse → '
          'Notifications to allow them.',
    PushPermission.unsupported =>
      'This platform does not support notification permission prompts.',
  };
}

/// Proof (to the user, and in QA) that the token actually reached the server.
class _SyncLine extends ConsumerWidget {
  const _SyncLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registration = ref.watch(pushRegistrationProvider);
    final text = registration.isLoading
        ? 'Registering this device…'
        : 'This device is registered for push.';
    return Row(
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: registration.isLoading
              ? const CircularProgressIndicator(strokeWidth: 1.6)
              : const Icon(
                  Icons.check_circle,
                  size: 12,
                  color: AppColors.success,
                ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: AppTypography.caption)),
      ],
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final _Action? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTypography.caption),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: action!.onTap,
              child: Text(
                action!.label,
                style: AppTypography.caption.copyWith(
                  color: AppColors.brand600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Action {
  const _Action({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
}

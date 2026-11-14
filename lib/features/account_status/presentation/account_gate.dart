import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/pulse_mark.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../notifications/application/push_controller.dart';
import '../application/account_status_controller.dart';
import '../domain/account_status.dart';

/// Blocks the authenticated area when the server says the account is
/// restricted. Server-side enforcement already exists (RLS denies writes and
/// reads); this screen exists so the user gets a real explanation instead of a
/// stream of permission errors (§25).
class AccountGate extends ConsumerWidget {
  const AccountGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(accountStatusControllerProvider);

    return status.when(
      loading: () =>
          const Scaffold(body: PulseLoading(message: 'Checking your account')),
      error: (error, _) => Scaffold(
        body: PulseErrorState(
          failure: error is AppFailure
              ? error
              : const ServerFailure(safeCode: 'status_unavailable'),
          onRetry: () =>
              ref.read(accountStatusControllerProvider.notifier).refresh(),
        ),
      ),
      data: (info) {
        if (info == null || !info.isRestricted) return child;
        return _RestrictedAccountScreen(info: info);
      },
    );
  }
}

class _RestrictedAccountScreen extends ConsumerWidget {
  const _RestrictedAccountScreen({required this.info});

  final AccountStatusInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.gpp_maybe_outlined,
                  size: 44,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                info.title,
                style: AppTypography.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                info.explanation,
                style: AppTypography.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (info.reasonText != null && info.reasonText!.isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(info.reasonText!, style: AppTypography.caption),
                ),
              ],
              if (info.endsAt != null) ...[
                const SizedBox(height: 14),
                Text(
                  'Access returns after ${info.endsAt}',
                  style: AppTypography.caption,
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              GradientButton(
                label: 'Log out',
                onPressed: () async {
                  await ref
                      .read(pushRegistrationProvider.notifier)
                      .handleSignOut();
                  await ref.read(authControllerProvider.notifier).signOut();
                  if (context.mounted) context.go('/welcome');
                },
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => ref
                    .read(accountStatusControllerProvider.notifier)
                    .refresh(),
                child: const Text('Check again'),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  PulseMark(size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Pulse',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
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

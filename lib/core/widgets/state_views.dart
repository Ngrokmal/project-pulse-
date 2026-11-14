import 'package:material_ui/material_ui.dart';

import '../../features/diagnostics/presentation/connection_screen.dart';
import '../error/app_failure.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'gradient_button.dart';

/// Every async surface must be able to render these (§11): loading, empty,
/// error (retryable), offline. No blank screens, no infinite spinners.

class PulseLoading extends StatelessWidget {
  const PulseLoading({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message!, style: AppTypography.caption),
          ],
        ],
      ),
    );
  }
}

class PulseEmptyState extends StatelessWidget {
  const PulseEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: const BoxDecoration(
                gradient: AppColors.pageWashGradient,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: AppColors.brand500),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              style: AppTypography.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              GradientButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
                height: 50,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PulseErrorState extends StatelessWidget {
  const PulseErrorState({super.key, required this.failure, this.onRetry});

  final AppFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final canRetry = failure.isRetryable && onRetry != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 36,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              failure is NetworkFailure
                  ? 'Connection problem'
                  : 'Something went wrong',
              style: AppTypography.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              failure.userMessage,
              style: AppTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (failure is NetworkFailure &&
                (failure as NetworkFailure).detail != null) ...[
              const SizedBox(height: 8),
              Text(
                (failure as NetworkFailure).detail!,
                style: AppTypography.caption,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (failure is NetworkFailure) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ConnectionScreen(),
                  ),
                ),
                child: const Text('Run a connection check'),
              ),
            ],
            if (canRetry) ...[
              const SizedBox(height: 22),
              GradientButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
                expand: false,
                height: 50,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small inline banner for recoverable problems (failed send, offline queue…).
class PulseInlineNotice extends StatelessWidget {
  const PulseInlineNotice({
    super.key,
    required this.message,
    this.tone = NoticeTone.error,
    this.onAction,
    this.actionLabel,
  });

  final String message;
  final NoticeTone tone;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      NoticeTone.error => AppColors.danger,
      NoticeTone.warning => AppColors.warning,
      NoticeTone.info => AppColors.brand600,
      NoticeTone.success => AppColors.success,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(
            switch (tone) {
              NoticeTone.error => Icons.error_outline_rounded,
              NoticeTone.warning => Icons.warning_amber_rounded,
              NoticeTone.info => Icons.info_outline_rounded,
              NoticeTone.success => Icons.check_circle_outline_rounded,
            },
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption.copyWith(color: color, fontSize: 13),
            ),
          ),
          if (onAction != null && actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: AppTypography.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum NoticeTone { error, warning, info, success }

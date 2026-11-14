import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/pulse_mark.dart';

/// Shown when the build has no backend configuration. This is a real,
/// actionable error state — not a blank screen and not a fake success (§11).
class ConfigMissingScreen extends StatelessWidget {
  const ConfigMissingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const PulseMark(size: 72),
              const SizedBox(height: 22),
              Text(
                'Backend not configured',
                style: AppTypography.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'This build was compiled without Supabase credentials. '
                'Pass them at build time:',
                style: AppTypography.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardAlt,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  'flutter build apk \\\n'
                  '  --dart-define=SUPABASE_URL=… \\\n'
                  '  --dart-define=SUPABASE_ANON_KEY=… \\\n'
                  '  --dart-define=CLOUDINARY_CLOUD_NAME=…',
                  style: AppTypography.caption.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/pulse_mark.dart';
import '../../../core/widgets/state_views.dart';

/// Debug-only design-system reference screen. Real, usable tool for reviewing
/// tokens and component states on a device — not shipped to users.
class DesignGalleryScreen extends StatelessWidget {
  const DesignGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Design system')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenX),
        children: [
          _section('Brand'),
          Row(
            children: const [
              PulseMark(size: 72),
              SizedBox(width: 16),
              PulseMark(size: 44),
              SizedBox(width: 16),
              Icon(Icons.verified_rounded, color: AppColors.brand500),
            ],
          ),
          _section('Purple scale'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _Swatch('500', AppColors.brand500),
              _Swatch('600', AppColors.brand600),
              _Swatch('700', AppColors.brand700),
              _Swatch('800', AppColors.brand800),
              _Swatch('300', AppColors.brand300),
              _Swatch('200', AppColors.brand200),
              _Swatch('100', AppColors.brand100),
            ],
          ),
          _section('Gradients'),
          Container(
            height: 64,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: AppRadius.cardRadius,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 64,
            decoration: BoxDecoration(
              gradient: AppColors.bubbleSelfGradient,
              borderRadius: AppRadius.cardRadius,
            ),
          ),
          _section('Type scale'),
          Text('Display 34 / 700', style: AppTypography.displaySmall),
          Text('H1 26 / 700', style: AppTypography.headlineMedium),
          Text('H2 20 / 600', style: AppTypography.titleLarge),
          Text('Body 15 / 400 — message text', style: AppTypography.bodyLarge),
          Text('Caption 12.5 / 500', style: AppTypography.caption),
          _section('Buttons'),
          GradientButton(
            label: 'Primary action',
            icon: Icons.arrow_forward_rounded,
            onPressed: () {},
          ),
          const SizedBox(height: 10),
          const GradientButton(label: 'Disabled', onPressed: null),
          const SizedBox(height: 10),
          const GradientButton(
            label: 'Loading',
            onPressed: null,
            loading: true,
          ),
          const SizedBox(height: 10),
          SoftButton(
            label: 'Secondary',
            icon: Icons.chat_bubble_outline_rounded,
            onPressed: () {},
          ),
          _section('Notices'),
          const PulseInlineNotice(
            message: 'Failed to send. Tap to retry.',
            actionLabel: 'Retry',
            onAction: _noop,
          ),
          const SizedBox(height: 8),
          const PulseInlineNotice(
            message: 'You are offline — message queued.',
            tone: NoticeTone.warning,
          ),
          const SizedBox(height: 8),
          const PulseInlineNotice(
            message: 'Message sent',
            tone: NoticeTone.success,
          ),
          _section('States'),
          const SizedBox(
            height: 120,
            child: PulseLoading(message: 'Checking for new messages'),
          ),
          const SizedBox(height: 20),
          PulseEmptyState(
            icon: Icons.forum_outlined,
            title: 'No conversations yet',
            message: 'Empty state example.',
            actionLabel: 'Action',
            onAction: _noop,
          ),
        ],
      ),
    );
  }

  static void _noop() {}

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(label.toUpperCase(), style: AppTypography.micro),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.border),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: AppTypography.micro),
      ],
    );
  }
}

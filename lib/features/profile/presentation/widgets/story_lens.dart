import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/profile.dart';
import '../../domain/profile_view_mode.dart';
import '../../domain/right_now.dart';
import 'pulse_ui.dart';
import 'right_now_grid.dart';

/// Story: the quote, the Right-now grid, how to reach them, and the labels that
/// keep people close.
class StoryLens extends StatelessWidget {
  const StoryLens({
    super.key,
    required this.profile,
    required this.mode,
    required this.board,
    required this.maskedEmail,
    required this.onTileTap,
    required this.onCopyHandle,
    required this.onCopyLink,
    required this.onAddLabel,
    required this.onRemoveLabel,
  });

  final Profile profile;
  final ProfileViewMode mode;
  final RightNowBoard board;
  final String maskedEmail;
  final ValueChanged<RightNowKind> onTileTap;
  final VoidCallback onCopyHandle;
  final VoidCallback onCopyLink;
  final VoidCallback onAddLabel;
  final ValueChanged<String> onRemoveLabel;

  @override
  Widget build(BuildContext context) {
    final handle = profile.handle;
    final link = profile.shareLink;
    final bio = profile.bio.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bio.isNotEmpty) _QuoteCard(text: bio),
        const PulseEyebrow('Right now'),
        RightNowGrid(board: board, mode: mode, onTap: onTileTap),
        const PulseEyebrow('Reach'),
        PulseRowStack(
          children: [
            if (handle != null)
              PulseRow(
                icon: Icons.alternate_email_rounded,
                title: handle,
                subtitle: 'Tap to copy the handle',
                trailing: const PulseChevron(icon: Icons.copy_rounded),
                onTap: onCopyHandle,
              ),
            if (!mode.isVisitor)
              PulseRow(
                icon: Icons.call_outlined,
                tone: PulseTone.good,
                title: maskedEmail,
                subtitle: 'Hidden from everyone else',
                trailing: Text(
                  'Only you',
                  style: AppTypography.micro.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brand600,
                  ),
                ),
                onTap: () => PulseToast.show(
                  context,
                  'Your sign-in address stays yours',
                ),
              ),
            if (link != null)
              PulseRow(
                icon: Icons.link_rounded,
                tone: PulseTone.blue,
                title: link,
                subtitle: 'The one link that opens this profile',
                trailing: const PulseChevron(),
                onTap: onCopyLink,
              ),
          ],
        ),
        const PulseEyebrow('Kept close'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final label in profile.labels)
              PulseTag(
                label: label,
                onRemove: mode.isVisitor ? null : () => onRemoveLabel(label),
              ),
            if (!mode.isVisitor && profile.labels.length < Profile.maxLabels)
              PulseTag(label: '+ Add a label', plain: true, onTap: onAddLabel),
          ],
        ),
        if (mode.isVisitor && profile.labels.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'No labels yet.',
              style: AppTypography.micro.copyWith(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
      ],
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.format_quote_rounded,
            size: 22,
            color: AppColors.brand200,
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: AppTypography.bodyLarge.copyWith(
              fontSize: 15,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

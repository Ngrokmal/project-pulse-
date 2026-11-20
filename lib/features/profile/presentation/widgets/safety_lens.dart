import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/safety_action.dart';
import 'pulse_ui.dart';

/// The visitor's fourth lens: **Safety**.
///
/// The owner gets Privacy — the block that configures the card. A visitor gets
/// this instead: what they need about *this person*, and the three ways to end
/// it. Nothing here is rendered for the owner, and no switch on somebody else's
/// card is ever shown as if it could be flipped.
class SafetyLens extends StatelessWidget {
  const SafetyLens({
    super.key,
    required this.givenName,
    required this.preview,
    required this.blocked,
    required this.notifications,
    required this.onNotifications,
    required this.onSaveContact,
    required this.onAction,
    required this.onReport,
    required this.onUnblock,
  });

  /// The person's first name, for "Block Rifat?".
  final String givenName;

  /// True when this is the owner looking at their own card through the
  /// visitor's eyes. The rows still render — that is the point of the preview —
  /// but the caller refuses to write anything.
  final bool preview;

  final bool blocked;
  final bool notifications;
  final void Function(bool value) onNotifications;
  final VoidCallback onSaveContact;
  final void Function(SafetyAction action) onAction;
  final VoidCallback onReport;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preview) ...[const _PreviewNote(), const SizedBox(height: 14)],
        const PulseEyebrow('THIS CHAT'),
        PulseRowStack(
          children: [
            PulseRow(
              icon: Icons.notifications_none_rounded,
              title: 'Notifications',
              subtitle: 'Messages arrive, the badge sleeps',
              trailing: PulseSwitch(
                value: notifications,
                onChanged: onNotifications,
              ),
              onTap: () => onNotifications(!notifications),
            ),
            PulseRow(
              icon: Icons.person_add_alt_1_outlined,
              tone: PulseTone.blue,
              title: 'Save the contact',
              subtitle: 'A Pulse card, not a phone number',
              trailing: const PulseChevron(),
              onTap: onSaveContact,
            ),
            PulseRow(
              icon: Icons.info_outline_rounded,
              title: 'What this card does not know',
              subtitle: 'No GPS, no listening, no guessed location',
              trailing: const PulseChevron(),
              onTap: () => PulseToast.show(
                context,
                'Pulse only shows what someone chose to share.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _dangerBlock(context),
      ],
    );
  }

  Widget _dangerBlock(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 14, 11, 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F9),
        borderRadius: BorderRadius.circular(AppRadius.card + 2),
        border: Border.all(color: const Color(0xFFFBDDE1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'IF IT HAS TO END',
              style: AppTypography.micro.copyWith(
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.danger,
              ),
            ),
          ),
          PulseRowStack(
            children: [
              PulseRow(
                icon: Icons.delete_outline_rounded,
                tone: PulseTone.bad,
                title: 'Clear this chat',
                subtitle: 'On this device only',
                trailing: const PulseChevron(),
                danger: true,
                onTap: () => onAction(SafetyAction.clearChat),
              ),
              PulseRow(
                icon: blocked ? Icons.lock_open_rounded : Icons.block_rounded,
                tone: PulseTone.bad,
                title: blocked ? 'Unblock' : 'Block',
                subtitle: blocked
                    ? 'Messages can reach you again'
                    : 'Quiet, complete, reversible',
                trailing: const PulseChevron(),
                danger: true,
                onTap: blocked ? onUnblock : () => onAction(SafetyAction.block),
              ),
              PulseRow(
                icon: Icons.flag_outlined,
                tone: PulseTone.bad,
                title: 'Report',
                subtitle: 'A human reads every report',
                trailing: const PulseChevron(),
                danger: true,
                onTap: onReport,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewNote extends StatelessWidget {
  const _PreviewNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: AppColors.brand50,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.brand100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.visibility_outlined,
            size: 17,
            color: AppColors.brand600,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'This is your own card, seen the way a visitor sees it. The three '
              'rows below act on the person whose chat you opened — not on you.',
              style: AppTypography.micro.copyWith(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.brand700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

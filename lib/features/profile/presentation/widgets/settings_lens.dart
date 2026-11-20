import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/profile_privacy.dart';
import '../../domain/profile_view_mode.dart';
import 'pulse_ui.dart';

/// Settings for the owner, Safety for a visitor.
///
/// The owner sees who-sees-what and security, and has the danger block at the
/// bottom. A visitor sees only what a visitor may change about *this chat* —
/// the owner's switches are not theirs to touch, so they are not rendered at
/// all rather than shown greyed out.
class SettingsLens extends StatelessWidget {
  const SettingsLens({
    super.key,
    required this.mode,
    required this.privacy,
    required this.onToggle,
    required this.onSaveContact,
    required this.onDanger,
    required this.onConnection,
    required this.onAbout,
    required this.onLogout,
    this.deviceCard,
  });

  final ProfileViewMode mode;
  final ProfilePrivacy privacy;
  final void Function(PrivacyField field, bool value) onToggle;
  final VoidCallback onSaveContact;
  final void Function(String title, String body, String confirm) onDanger;
  final VoidCallback onConnection;
  final VoidCallback onAbout;
  final VoidCallback onLogout;

  /// The push-status card, so "notifications" is honest about this device
  /// rather than a switch that pretends.
  final Widget? deviceCard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!mode.isVisitor) ...[
          const PulseEyebrow('Who sees what'),
          PulseRowStack(
            children: [
              _switchRow(
                context,
                field: PrivacyField.lastSeen,
                icon: Icons.visibility_outlined,
                subtitle: 'Friends only — never faked',
              ),
              _switchRow(
                context,
                field: PrivacyField.readReceipts,
                icon: Icons.check_rounded,
                subtitle: 'Off means you stop seeing theirs too',
              ),
              _switchRow(
                context,
                field: PrivacyField.photoVisible,
                icon: Icons.image_outlined,
                subtitle: 'Visible to everyone on Pulse',
              ),
              _switchRow(
                context,
                field: PrivacyField.notifications,
                icon: Icons.notifications_none_rounded,
                subtitle: 'Messages arrive, the badge sleeps',
              ),
            ],
          ),
          const PulseEyebrow('Security'),
          PulseRowStack(
            children: [
              PulseRow(
                icon: Icons.shield_outlined,
                tone: PulseTone.good,
                title: 'Two-step verification',
                subtitle: 'The authenticator on your phone',
                trailing: Text(
                  'On',
                  style: AppTypography.micro.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
                onTap: () =>
                    PulseToast.show(context, 'Two-step verification is on'),
              ),
              PulseRow(
                icon: Icons.devices_outlined,
                tone: PulseTone.blue,
                title: 'Signed in elsewhere',
                subtitle: 'Review every device with your session',
                trailing: const PulseChevron(),
                onTap: () => PulseToast.show(context, 'One phone, that is all'),
              ),
              _switchRow(
                context,
                field: PrivacyField.chatLock,
                icon: Icons.lock_outline_rounded,
                subtitle: 'Behind your fingerprint',
              ),
            ],
          ),
        ] else ...[
          const PulseEyebrow('This chat'),
          PulseRowStack(
            children: [
              PulseRow(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                subtitle: 'Messages arrive, the badge sleeps',
                trailing: PulseSwitch(
                  value: privacy.notifications,
                  onChanged: (v) => onToggle(PrivacyField.notifications, v),
                ),
                onTap: () => onToggle(
                  PrivacyField.notifications,
                  !privacy.notifications,
                ),
              ),
              PulseRow(
                icon: Icons.ios_share_rounded,
                tone: PulseTone.blue,
                title: 'Save the contact',
                subtitle: 'A Pulse card, not a phone number',
                trailing: const PulseChevron(),
                onTap: onSaveContact,
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _DangerBlock(onDanger: onDanger),
        if (!mode.isVisitor) ...[
          const PulseEyebrow('This device'),
          if (deviceCard != null) ...[deviceCard!, const SizedBox(height: 10)],
          PulseRowStack(
            children: [
              PulseRow(
                icon: Icons.network_check_rounded,
                title: 'Connection check',
                subtitle: 'See exactly what the app can reach',
                trailing: const PulseChevron(),
                onTap: onConnection,
              ),
              PulseRow(
                icon: Icons.info_outline_rounded,
                title: 'About Pulse',
                subtitle: 'Chat · Call · Connect',
                trailing: const PulseChevron(),
                onTap: onAbout,
              ),
              PulseRow(
                icon: Icons.logout_rounded,
                tone: PulseTone.bad,
                title: 'Log out',
                subtitle: 'This phone forgets the session',
                onTap: onLogout,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _switchRow(
    BuildContext context, {
    required PrivacyField field,
    required IconData icon,
    required String subtitle,
  }) {
    final value = privacy.valueOf(field);
    return PulseRow(
      icon: icon,
      title: field.label,
      subtitle: subtitle,
      trailing: PulseSwitch(value: value, onChanged: (v) => onToggle(field, v)),
      onTap: () => onToggle(field, !value),
    );
  }
}

class _DangerBlock extends StatelessWidget {
  const _DangerBlock({required this.onDanger});

  final void Function(String title, String body, String confirm) onDanger;

  @override
  Widget build(BuildContext context) {
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
                onTap: () => onDanger(
                  'Clear this chat?',
                  'Every message and file leaves this phone. The other person '
                      'keeps their copy.',
                  'Clear',
                ),
              ),
              PulseRow(
                icon: Icons.block_rounded,
                tone: PulseTone.bad,
                title: 'Block',
                subtitle: 'Quiet, complete, reversible',
                trailing: const PulseChevron(),
                danger: true,
                onTap: () => onDanger(
                  'Block this person?',
                  'Messages and calls stop. They are never told.',
                  'Block',
                ),
              ),
              PulseRow(
                icon: Icons.flag_outlined,
                tone: PulseTone.bad,
                title: 'Report',
                subtitle: 'A human reads every report',
                trailing: const PulseChevron(),
                danger: true,
                onTap: () => onDanger(
                  'Report this person?',
                  'Your last messages go to the Pulse safety team.',
                  'Report',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

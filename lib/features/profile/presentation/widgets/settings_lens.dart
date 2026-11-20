import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../application/profile_sync_controller.dart';
import '../../domain/account_session.dart';
import '../../domain/profile_privacy.dart';
import 'pulse_ui.dart';

/// The owner's fourth lens: **Privacy**.
///
/// A visitor never sees this — it is the block that configures the card, and
/// configuring somebody else's card is not a thing. Every switch here writes a
/// real column (0012) through [onToggle]; when the write cannot reach the
/// server the banner says so instead of pretending it landed.
class PrivacyLens extends StatelessWidget {
  const PrivacyLens({
    super.key,
    required this.privacy,
    required this.sync,
    required this.onToggle,
    required this.onRetrySync,
    required this.sessions,
    required this.sessionsNow,
    required this.onSignOutOthers,
    required this.onConnection,
    required this.onAbout,
    required this.onLogout,
    required this.maskedEmail,
    this.deviceCard,
  });

  final ProfilePrivacy privacy;
  final ProfileSyncState sync;
  final void Function(PrivacyField field, bool value) onToggle;
  final VoidCallback onRetrySync;

  final AsyncValue<List<AccountSession>> sessions;
  final DateTime sessionsNow;
  final Future<void> Function() onSignOutOthers;

  final VoidCallback onConnection;
  final VoidCallback onAbout;
  final VoidCallback onLogout;
  final String maskedEmail;

  /// The push-status card, so "notifications" is honest about this device
  /// rather than a switch that pretends.
  final Widget? deviceCard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!sync.isClean) ...[
          _SyncBanner(sync: sync, onRetry: onRetrySync),
          const SizedBox(height: 14),
        ],
        const PulseEyebrow('Who sees what'),
        PulseRowStack(
          children: [
            _switchRow(
              PrivacyField.lastSeen,
              Icons.visibility_outlined,
              'Friends only — never faked',
            ),
            _switchRow(
              PrivacyField.readReceipts,
              Icons.done_all_rounded,
              'Off means you stop seeing theirs too',
            ),
            _switchRow(
              PrivacyField.photoVisible,
              Icons.image_outlined,
              privacy.photoVisible
                  ? 'Visible to everyone on Pulse'
                  : 'Hidden — your initials stand in',
            ),
            _switchRow(
              PrivacyField.notifications,
              Icons.notifications_none_rounded,
              'Messages arrive, the badge sleeps',
            ),
            _switchRow(
              PrivacyField.chatLock,
              Icons.lock_outline_rounded,
              'Behind your fingerprint',
            ),
          ],
        ),
        const PulseEyebrow('YOUR ACCOUNT'),
        PulseRowStack(
          children: [
            PulseRow(
              icon: Icons.alternate_email_rounded,
              title: 'Email',
              subtitle: maskedEmail,
              trailing: Text(
                'Only you',
                style: AppTypography.micro.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brand600,
                ),
              ),
              onTap: () => PulseToast.show(
                context,
                'Your address is never shown on the card',
              ),
            ),
            _SessionsRow(
              sessions: sessions,
              now: sessionsNow,
              onSignOutOthers: onSignOutOthers,
            ),
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
        if (deviceCard != null) ...[
          const SizedBox(height: 16),
          deviceCard!,
        ],
      ],
    );
  }

  Widget _switchRow(PrivacyField field, IconData icon, String subtitle) {
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

/// "3 changes waiting for a connection" — and a way to retry now.
class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.sync, required this.onRetry});

  final ProfileSyncState sync;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = sync.offline;
    final pending = sync.pending;
    final title = offline
        ? 'You are offline'
        : pending > 0
        ? '$pending change${pending == 1 ? '' : 's'} waiting'
        : 'Everything is saved';
    final body = sync.note ??
        (offline
            ? 'Showing the copy saved on this phone.'
            : 'The card on the server matches this device.');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: offline ? const Color(0xFFFFF8EC) : AppColors.brand50,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: offline ? const Color(0xFFF7E3BF) : AppColors.brand100,
        ),
      ),
      child: Row(
        children: [
          Icon(
            offline ? Icons.cloud_off_rounded : Icons.sync_rounded,
            size: 18,
            color: offline ? const Color(0xFF9A6B00) : AppColors.brand600,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.caption.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: offline
                        ? const Color(0xFF7A5400)
                        : AppColors.brand700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: AppTypography.micro.copyWith(
                    fontSize: 11,
                    height: 1.4,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (pending > 0 || offline)
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

/// One row that opens the device list, because "Devices & sessions" is a real
/// list of rows from `account_device_history`, not a number.
class _SessionsRow extends StatelessWidget {
  const _SessionsRow({
    required this.sessions,
    required this.now,
    required this.onSignOutOthers,
  });

  final AsyncValue<List<AccountSession>> sessions;
  final DateTime now;
  final Future<void> Function() onSignOutOthers;

  @override
  Widget build(BuildContext context) {
    final list = sessions.value ?? const <AccountSession>[];
    final count = list.length;
    final subtitle = switch (sessions) {
      AsyncLoading() => 'Checking the devices on this account',
      AsyncError() => 'Could not read your devices right now',
      _ => count <= 1
          ? 'This phone is the only one signed in'
          : '$count devices signed in',
    };

    return PulseRow(
      icon: Icons.devices_outlined,
      tone: PulseTone.blue,
      title: 'Devices & sessions',
      subtitle: subtitle,
      trailing: const PulseChevron(),
      onTap: () => _showDevices(context, list),
    );
  }

  Future<void> _showDevices(
    BuildContext context,
    List<AccountSession> list,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE1DDF0),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Devices & sessions', style: AppTypography.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Every phone that has used this account. Signing the others '
                'out does not touch this one.',
                style: AppTypography.caption.copyWith(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'No other device has signed in yet.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                )
              else
                for (final session in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PulseRowStack(
                      children: [
                        PulseRow(
                          icon: Icons.smartphone_rounded,
                          title: session.label,
                          subtitle: session.activityLabel(now),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await onSignOutOthers();
                  },
                  icon: const Icon(Icons.logout_rounded, size: 16),
                  label: const Text('Sign out the other devices'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

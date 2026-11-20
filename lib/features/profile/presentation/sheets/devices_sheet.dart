import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../application/safety_controller.dart';
import '../widgets/pulse_ui.dart';
import 'pulse_sheet.dart';

/// Opens the device list. One sheet, one implementation, two doors: the Settings
/// lens row and the "…" sheet on the card.
Future<void> showDevicesSheet(BuildContext context) {
  return showPulseSheet<void>(context: context, child: const DevicesSheet());
}

/// **Devices & sessions.** Every phone that has used this account, read from
/// `account_device_history` — the owner's own rows only.
///
/// The sheet states what it cannot do as plainly as what it can: signing the
/// others out does not touch the phone in your hand, and there is no invented
/// device name — a platform the server did not label says "Pulse device".
class DevicesSheet extends ConsumerWidget {
  const DevicesSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(profileSessionsProvider);
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetHeading(
          title: 'Devices & sessions',
          subtitle:
              'Every phone that has used this account. Signing the others out '
              'does not touch this one.',
        ),
        sessions.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (_, _) => PulseRowStack(
            children: [
              PulseRow(
                icon: Icons.wifi_off_rounded,
                tone: PulseTone.bad,
                title: 'Could not read your devices',
                subtitle: 'Check the connection and try again',
                trailing: const PulseChevron(icon: Icons.refresh_rounded),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? PulseRowStack(
                  children: const [
                    PulseRow(
                      icon: Icons.smartphone_rounded,
                      tone: PulseTone.blue,
                      title: 'No device history yet',
                      subtitle:
                          'This phone will appear here after its next sync',
                    ),
                  ],
                )
              : PulseRowStack(
                  children: [
                    for (final session in list)
                      PulseRow(
                        icon: Icons.smartphone_rounded,
                        tone: PulseTone.blue,
                        title: session.label,
                        subtitle: session.activityLabel(now),
                        trailing: session.isCurrent(null)
                            ? const PulseChevron(icon: Icons.circle)
                            : null,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final failure = await ref.read(signOutOthersProvider)();
              if (!context.mounted) return;
              ref.invalidate(profileSessionsProvider);
              navigator.pop();
              ScaffoldMessenger.maybeOf(context)
                ?..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.navy800,
                    content: Text(
                      failure == null
                          ? 'The other devices were signed out'
                          : 'That did not go through. Try again.',
                    ),
                  ),
                );
            },
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('Sign out the other devices'),
          ),
        ),
      ],
    );
  }
}

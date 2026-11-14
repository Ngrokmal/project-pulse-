import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/state_views.dart';
import '../../notifications/domain/push_token.dart';
import '../domain/app_settings.dart';
import '../domain/notification_settings_probe.dart';

/// Settings (§8 phase 9): notifications, sounds, motion, text size — each one
/// shows the *real* OS state, and every denied path says what can be done next.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/app'),
        ),
        title: Text('Settings', style: AppTypography.titleMedium),
      ),
      body: SafeArea(
        child: settings.when(
          loading: () => const PulseLoading(message: 'Loading settings'),
          error: (error, _) => PulseErrorState(
            failure: error is AppFailure ? error : const ServerFailure(),
            onRetry: () => ref.invalidate(settingsProvider),
          ),
          data: (value) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const _SectionHeader('Notifications'),
              const _PermissionTile(),
              _SwitchTile(
                key: const Key('settings-notifications'),
                title: 'Notification banner',
                subtitle:
                    'Show new messages in the notification shade while the app '
                    'is closed.',
                value: value.notificationsEnabled,
                onChanged: (on) =>
                    ref.read(settingsProvider.notifier).setNotifications(on),
              ),
              _SwitchTile(
                key: const Key('settings-force-audio-auto'),
                title: 'Open Force Audio automatically',
                subtitle:
                    'A Force Audio alert takes over the screen when it arrives. '
                    'Turning it off keeps the alert in the inbox.',
                value: value.forceAudioAutoOpen,
                onChanged: (on) => ref
                    .read(settingsProvider.notifier)
                    .setForceAudioAutoOpen(on),
              ),
              const _SectionHeader('Sounds'),
              _SwitchTile(
                key: const Key('settings-sounds'),
                title: 'In-app sounds',
                subtitle: 'Play the sent/received sounds inside the app.',
                value: value.soundsEnabled,
                onChanged: (on) =>
                    ref.read(settingsProvider.notifier).setSounds(on),
              ),
              const _SectionHeader('Accessibility'),
              _SwitchTile(
                key: const Key('settings-reduce-motion'),
                title: 'Reduce motion',
                subtitle: 'Skip screen transitions and animated lists.',
                value: value.reduceMotion,
                onChanged: (on) =>
                    ref.read(settingsProvider.notifier).setReduceMotion(on),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                child: Semantics(
                  label: 'Text size',
                  value: '${(value.textScale * 100).round()} percent',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Text size', style: AppTypography.titleMedium),
                          const Spacer(),
                          Text(
                            '${(value.textScale * 100).round()}%',
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                      Slider(
                        value: value.textScale,
                        min: AppSettings.minTextScale,
                        max: AppSettings.maxTextScale,
                        divisions: 7,
                        label: '${(value.textScale * 100).round()}%',
                        onChanged: (v) =>
                            ref.read(settingsProvider.notifier).setTextScale(v),
                      ),
                      Text(
                        'Stays inside what the app can lay out without cutting '
                        'text off, on top of the system setting.',
                        style: AppTypography.caption,
                      ),
                    ],
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.micro.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: AppRadius.cardRadius,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
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
            Switch(
              value: value,
              activeThumbColor: AppColors.brand600,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// Reads the OS permission and offers exactly the action that can still work.
class _PermissionTile extends ConsumerStatefulWidget {
  const _PermissionTile();

  @override
  ConsumerState<_PermissionTile> createState() => _PermissionTileState();
}

class _PermissionTileState extends ConsumerState<_PermissionTile> {
  late Future<PushPermission> _permission;

  @override
  void initState() {
    super.initState();
    _permission = ref.read(notificationProbeProvider).read();
  }

  Future<void> _request() async {
    final probe = ref.read(notificationProbeProvider);
    final messenger = ScaffoldMessenger.of(context);
    final result = await probe.request();
    if (!mounted) return;
    final next = Future<PushPermission>.value(result);
    setState(() {
      _permission = next;
    });
    if (!result.canDeliver) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result == PushPermission.permanentlyDenied
                ? 'Blocked by the system. Turn notifications back on in the '
                      'phone settings for Pulse.'
                : 'Notifications stay off. You can turn them on here any time.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PushPermission>(
      future: _permission,
      builder: (context, snapshot) {
        final permission = snapshot.data;
        final String title;
        final String subtitle;
        String? action;
        VoidCallback? onAction;

        switch (permission) {
          case PushPermission.granted:
            title = 'Notifications are on';
            subtitle = 'Message alerts and Force Audio will reach this phone.';
          case PushPermission.notRequested:
            title = 'Notifications are off';
            subtitle =
                'Allow them to hear about messages while the app is closed.';
            action = 'Turn on';
            onAction = _request;
          case PushPermission.denied:
            title = 'Notifications are off';
            subtitle =
                'You declined the prompt. You can ask again, or leave it off.';
            action = 'Ask again';
            onAction = _request;
          case PushPermission.permanentlyDenied:
            title = 'Notifications are blocked';
            subtitle =
                'The system will not ask again. Open your phone settings for '
                'Pulse and allow notifications.';
            action = 'Open system settings';
            onAction = null; // nothing in-app can undo this
          case PushPermission.unsupported:
            title = 'Notifications are unavailable';
            subtitle =
                'This build has no push support (Firebase did not initialise). '
                'Chat and calls still work while the app is open.';
          case null:
            title = 'Checking your permission…';
            subtitle = 'One moment.';
        }

        return Material(
          color: AppColors.card,
          borderRadius: AppRadius.cardRadius,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      permission?.canDeliver == true
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                      size: 18,
                      color: permission?.canDeliver == true
                          ? AppColors.brand600
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(title, style: AppTypography.titleMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: AppTypography.caption),
                if (action != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(onPressed: onAction, child: Text(action)),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

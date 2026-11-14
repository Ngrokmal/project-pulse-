import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';
import '../core/theme/app_theme.dart';
import '../features/calls/application/call_controller.dart';
import '../features/notifications/application/push_message_controller.dart';
import '../features/notifications/domain/push_message.dart';
import '../features/shell/presentation/config_missing_screen.dart';
import 'router/app_router.dart';

final _log = AppLogger('app');

class PulseApp extends ConsumerWidget {
  const PulseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppConfig.isBackendConfigured) {
      return MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const ConfigMissingScreen(),
      );
    }

    final router = ref.watch(routerProvider);

    // A tapped Force Audio notification (including one that launched the app from
    // a terminated state) takes over the screen. The alert id is verified against
    // the server by that screen before anything is downloaded or played.
    ref.listen<PushMessage?>(pushMessageProvider, (previous, next) {
      if (next == null || !next.opened) return;
      if (next.kind != PushKind.forceAudio) return;
      final alertId = next.alertId;
      if (alertId == null || alertId.isEmpty) return;
      _log.info('force_audio_open_requested');
      ref.read(pushMessageProvider.notifier).dismiss();
      router.go('/force-audio/$alertId');
    });

    // An incoming call takes over the screen too — but only when the server row
    // is the one that says "ringing" (incomingCallProvider reads `calls`, it does
    // not invent anything).
    ref.listen<AsyncValue<String?>>(incomingCallProvider, (previous, next) {
      final callId = next.value;
      if (callId == null || callId.isEmpty) return;
      if (previous?.value == callId) return;
      _log.info('incoming_call_open_requested');
      router.push('/call/$callId');
    });

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      routerConfig: router,
      builder: (context, child) {
        // Never let system font scaling break layout completely; keep text
        // readable while preventing extreme overflow (§15).
        final scaler = MediaQuery.textScalerOf(context)
            .clamp(minScaleFactor: 0.9, maxScaleFactor: 1.6);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

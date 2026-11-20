import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';
import '../core/theme/app_theme.dart';
import '../features/account_status/application/account_status_controller.dart';
import '../features/account_status/domain/account_status.dart';
import '../features/calls/application/call_controller.dart';
import '../features/chat/application/chat_controller.dart';
import '../features/settings/domain/app_settings.dart';
import 'lifecycle.dart';
import '../features/notifications/application/push_message_controller.dart';
import '../features/notifications/domain/push_message.dart';
import '../features/shell/presentation/config_missing_screen.dart';
import 'router/app_router.dart';
import '../features/update/presentation/widgets/update_resume_gate.dart';

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
    // Preferences drive what the app shows: text size and motion are applied at
    // the root so every screen (including dialogs) honours them.
    final appSettings =
        ref.watch(settingsProvider).value ?? const AppSettings();
    reduceMotionNotifier.value = appSettings.reduceMotion;
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (_, next) {
      final value = next.value;
      if (value != null) reduceMotionNotifier.value = value.reduceMotion;
    });
    // The account watchdog has to outlive every screen: a hold that lands while
    // the person is typing in a chat must end the session there too, not only
    // when they walk back to the shell (§25). `listen` keeps the provider alive
    // without rebuilding the whole app on every poll.
    ref.listen<AsyncValue<AccountStatusInfo?>>(
      accountStatusControllerProvider,
      (_, _) {},
    );

    // Resuming after a long sleep means the caches are stale; refresh once,
    // throttled, so a flickering phone does not hammer the network (§9).
    if (ref.read(appLifecycleProvider) == AppLifecycleState.resumed) {
      ref.read(resumeRefresherProvider).maybeRun(DateTime.now(), [
        () => ref.invalidate(conversationsProvider),
        () => ref.invalidate(incomingCallProvider),
      ]);
    }

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
        final scaler = TextScaler.linear(appSettings.textScale).clamp(
          minScaleFactor: AppSettings.minTextScale,
          maxScaleFactor: AppSettings.maxTextScale,
        );
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          // Above the router on purpose: wherever the user left the app, coming
          // back asks the release channel again (see UpdateResumeGate).
          // The router is handed in rather than looked up: this builder runs
          // *above* the router's inherited scope, where `GoRouter.of` throws.
          child: UpdateResumeGate(
            routes: router.routerDelegate,
            location: () => router.routerDelegate.currentConfiguration.uri.path,
            openUpdate: () => router.go('/update'),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

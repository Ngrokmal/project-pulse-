import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/platform/firebase_bootstrap.dart';
import 'features/chat/data/chat_local_store.dart';
import 'core/logging/app_logger.dart';

final _log = AppLogger('bootstrap');

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Root error boundary: log safely, never crash the whole app on a
      // widget build failure (§11).
      FlutterError.onError = (details) {
        _log.error('flutter_error', error: details.exceptionAsString());
        if (kDebugMode) FlutterError.presentError(details);
      };

      // Push must come up before the first frame so a cold-start notification
      // tap is not lost. Failure is non-fatal by design.
      await initialiseFirebase();

      // Offline cache + outbox. Failing to open Hive degrades to online-only;
      // it must never stop the messenger from starting.
      await ChatLocalStore.open();

      if (AppConfig.isBackendConfigured) {
        try {
          await Supabase.initialize(
            url: AppConfig.supabaseUrl,
            publishableKey: AppConfig.supabaseAnonKey,
          );
          _log.info('supabase_ready');
        } catch (e) {
          // Keep the app alive: the UI shows a real, retryable error state.
          _log.error('supabase_init_failed', error: e);
        }
      } else {
        _log.warning('backend_not_configured');
      }

      runApp(const ProviderScope(child: PulseApp()));
    },
    (error, stack) {
      _log.error('uncaught_zone_error', error: error);
    },
  );
}

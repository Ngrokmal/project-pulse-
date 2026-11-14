import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/application/auth_controller.dart';

import 'package:firebase_messaging/firebase_messaging.dart' show RemoteMessage;

import '../domain/push_message.dart';
import 'push_controller.dart';

final _log = AppLogger('push');

/// Holds the most recent push that arrived while the user is in the app, plus a
/// cold-start tap. Android renders nothing itself in the foreground, so without
/// this a message would arrive invisibly (§31).
class PushMessageController extends Notifier<PushMessage?> {
  @override
  PushMessage? build() {
    if (!AppConfig.isBackendConfigured) return null;

    final service = ref.watch(pushMessagingServiceProvider);
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthSignedIn) return null;

    final subs = <StreamSubscription<RemoteMessage>>[
      service.foregroundMessages.listen((m) {
        final message = PushMessage.fromRemote(m);
        _log.info('push_foreground', data: {'kind': message.kind.name});
        state = message;
      }),
      service.openedMessages.listen((m) {
        final message = PushMessage.fromRemote(m, opened: true);
        _log.info('push_opened', data: {'kind': message.kind.name});
        state = message;
      }),
    ];
    // A tap that launched the app from a terminated state.
    service.initialMessage().then((m) {
      if (m != null) state = PushMessage.fromRemote(m, opened: true);
    });

    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    return null;
  }

  void dismiss() => state = null;
}

final pushMessageProvider =
    NotifierProvider<PushMessageController, PushMessage?>(
      PushMessageController.new,
    );

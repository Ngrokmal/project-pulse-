import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/features/notifications/application/push_message_controller.dart';
import 'package:pulse/features/notifications/domain/push_message.dart';
import 'package:pulse/features/notifications/presentation/push_banner.dart';

class _StubPushMessages extends PushMessageController {
  _StubPushMessages(this._value);
  final PushMessage? _value;

  @override
  PushMessage? build() => _value;

  @override
  void dismiss() {}
}

void main() {
  group('PushKind.fromData', () {
    test('force_audio payload wins over everything else', () {
      expect(
        PushKind.fromData({'kind': 'force_audio', 'chat_id': 'c1'}),
        PushKind.forceAudio,
      );
      expect(
        PushKind.fromData({'force_audio_alert_id': 'a1'}),
        PushKind.forceAudio,
        reason: 'the alert id alone is enough to activate the takeover',
      );
    });

    test('chat pushes are messages', () {
      expect(PushKind.fromData({'kind': 'message'}), PushKind.message);
      expect(PushKind.fromData({'chat_id': 'c1'}), PushKind.message);
    });

    test('unknown payloads stay unknown instead of guessing', () {
      expect(PushKind.fromData({}), PushKind.unknown);
      expect(PushKind.fromData({'kind': 'analytics'}), PushKind.unknown);
    });
  });

  group('PushMessage.fromRemote', () {
    test('reads the notification block', () {
      final m = PushMessage.fromRemote(
        RemoteMessage(
          messageId: 'm1',
          notification: const RemoteNotification(
            title: 'New message',
            body: 'Hey, are you free?',
          ),
        ),
      );
      expect(m.title, 'New message');
      expect(m.body, 'Hey, are you free?');
      expect(m.kind, PushKind.unknown);
      expect(m.hasBody, isTrue);
      expect(m.messageId, 'm1');
    });

    test('falls back to the data block for data-only pushes', () {
      final m = PushMessage.fromRemote(
        RemoteMessage(
          data: {
            'title': 'Incoming call',
            'body': 'from Ngrok',
            'kind': 'force_audio',
            'force_audio_alert_id': 'alert-9',
          },
        ),
      );
      expect(m.title, 'Incoming call');
      expect(m.body, 'from Ngrok');
      expect(m.kind, PushKind.forceAudio);
      expect(m.alertId, 'alert-9');
    });

    test('never renders an empty title', () {
      final m = PushMessage.fromRemote(RemoteMessage(data: const {}));
      expect(m.title, 'Pulse');
      expect(m.hasBody, isFalse);
    });
  });

  group('PushBanner', () {
    testWidgets('is invisible when there is no push', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pushMessageProvider.overrideWith(() => _StubPushMessages(null)),
          ],
          child: const MaterialApp(home: Scaffold(body: PushBanner())),
        ),
      );
      await tester.pump();
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('shows the message and a dismiss control', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pushMessageProvider.overrideWith(
              () => _StubPushMessages(
                const PushMessage(
                  kind: PushKind.forceAudio,
                  title: 'Force audio alert',
                  body: 'Someone needs you now',
                  alertId: 'alert-1',
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: PushBanner())),
        ),
      );
      await tester.pump();
      expect(find.text('Force audio alert'), findsOneWidget);
      expect(find.text('Someone needs you now'), findsOneWidget);
      expect(find.byTooltip('Dismiss'), findsOneWidget);
    });
  });
}

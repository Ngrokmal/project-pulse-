import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/chat/domain/message.dart';
import 'package:pulse/features/inbox/application/voice_recording_controller.dart';
import 'package:pulse/features/inbox/domain/inbox_record_state.dart';
import 'package:pulse/features/inbox/presentation/widgets/composer_bar.dart';
import 'package:pulse/features/inbox/presentation/widgets/recording_pill.dart';
import 'package:pulse/features/inbox/presentation/widgets/voice_note_bubble.dart';

/// A recorder that is already rolling — no microphone, no timers, so the pill can
/// be laid out deterministically on a narrow (360 dp) screen.
class _FakeRecording extends VoiceRecordingController {
  _FakeRecording(this._initial);

  final InboxRecordState _initial;

  @override
  InboxRecordState build() => _initial;

  @override
  Future<String?> start() async => null;

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> discard() async {}

  @override
  Future<String?> send({required String conversationId}) async => null;
}

Widget _app({required Widget child}) => ProviderScope(
  overrides: [
    voiceRecordingProvider.overrideWith(
      () => _FakeRecording(
        const InboxRecordState(
          stage: RecordStage.recording,
          elapsedMs: 12500,
          path: '/tmp/take.m4a',
        ),
      ),
    ),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 360,
        child: Align(alignment: Alignment.bottomCenter, child: child),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'the recorder pill fits a 360 dp screen and keeps the bin inside',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      var discarded = false;
      await tester.pumpWidget(
        _app(
          child: SizedBox(
            width: 360,
            child: Row(
              children: [
                Expanded(
                  child: RecordingPill(onDiscard: () => discarded = true),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 320));

      expect(tester.takeException(), isNull, reason: 'nothing may overflow');
      expect(find.text('0:12'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

      // The bin's rect must sit inside the pill's rect — the v3 rule.
      final pill = tester.getRect(find.byType(RecordingPill));
      final bin = tester.getRect(find.byIcon(Icons.delete_outline_rounded));
      expect(bin.left, greaterThan(pill.left));
      expect(bin.right, lessThan(pill.right));
      expect(bin.top, greaterThan(pill.top));
      expect(bin.bottom, lessThan(pill.bottom));

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      await tester.pump();
      expect(discarded, isTrue, reason: 'the bin discards, it never sends');
    },
  );

  testWidgets(
    'the composer swaps the field for the recorder, with no overflow',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(() {
        controller.dispose();
        focus.dispose();
      });

      await tester.pumpWidget(
        _app(
          child: ComposerBar(
            controller: controller,
            focusNode: focus,
            attachOpen: false,
            onSendText: () async {},
            onSendVoice: () async => null,
            onPickPhoto: () {},
            onPickFile: () {},
            onTyping: () {},
            onToggleAttach: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 320));

      expect(tester.takeException(), isNull);
      expect(find.byType(RecordingPill), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: 'the field hides');
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    },
  );

  testWidgets('a voice bubble renders its duration and speed chip', (
    tester,
  ) async {
    final message = Message(
      id: 'audio-1',
      conversationId: 'c1',
      senderId: 'peer',
      kind: MessageKind.audio,
      createdAt: DateTime(2026, 11, 14, 10),
      mediaUrl: 'https://example.test/note.m4a',
      durationMs: 7400,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(child: VoiceNoteBubble(message: message, mine: false)),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('0:07'), findsOneWidget);
    expect(find.text('1×'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });
}

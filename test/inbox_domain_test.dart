import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/chat/domain/message.dart';
import 'package:pulse/features/inbox/domain/inbox_delivery.dart';
import 'package:pulse/features/inbox/domain/inbox_motion.dart';
import 'package:pulse/features/inbox/domain/inbox_timeline.dart';
import 'package:pulse/features/inbox/domain/voice_clip.dart';

Message _msg({
  required String id,
  required String sender,
  required DateTime at,
  MessageKind kind = MessageKind.text,
  int? durationMs,
  String? mediaUrl,
  DeliveryState delivery = DeliveryState.sent,
}) => Message(
  id: id,
  conversationId: 'c1',
  senderId: sender,
  kind: kind,
  createdAt: at,
  body: kind == MessageKind.text ? 'hi $id' : null,
  mediaUrl: mediaUrl,
  durationMs: durationMs,
  delivery: delivery,
);

void main() {
  const me = 'me';
  const peer = 'peer';

  group('timeline', () {
    test('opens a day divider only when the calendar day changes', () {
      final morning = DateTime(2026, 11, 14, 9);
      final cells = buildInboxTimeline([
        _msg(id: 'a', sender: peer, at: morning),
        _msg(
          id: 'b',
          sender: peer,
          at: morning.add(const Duration(minutes: 1)),
        ),
        _msg(id: 'c', sender: me, at: morning.add(const Duration(days: 1))),
      ], myId: me);

      expect(cells.length, 3);
      expect(cells[0].showDay, isTrue);
      expect(cells[1].showDay, isFalse);
      expect(cells[2].showDay, isTrue);
      expect(cells[2].mine, isTrue);
    });

    test(
      'stacks consecutive messages from the same side inside two minutes',
      () {
        final start = DateTime(2026, 11, 14, 9);
        final cells = buildInboxTimeline([
          _msg(id: 'a', sender: me, at: start),
          _msg(id: 'b', sender: me, at: start.add(const Duration(seconds: 30))),
          _msg(id: 'c', sender: me, at: start.add(const Duration(minutes: 30))),
        ], myId: me);

        expect(cells[0].stackNext, isTrue, reason: 'b follows a');
        expect(cells[1].stackPrev, isTrue);
        expect(cells[1].stackNext, isFalse, reason: 'c is 30 minutes later');
        expect(cells[2].stackPrev, isFalse);
      },
    );

    test('seen comes from the peer read cursor, never from a guess', () {
      final at = DateTime(2026, 11, 14, 9);
      final message = _msg(id: 'a', sender: me, at: at);

      expect(
        resolveInboxDelivery(
          message,
          peerLastReadAt: at.subtract(const Duration(seconds: 1)),
        ),
        InboxDelivery.sent,
      );
      expect(
        resolveInboxDelivery(message, peerLastReadAt: at),
        InboxDelivery.seen,
      );
      expect(resolveInboxDelivery(message), InboxDelivery.sent);
      expect(
        resolveInboxDelivery(
          _msg(id: 'b', sender: me, at: at, delivery: DeliveryState.failed),
          peerLastReadAt: at.add(const Duration(hours: 1)),
        ),
        InboxDelivery.failed,
      );
    });
  });

  group('voice clip', () {
    test('bars are deterministic and inside the painter band', () {
      final message = _msg(
        id: 'audio-1',
        sender: peer,
        at: DateTime(2026, 11, 14, 9),
        kind: MessageKind.audio,
        durationMs: 7400,
        mediaUrl: 'https://example.test/a.m4a',
      );
      final clip = VoiceClip.fromMessage(message);

      expect(clip.duration, const Duration(milliseconds: 7400));
      expect(clip.canPlay, isTrue);

      final first = clip.barHeights();
      final second = clip.barHeights();
      expect(first.length, InboxMotion.waveformBars);
      expect(
        first,
        second,
        reason: 'a bubble must not reshuffle between builds',
      );
      expect(first.every((value) => value >= 0.32 && value <= 1.0), isTrue);
    });

    test('an audio message without a duration still renders one second', () {
      final clip = VoiceClip.fromMessage(
        _msg(
          id: 'audio-2',
          sender: peer,
          at: DateTime(2026, 11, 14, 9),
          kind: MessageKind.audio,
        ),
      );
      expect(clip.duration, const Duration(seconds: 1));
      expect(clip.canPlay, isFalse);
    });

    test('mm:ss formatting', () {
      expect(VoiceClip.formatMmSs(const Duration(seconds: 7)), '0:07');
      expect(VoiceClip.formatMmSs(const Duration(seconds: 75)), '1:15');
    });
  });

  group('level mapping', () {
    test('the level scales geometry exactly like the reference', () {
      expect(InboxMotion.hintLift(0), 0);
      expect(InboxMotion.hintLift(1), -3.4);
      expect(InboxMotion.hintScale(1), closeTo(1.15, 1e-9));
      expect(InboxMotion.hintOpacity(1), closeTo(1.0, 1e-9));
      expect(InboxMotion.haloSpread(1), 5);
      expect(InboxMotion.sendBloom(1), 18);
      expect(InboxMotion.meterFirst(1), 12);
      expect(InboxMotion.recorderBar(1, 1, 0), 25);
      expect(InboxMotion.recorderBar(0, 0, 0), 4);
      expect(InboxMotion.recorderBar(1, 1, 10), 26, reason: 'clamped at 26');
    });
  });
}

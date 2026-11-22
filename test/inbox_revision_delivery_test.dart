import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/chat/domain/message.dart';
import 'package:pulse/features/inbox/domain/inbox_delivery.dart';

void main() {
  Message row(int? revision) => Message(
    id: 'one',
    conversationId: 'conv',
    senderId: 'me',
    kind: MessageKind.text,
    createdAt: DateTime.utc(2026),
    creationRevision: revision,
  );
  test('seen requires peer revision at or after message creation', () {
    expect(
      resolveInboxDelivery(row(8), peerLastReadRevision: 7),
      InboxDelivery.sent,
    );
    expect(
      resolveInboxDelivery(row(8), peerLastReadRevision: 8),
      InboxDelivery.seen,
    );
    expect(
      resolveInboxDelivery(row(8), peerLastReadRevision: 9),
      InboxDelivery.seen,
    );
  });
  test('missing creation revision cannot fall back to timestamp for revision-aware peer', () {
    expect(
      resolveInboxDelivery(
        row(null),
        peerLastReadRevision: 8,
        peerLastReadAt: DateTime.utc(2030),
      ),
      InboxDelivery.sent,
    );
  });
  test('legacy peer keeps old timestamp behavior', () {
    expect(
      resolveInboxDelivery(row(null), peerLastReadAt: DateTime.utc(2030)),
      InboxDelivery.seen,
    );
  });
  test('creation revision survives local serialization', () {
    expect(Message.fromMap(row(8).toMap()).creationRevision, 8);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/chat/domain/message.dart';
import 'package:pulse/features/chat/domain/message_merge.dart';

Message msg(
  String id, {
  String? client,
  DeliveryState delivery = DeliveryState.sent,
  bool deleted = false,
  String sender = 'sender',
  String conversation = 'conversation',
  String body = 'test',
}) => Message(
  id: id,
  conversationId: conversation,
  senderId: sender,
  kind: MessageKind.text,
  createdAt: DateTime.utc(2026),
  body: body,
  clientId: client,
  delivery: delivery,
  isDeleted: deleted,
);

void main() {
  test('server row wins over pending even if pending is encountered later', () {
    final sent = msg('server', client: 'client-1');
    final pending = msg(
      'pending:client-1',
      client: 'client-1',
      delivery: DeliveryState.pending,
    );
    expect(mergeConversationMessages([sent], [pending]).single.id, 'server');
    expect(mergeConversationMessages([pending], [sent]).single.id, 'server');
  });
  test('a client id collision from a different sender cannot hide a draft', () {
    final pending = msg(
      'pending',
      client: 'client-1',
      sender: 'a',
      delivery: DeliveryState.failed,
    );
    final unrelated = msg('server', client: 'client-1', sender: 'b');
    expect(
      mergeConversationMessages(
        [pending],
        [unrelated],
      ).map((m) => m.id).toSet(),
      {'pending', 'server'},
    );
  });
  test('different content under the same client id cannot hide a draft', () {
    final pending = msg(
      'pending',
      client: 'client-1',
      body: 'unsent',
      delivery: DeliveryState.failed,
    );
    final different = msg('server', client: 'client-1', body: 'different');
    expect(
      mergeConversationMessages(
        [pending],
        [different],
      ).map((m) => m.id).toSet(),
      {'pending', 'server'},
    );
  });
  test('newer server event updates an existing row including tombstone', () {
    final result = mergeConversationMessages(
      [msg('1')],
      [msg('1', deleted: true)],
    );
    expect(result.single.isDeleted, isTrue);
  });
  test('same timestamp ordering is deterministic and duplicates collapse', () {
    final result = mergeConversationMessages(
      [msg('b'), msg('a')],
      [msg('b'), msg('c')],
    );
    expect(result.map((m) => m.id).toList(), ['a', 'b', 'c']);
  });
}

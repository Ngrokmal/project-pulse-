import 'message.dart';

/// True only when a local pending send and a server row represent the same
/// account's same request. A client-id collision alone is not confirmation.
bool _sameRequest(Message a, Message b) =>
    a.conversationId == b.conversationId &&
    a.senderId == b.senderId &&
    a.clientId != null &&
    a.clientId == b.clientId &&
    a.kind == b.kind &&
    a.body == b.body &&
    a.mediaUrl == b.mediaUrl &&
    a.mediaName == b.mediaName &&
    a.mediaBytes == b.mediaBytes &&
    a.durationMs == b.durationMs;

typedef _ClientIdentity = (String, String, String);
_ClientIdentity? _identity(Message message) => message.clientId == null
    ? null
    : (message.conversationId, message.senderId, message.clientId!);

/// Merge one conversation's messages. Server updates for the same row replace
/// older snapshots. A confirmed row reconciles a pending/failed row only when
/// sender, conversation, client id and request payload all match. Ambiguous
/// collisions are retained visibly instead of silently deleting a draft.
List<Message> mergeConversationMessages(
  Iterable<Message> existing,
  Iterable<Message> incoming,
) {
  final rows = <String, Message>{};
  final identities = <_ClientIdentity, Set<String>>{};

  void remove(String id) {
    final old = rows.remove(id);
    if (old == null) return;
    final identity = _identity(old);
    if (identity != null) {
      identities[identity]?.remove(id);
      if (identities[identity]?.isEmpty == true) identities.remove(identity);
    }
  }

  void put(Message message) {
    rows[message.id] = message;
    final identity = _identity(message);
    if (identity != null) {
      identities.putIfAbsent(identity, () => <String>{}).add(message.id);
    }
  }

  for (final message in [...existing, ...incoming]) {
    final sameRow = rows[message.id];
    if (sameRow != null) {
      if (sameRow.delivery == DeliveryState.sent &&
          message.delivery != DeliveryState.sent) {
        continue;
      }
      remove(message.id);
      put(message);
      continue;
    }
    final identity = _identity(message);
    Message? match;
    if (identity != null) {
      for (final id in identities[identity] ?? const <String>{}) {
        final other = rows[id]!;
        final oneConfirmed =
            (other.delivery == DeliveryState.sent) !=
            (message.delivery == DeliveryState.sent);
        if (oneConfirmed && _sameRequest(other, message)) {
          match = other;
          break;
        }
      }
    }
    if (match != null) {
      if (match.delivery == DeliveryState.sent) continue;
      remove(match.id);
    }
    put(message);
  }
  return rows.values.toList()..sort((a, b) {
    final time = a.createdAt.compareTo(b.createdAt);
    return time != 0 ? time : a.id.compareTo(b.id);
  });
}

import '../../chat/domain/message.dart';

/// What the tick in a bubble is allowed to say.
///
/// The database only ever tells us three things: the row exists (`sent`), the
/// peer's read cursor (`conversation_members.last_read_at` → `seen`), or that
/// the send has not landed yet. There is deliberately no invented `delivered`
/// state — a double tick that is not backed by a server fact would be a lie.
enum InboxDelivery { pending, sent, seen, failed }

/// Resolves the delivery state of one message.
///
/// [peerLastReadAt] is the peer's read cursor for this conversation: when it is
/// at or after the message, the peer has seen it.
InboxDelivery resolveInboxDelivery(
  Message message, {
  DateTime? peerLastReadAt,
  int? peerLastReadRevision,
}) {
  switch (message.delivery) {
    case DeliveryState.pending:
      return InboxDelivery.pending;
    case DeliveryState.failed:
      return InboxDelivery.failed;
    case DeliveryState.sent:
      if (peerLastReadRevision != null) {
        final created = message.creationRevision;
        return created != null && created <= peerLastReadRevision
            ? InboxDelivery.seen
            : InboxDelivery.sent;
      }
      // Legacy peers only expose a timestamp, which cannot prove gap-safe reads.
      if (peerLastReadAt != null &&
          !message.createdAt.isAfter(peerLastReadAt)) {
        return InboxDelivery.seen;
      }
      return InboxDelivery.sent;
  }
}

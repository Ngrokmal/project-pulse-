import '../../chat/domain/message.dart';
import 'inbox_delivery.dart';

/// One row of the thread, with everything already resolved:
///
/// * `showDay` – this row opens a new calendar day,
/// * `stackPrev` / `stackNext` – the neighbour above/below is from the same
///   side and within two minutes, so the corners pull in (reference grouping),
/// * `delivery` – what the tick may say.
///
/// The presentation layer stays a pure function of this list: no grouping logic
/// inside `build()`, so scrolling never recomputes anything.
class InboxCell {
  const InboxCell({
    required this.message,
    required this.mine,
    required this.delivery,
    required this.showDay,
    required this.stackPrev,
    required this.stackNext,
  });

  final Message message;
  final bool mine;
  final InboxDelivery delivery;
  final bool showDay;
  final bool stackPrev;
  final bool stackNext;

  DateTime get createdAt => message.createdAt;
  bool get isFresh =>
      mine &&
      (delivery == InboxDelivery.pending || delivery == InboxDelivery.failed);
}

/// Builds the timeline in ascending order (oldest first). The view reverses it
/// for a bottom-anchored `ListView`, which keeps the list lazy.
List<InboxCell> buildInboxTimeline(
  List<Message> messages, {
  required String myId,
  DateTime? peerLastReadAt,
  int? peerLastReadRevision,
}) {
  if (messages.isEmpty) return const [];
  const stackWindow = Duration(minutes: 2);
  final cells = <InboxCell>[];
  for (var i = 0; i < messages.length; i++) {
    final message = messages[i];
    final mine = message.senderId == myId;
    final previous = i == 0 ? null : messages[i - 1];
    final next = i == messages.length - 1 ? null : messages[i + 1];
    final showDay =
        previous == null || !_sameDay(previous.createdAt, message.createdAt);
    final stackPrev =
        !showDay &&
        previous.senderId == message.senderId &&
        message.createdAt.difference(previous.createdAt) < stackWindow;
    final stackNext =
        next != null &&
        next.senderId == message.senderId &&
        next.createdAt.difference(message.createdAt) < stackWindow;
    cells.add(
      InboxCell(
        message: message,
        mine: mine,
        delivery: resolveInboxDelivery(
          message,
          peerLastReadAt: peerLastReadAt,
          peerLastReadRevision: peerLastReadRevision,
        ),
        showDay: showDay,
        stackPrev: stackPrev,
        stackNext: stackNext,
      ),
    );
  }
  return cells;
}

bool sameCalendarDay(DateTime a, DateTime b) => _sameDay(a, b);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

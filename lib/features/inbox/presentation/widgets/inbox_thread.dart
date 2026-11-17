import 'package:material_ui/material_ui.dart';

import '../../../chat/domain/message.dart';
import '../../domain/inbox_timeline.dart';
import 'day_divider.dart';
import 'message_row.dart';
import 'typing_bubble.dart';

/// The thread itself: a **lazy, bottom-anchored** list.
///
/// `reverse: true` means the newest message is at the bottom with no scroll
/// bookkeeping, the list stays virtualised for long conversations, and
/// "jump to latest" is simply `animateTo(0)`. Day dividers ride inside the row
/// they open, so grouping never costs an extra layout pass.
class InboxThread extends StatelessWidget {
  const InboxThread({
    super.key,
    required this.cells,
    required this.peerTyping,
    required this.controller,
    required this.now,
    required this.emptyState,
    required this.onRetry,
    required this.onDelete,
    this.myName,
    this.peerName,
  });

  final List<InboxCell> cells;
  final bool peerTyping;
  final ScrollController controller;
  final DateTime now;
  final Widget emptyState;
  final VoidCallback onRetry;
  final ValueChanged<Message> onDelete;

  /// Used for the `Saiful → Mahmoud` line under every attachment.
  final String? myName;
  final String? peerName;

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty && !peerTyping) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 26),
          child: emptyState,
        ),
      );
    }

    final typingOffset = peerTyping ? 1 : 0;
    final itemCount = cells.length + typingOffset;

    return ListView.builder(
      controller: controller,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: itemCount,
      scrollCacheExtent: const ScrollCacheExtent.pixels(600),
      itemBuilder: (context, index) {
        if (peerTyping && index == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TypingBubble(),
            ),
          );
        }
        final cell = cells[cells.length - 1 - (index - typingOffset)];
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (cell.showDay) DayDivider(when: cell.createdAt, now: now),
              MessageRow(
                cell: cell,
                myName: myName,
                peerName: peerName,
                onRetry: onRetry,
                onDelete: cell.mine && !cell.message.isDeleted
                    ? () => onDelete(cell.message)
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/features/chat/presentation/widgets/pulse_segments.dart';

/// The tabs must show what is actually true — including `0` when there is no
/// group to show (the reference always renders its count chip).
void main() {
  Widget host({
    required InboxFilter selected,
    required int all,
    required int chats,
    required int groups,
    ValueChanged<InboxFilter>? onChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: PulseSegments(
            selected: selected,
            allCount: all,
            chatCount: chats,
            groupCount: groups,
            onChanged: onChanged ?? (_) {},
          ),
        ),
      ),
    );
  }

  // No pumpAndSettle anywhere: the pill's sheen runs forever by design.
  testWidgets('counts come from the data, and an empty side reads 0', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(selected: InboxFilter.all, all: 7, chats: 7, groups: 0),
    );

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('7'), findsNWidgets(2));
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('a group shows up in the Groups count', (tester) async {
    await tester.pumpWidget(
      host(selected: InboxFilter.groups, all: 9, chats: 8, groups: 1),
    );

    expect(find.text('9'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('tapping a tab reports it', (tester) async {
    InboxFilter? picked;
    await tester.pumpWidget(
      host(
        selected: InboxFilter.all,
        all: 3,
        chats: 2,
        groups: 1,
        onChanged: (f) => picked = f,
      ),
    );

    await tester.tap(find.text('Groups'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(picked, InboxFilter.groups);
  });
}

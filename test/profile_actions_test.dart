import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/features/explore/application/friend_actions_controller.dart';
import 'package:pulse/features/explore/domain/friend_state.dart';
import 'package:pulse/features/explore/domain/people_search.dart';
import 'package:pulse/features/explore/domain/person.dart';
import 'package:pulse/features/explore/presentation/widgets/search_result_tile.dart';
import 'package:pulse/features/profile/domain/profile.dart';
import 'package:pulse/features/profile/presentation/sheets/more_with_sheet.dart';
import 'package:pulse/features/profile/presentation/sheets/pulse_sheet.dart';

/// The two doors a person has, and the sheet that used to lead nowhere.
///
/// 1. In a search result the **face and the name** open their card, and the
///    **pill on the right** opens the chat. They are separate targets and they
///    do different things — that is the point of the change.
/// 2. The "…" sheet closes itself exactly once, so a row can open its own sheet
///    instead of taking the whole page down with it.
const _person = Person(
  id: 'peer-1',
  displayName: 'abdullah',
  handle: 'abdullah',
);

final _hit = const SearchHit(
  person: _person,
  state: FriendState.friend,
  score: 96,
);

void main() {
  testWidgets('tapping the face opens the card, not the chat', (tester) async {
    var chat = 0;
    var card = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: Consumer(
                  builder: (context, ref, _) => SearchResultTile(
                    hit: _hit,
                    // The real actions object; none of the taps below reach the
                    // network, they only choose a door.
                    actions: ref.read(friendActionsProvider),
                    onOpenChat: () => chat++,
                    onOpenProfile: () => card++,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // The avatar is the first tappable inside the row.
    await tester.tap(find.text('AB'));
    await tester.pump();
    expect(card, 1, reason: 'the face opens the person');
    expect(chat, 0, reason: 'and never the thread');

    await tester.tap(find.text('abdullah'));
    await tester.pump();
    expect(card, 2, reason: 'the name opens them too');
    expect(chat, 0);
  });

  testWidgets('the message pill still opens the chat', (tester) async {
    var chat = 0;
    var card = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: Consumer(
                  builder: (context, ref, _) => SearchResultTile(
                    hit: _hit,
                    // The real actions object; none of the taps below reach the
                    // network, they only choose a door.
                    actions: ref.read(friendActionsProvider),
                    onOpenChat: () => chat++,
                    onOpenProfile: () => card++,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Message'));
    await tester.pump();
    expect(chat, 1);
    expect(card, 0);
  });

  testWidgets('a row in the "…" sheet runs once and takes only itself down', (
    tester,
  ) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showPulseSheet<void>(
                  context: context,
                  child: MoreWithSheet(
                    profile: const Profile(
                      id: 'me',
                      displayName: 'Saiful Islam',
                      username: 'saiful',
                    ),
                    actions: [
                      SheetAction(
                        icon: Icons.edit_outlined,
                        title: 'Edit your card',
                        subtitle: 'Name, handle, status and where',
                        onTap: () => taps++,
                      ),
                    ],
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Edit your card'), findsOneWidget);

    await tester.tap(find.text('Edit your card'));
    await tester.pumpAndSettle();

    expect(taps, 1, reason: 'the action ran exactly once');
    expect(
      find.text('Edit your card'),
      findsNothing,
      reason: 'the sheet closed',
    );
    expect(
      find.text('open'),
      findsOneWidget,
      reason: 'and the page underneath is still there — one pop, not two',
    );
  });
}

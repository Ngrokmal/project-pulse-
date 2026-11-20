import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/features/inbox/presentation/widgets/inbox_avatar.dart';
import 'package:pulse/features/profile/domain/profile_view_mode.dart';
import 'package:pulse/features/profile/presentation/widgets/people_lens.dart';

/// The photo you upload on the profile card has to be the photo every screen
/// paints. These tests pin the two screens that used to draw initials only.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('the inbox avatar paints the photo when there is one', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const InboxAvatar(
          initials: 'RH',
          seed: 'c1',
          presence: AvatarPresence.active,
          imageUrl: 'https://cdn.test/rifat.png',
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as NetworkImage).url,
      'https://cdn.test/rifat.png',
      reason: 'the chat header must not fall back to initials',
    );
  });

  testWidgets('without a photo it is still the initials, not a broken tile', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const InboxAvatar(
          initials: 'RH',
          seed: 'c1',
          presence: AvatarPresence.offline,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.text('RH'), findsOneWidget);
  });

  testWidgets('a face in the people lens paints the photo too', (tester) async {
    await tester.pumpWidget(
      wrap(
        const PeopleLens(
          faces: [
            PeopleFace(
              initials: 'RH',
              tone: 0,
              imageUrl: 'https://cdn.test/rifat.png',
            ),
          ],
          circles: [],
          mode: ProfileViewMode.owner,
          knownLine: 'Rifat',
          onOpenCode: _noop,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
  });
}

void _noop() {}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/app/app.dart';

void main() {
  testWidgets(
    'unconfigured build shows an actionable error, never a blank screen',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: PulseApp()));
      await tester.pumpAndSettle();

      // Tests run without --dart-define, so config is empty by definition.
      expect(find.text('Backend not configured'), findsOneWidget);
      expect(find.textContaining('--dart-define=SUPABASE_URL'), findsOneWidget);
    },
  );
}

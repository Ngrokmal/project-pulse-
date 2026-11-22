import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/core/error/app_failure.dart';
import 'package:pulse/features/error_messages/application/error_message_resolver.dart';
import 'package:pulse/features/error_messages/domain/error_message_repository.dart';

class _ErrorRepository implements ErrorMessageRepository {
  _ErrorRepository({this.value, this.fail = false});
  final String? value;
  final bool fail;
  @override
  Future<String?> fetch(String code) async {
    if (fail) throw StateError('offline');
    return value;
  }
}

class _Example extends ConsumerStatefulWidget {
  const _Example();
  @override
  ConsumerState<_Example> createState() => _ExampleState();
}

class _ExampleState extends ConsumerState<_Example> {
  String value = 'loading';
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final result = await resolveErrorMessage(
        ref,
        const AdminControlFailure('message_send_disabled'),
      );
      if (mounted) setState(() => value = result);
    });
  }

  @override
  Widget build(BuildContext context) =>
      Text(value, textDirection: TextDirection.ltr);
}

void main() {
  testWidgets('server override is shown when available', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          errorMessageRepositoryProvider.overrideWithValue(
            _ErrorRepository(value: 'Custom message'),
          ),
        ],
        child: const _Example(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Custom message'), findsOneWidget);
  });
  testWidgets('offline falls back to local safe message', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          errorMessageRepositoryProvider.overrideWithValue(
            _ErrorRepository(fail: true),
          ),
        ],
        child: const _Example(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('Messaging is not available for this account.'),
      findsOneWidget,
    );
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/error/app_failure.dart';
import 'package:pulse/features/chat/application/chat_controller.dart';
import 'package:pulse/features/chat/domain/chat_repository.dart';
import 'package:pulse/features/chat/domain/conversation.dart';
import 'package:pulse/features/explore/application/explore_chat_launcher.dart';
import 'package:pulse/features/explore/application/explore_feedback_controller.dart';
import 'package:pulse/features/explore/domain/person.dart';

/// Message, from Explore, has to open the real conversation — which means asking
/// the one repository that owns conversations for the id, and never inventing
/// one. These two cases are the whole contract: a success hands back the id, a
/// failure hands back nothing and says why.
class _FakeChat implements ChatRepository {
  _FakeChat({this.failure});

  final AppFailure? failure;
  final List<String> started = <String>[];

  @override
  Future<String> startDirectConversation(String otherUserId) async {
    started.add(otherUserId);
    final error = failure;
    if (error != null) throw error;
    return 'conv-$otherUserId';
  }

  @override
  Future<List<Conversation>> conversations() async => const <Conversation>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  const person = Person(id: 'person-7', displayName: 'Mahmoud Hasan');

  test('a tap resolves the real conversation id', () async {
    final chat = _FakeChat();
    final container = ProviderContainer(
      overrides: [chatRepositoryProvider.overrideWithValue(chat)],
    );
    addTearDown(container.dispose);

    final id = await container
        .read(exploreChatLauncherProvider)
        .openWith(person);

    expect(id, 'conv-person-7');
    expect(chat.started, <String>['person-7']);
    expect(container.read(exploreFeedbackProvider), isNull);
  });

  test('a failure opens nothing and explains itself', () async {
    final chat = _FakeChat(
      failure: const ServerFailure(safeCode: 'conversation_failed'),
    );
    final container = ProviderContainer(
      overrides: [chatRepositoryProvider.overrideWithValue(chat)],
    );
    addTearDown(container.dispose);

    final id = await container
        .read(exploreChatLauncherProvider)
        .openWith(person);

    expect(id, isNull);
    final toast = container.read(exploreFeedbackProvider);
    expect(toast, isNotNull);
    expect(toast!.tick, isFalse, reason: 'a failure must not wear a tick');
    expect(toast.person, isNull, reason: 'no face on a failure toast');
    expect(toast.detail, contains('Mahmoud Hasan'));
  });
}

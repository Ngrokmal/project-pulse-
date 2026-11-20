import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../chat/application/chat_controller.dart';
import '../domain/person.dart';
import 'explore_failure_copy.dart';
import 'explore_feedback_controller.dart';

/// Message, from Explore, for real.
///
/// The button used to say "opening chat…" and stop there, because the chat lives
/// in another feature. This is the missing half: the chat repository already
/// knows how to start a 1:1 conversation idempotently, so Explore asks it for the
/// id and the presentation layer pushes the real inbox route. Nothing about
/// conversations is re-implemented here — the id comes from the one place that
/// owns them.
class ExploreChatLauncher {
  ExploreChatLauncher(this._ref);

  final Ref _ref;

  /// Returns the conversation id to open, or `null` when it could not be
  /// created (the toast already explains why).
  Future<String?> openWith(Person person) async {
    try {
      final conversationId = await _ref
          .read(chatRepositoryProvider)
          .startDirectConversation(person.id);

      // The new thread belongs on Home too; refresh now so the list is right
      // when the user comes back from it.
      unawaited(_refreshConversations());

      return conversationId;
    } on AppFailure catch (failure) {
      _ref
          .read(exploreFeedbackProvider.notifier)
          .show(
            ExploreToast(
              message: exploreFailureCopy(failure),
              detail:
                  'Could not open the chat with '
                  '${person.displayName.trim().isEmpty ? 'them' : person.displayName.trim()}',
              tick: false,
            ),
          );
      return null;
    }
  }

  Future<void> _refreshConversations() async {
    try {
      await _ref.read(conversationsProvider.notifier).refresh();
    } on Object {
      // A stale Home list is not worth a second message on top of a success.
    }
  }
}

final exploreChatLauncherProvider = Provider<ExploreChatLauncher>(
  ExploreChatLauncher.new,
);

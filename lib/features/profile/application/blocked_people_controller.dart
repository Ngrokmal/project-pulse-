import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../chat/application/chat_controller.dart';
import '../domain/blocked_person.dart';
import 'profile_controller.dart';

/// Who this account has blocked, newest first.
///
/// The list is the server's answer to `blocked_people()` (0014) — not a local
/// mirror — so a block made on another phone is here the next time this page
/// opens, and an unblock made here is gone from the other phone too.
class BlockedPeopleController extends AsyncNotifier<List<BlockedPerson>> {
  @override
  Future<List<BlockedPerson>> build() {
    return ref.watch(profileRepositoryProvider).blockedPeople();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).blockedPeople(),
    );
  }

  /// Lifts a block. The row disappears from `public.blocks`, which is also what
  /// lets the two of you reach each other again — the message trigger in 0013
  /// reads the same table.
  Future<AppFailure?> unblock(BlockedPerson person) async {
    final previous = state.value ?? const <BlockedPerson>[];
    // Take it off the page first: the row is the thing they asked to be gone.
    state = AsyncData([
      for (final row in previous)
        if (row.id != person.id) row,
    ]);
    try {
      await ref.read(profileRepositoryProvider).unblockUser(person.id);
      // Their avatar and last message rejoin the conversation list.
      ref.invalidate(conversationsProvider);
      unawaited(refresh());
      return null;
    } on AppFailure catch (failure) {
      state = AsyncData(previous);
      return failure;
    } catch (_) {
      state = AsyncData(previous);
      return const ServerFailure();
    }
  }
}

final blockedPeopleProvider =
    AsyncNotifierProvider<BlockedPeopleController, List<BlockedPerson>>(
      BlockedPeopleController.new,
    );

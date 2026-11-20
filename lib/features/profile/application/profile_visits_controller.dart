import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/profile.dart';
import '../domain/profile_visitor.dart';
import 'profile_controller.dart';

/// Who opened this account's card, newest first.
///
/// The list is the server's answer to `profile_visitors()` (0015), never a local
/// mirror — so a visit from another phone shows up here, and a visit that has
/// since become a block is gone.
class ProfileVisitsController extends AsyncNotifier<List<ProfileVisitor>> {
  @override
  Future<List<ProfileVisitor>> build() {
    return ref.watch(profileRepositoryProvider).profileVisitors();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).profileVisitors(),
    );
  }
}

final profileVisitorsProvider =
    AsyncNotifierProvider<ProfileVisitsController, List<ProfileVisitor>>(
      ProfileVisitsController.new,
    );

/// Someone else's card, as they allow it to be seen.
///
/// Loading the card is also what records the visit: one call, in one place, so
/// there is no second code path that could open a card without the person on the
/// other end ever knowing — or, worse, record an open that never happened. The
/// write is best effort and silent; a card that fails to save its visit must
/// still open.
final peerCardProvider = FutureProvider.autoDispose.family<Profile, String>((
  ref,
  peerId,
) async {
  final repository = ref.watch(profileRepositoryProvider);
  final profile = await repository.fetchProfile(peerId);
  unawaited(
    Future<void>(() async {
      try {
        await repository.recordProfileVisit(peerId);
      } catch (_) {
        // A visit that could not be stored is not the visitor's problem.
      }
    }),
  );
  return profile;
});

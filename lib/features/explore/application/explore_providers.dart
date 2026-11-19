import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../data/supabase_explore_repository.dart';
import '../domain/explore_repository.dart';
import 'explore_counts.dart';

/// One repository for the whole tab.
final exploreRepositoryProvider = Provider<ExploreRepository>((ref) {
  if (!AppConfig.isBackendConfigured) {
    throw const ConfigurationFailure('Supabase is not configured.');
  }
  return SupabaseExploreRepository(Supabase.instance.client);
});

/// People who asked me. Newest first.
///
/// Deliberately not `autoDispose`: the shell keeps Explore alive in an
/// `IndexedStack`, and keeping the last answer means a tab switch never shows a
/// spinner over data we already had. It is refreshed by the actions controller
/// and by pull-to-refresh — exactly where the reference refreshes too.
final incomingRequestsProvider = FutureProvider((ref) {
  return ref.watch(exploreRepositoryProvider).incomingRequests();
});

final sentRequestsProvider = FutureProvider((ref) {
  return ref.watch(exploreRepositoryProvider).sentRequests();
});

final friendsProvider = FutureProvider((ref) {
  return ref.watch(exploreRepositoryProvider).friends();
});

/// The number on the Friends segment: asked for on its own so a capped list can
/// never make the count lie.
final friendsCountProvider = FutureProvider((ref) {
  return ref.watch(exploreRepositoryProvider).friendsCount();
});

/// The searched population, for the honest "of 4,208" line.
final exploreNetworkSizeProvider = FutureProvider((ref) {
  return ref.watch(exploreRepositoryProvider).networkSize();
});

/// The three numbers the segmented control shows. Derived, never stored twice.
final exploreCountsProvider = Provider<ExploreCounts>((ref) {
  return ExploreCounts(
    requests: ref.watch(incomingRequestsProvider).value?.length ?? 0,
    sent: ref.watch(sentRequestsProvider).value?.length ?? 0,
    friends: ref.watch(friendsCountProvider).value ?? 0,
  );
});

/// Refreshes every Explore read. Pull-to-refresh and every mutation call this.
void refreshExplore(Ref ref) {
  ref.invalidate(incomingRequestsProvider);
  ref.invalidate(sentRequestsProvider);
  ref.invalidate(friendsProvider);
  ref.invalidate(friendsCountProvider);
}

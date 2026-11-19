import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../domain/explore_motion.dart';
import '../domain/people_search.dart';
import 'explore_providers.dart';

/// The search sheet's five moments, as one sealed state.
sealed class SearchUiState {
  const SearchUiState();
}

/// Nothing asked yet: recent names, who is awake, the invite card.
class SearchIdle extends SearchUiState {
  const SearchIdle();
}

/// One request is in flight. Carries the query so the skeleton can say it.
class SearchLoading extends SearchUiState {
  const SearchLoading(this.query);
  final String query;
}

/// The server answered with at least one person above the floor.
class SearchResults extends SearchUiState {
  const SearchResults(this.result);
  final PeopleSearch result;
}

/// The server answered with nobody — and possibly two near-misses, which arrive
/// a moment later without blocking the empty state.
class SearchEmpty extends SearchUiState {
  const SearchEmpty(this.result, {this.nearMisses = const <SearchHit>[]});
  final PeopleSearch result;
  final List<SearchHit> nearMisses;
}

class SearchFailed extends SearchUiState {
  const SearchFailed(this.query, this.failure);
  final String query;
  final AppFailure failure;
}

/// Owns one explicit submit at a time.
///
/// Nothing here reacts to typing: [submit] is called by the search icon or by
/// Enter, exactly once. A newer submit bumps a generation counter, and any late
/// answer from an older one is dropped — so fast taps can never paint stale
/// rows over fresh ones.
class PeopleSearchController extends Notifier<SearchUiState> {
  int _generation = 0;

  @override
  SearchUiState build() {
    ref.onDispose(() => _generation++);
    return const SearchIdle();
  }

  Future<void> submit(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) {
      reset();
      return;
    }

    final generation = ++_generation;
    state = SearchLoading(query);

    final repository = ref.read(exploreRepositoryProvider);
    final started = DateTime.now();

    try {
      final result = await repository.searchPeople(query);

      // Keep the skeleton on screen for a beat even when the server is quick:
      // a flash of skeleton is more jarring than a calm 380 ms.
      final elapsed = DateTime.now().difference(started);
      final remaining = ExploreMotion.searchMinimum - elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      if (generation != _generation) return;

      if (result.isEmpty) {
        state = SearchEmpty(result);
        await _loadNearMisses(query, generation);
      } else {
        state = SearchResults(result);
      }
    } on AppFailure catch (failure) {
      if (generation != _generation) return;
      state = SearchFailed(query, failure);
    } on Object {
      if (generation != _generation) return;
      state = SearchFailed(query, const ServerFailure());
    }
  }

  /// Suggestions are a courtesy: if this call fails the empty state simply keeps
  /// its "try a shorter search" chips and says nothing about the failure.
  Future<void> _loadNearMisses(String query, int generation) async {
    try {
      final near = await ref.read(exploreRepositoryProvider).nearMisses(query);
      if (generation != _generation) return;
      final current = state;
      if (current is SearchEmpty && current.nearMisses.isEmpty) {
        state = SearchEmpty(current.result, nearMisses: near);
      }
    } on Object {
      // ignored on purpose
    }
  }

  /// Back to the idle sheet (used when the field is emptied or the sheet closes).
  void reset() {
    _generation++;
    state = const SearchIdle();
  }

  /// The query the last answer belongs to, for the "3 people match “nus”" line.
  String get answeredQuery => switch (state) {
    SearchResults(:final result) => result.query,
    SearchEmpty(:final result) => result.query,
    SearchLoading(:final query) => query,
    SearchFailed(:final query) => query,
    SearchIdle() => '',
  };
}

final peopleSearchProvider =
    NotifierProvider<PeopleSearchController, SearchUiState>(
      PeopleSearchController.new,
    );

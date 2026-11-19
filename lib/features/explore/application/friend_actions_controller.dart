import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../domain/explore_repository.dart';
import '../domain/friend_request.dart';
import '../domain/friend_state.dart';
import '../domain/person.dart';
import 'explore_failure_copy.dart';
import 'explore_feedback_controller.dart';
import 'explore_providers.dart';

/// Every write Explore can make, in one place, with the sentence that follows it.
///
/// Each action does three things in the same order: talk to the server, refresh
/// the reads it invalidated, and raise one toast — which is also where Undo
/// lives. Nothing here mutates a list directly: the lists are the server's
/// answer, so the screen can never drift from the database.
class FriendActions {
  FriendActions(this._ref);

  final Ref _ref;

  ExploreRepository get _repo => _ref.read(exploreRepositoryProvider);

  void _toast(ExploreToast toast) =>
      _ref.read(exploreFeedbackProvider.notifier).show(toast);

  void _fail(AppFailure failure) => _toast(
    ExploreToast(
      message: exploreFailureCopy(failure),
      detail: failure.isRetryable ? 'Pull down to try again.' : null,
      tick: false,
    ),
  );

  void _refresh() => refreshExplore(_ref);

  // ------------------------------------------------------------------ accept
  Future<void> accept(FriendRequest request) async {
    final name = request.person.displayName;
    try {
      await _repo.acceptRequest(request.id);
      _refresh();
      _toast(
        ExploreToast(
          message: '${_firstName(name)} is now in your circle',
          detail: 'Open the Friends segment to say hi',
          person: request.person,
        ),
      );
    } on AppFailure catch (failure) {
      _refresh();
      _fail(failure);
    }
  }

  // ----------------------------------------------------------------- decline
  Future<void> decline(FriendRequest request) async {
    final person = request.person;
    try {
      await _repo.declineRequest(request.id);
      _refresh();
      _toast(
        ExploreToast(
          message: 'Declined ${_firstName(person.displayName)}’s request',
          detail: 'They are not told — this is your decision, quietly',
          person: person,
          onUndo: () async {
            try {
              await _repo.undoDecline(request.id);
              _refresh();
            } on AppFailure catch (failure) {
              _fail(failure);
            }
          },
        ),
      );
    } on AppFailure catch (failure) {
      _refresh();
      _fail(failure);
    }
  }

  // ------------------------------------------------------------------ cancel
  Future<void> cancel(FriendRequest request) async {
    final person = request.person;
    try {
      await _repo.cancelRequest(request.id);
      _refresh();
      _toast(
        ExploreToast(
          message: 'Request to ${_firstName(person.displayName)} cancelled',
          detail: 'They never saw it',
          person: person,
          onUndo: () async {
            try {
              await _repo.sendRequest(person.id);
              _refresh();
            } on AppFailure catch (failure) {
              _fail(failure);
            }
          },
        ),
      );
    } on AppFailure catch (failure) {
      _refresh();
      _fail(failure);
    }
  }

  // -------------------------------------------------------------------- send
  /// Returns the state the server ended up in, so a search row can paint the
  /// truth immediately: `requestedByMe`, or `friend` when they had already
  /// asked me (the SQL accepts in that case instead of stacking a second ask).
  Future<FriendState?> send(Person person) async {
    try {
      final state = await _repo.sendRequest(person.id);
      _refresh();
      if (state == FriendState.friend) {
        _toast(
          ExploreToast(
            message: '${_firstName(person.displayName)} is now in your circle',
            detail: 'They had already asked you — accepted',
            person: person,
          ),
        );
      } else {
        _toast(
          ExploreToast(
            message: 'Request sent to ${_firstName(person.displayName)}',
            detail: 'Waiting for them — see the Sent segment',
            person: person,
          ),
        );
      }
      return state;
    } on AppFailure catch (failure) {
      _fail(failure);
      return null;
    }
  }

  /// Cancel the ask I sent to [person] (used by a search result row, which has
  /// no request id of its own).
  Future<bool> cancelTo(Person person) async {
    try {
      await _repo.cancelRequestTo(person.id);
      _refresh();
      _toast(
        ExploreToast(
          message: 'Request to ${_firstName(person.displayName)} cancelled',
          detail: 'They never saw it',
          person: person,
        ),
      );
      return true;
    } on AppFailure catch (failure) {
      _fail(failure);
      return false;
    }
  }

  /// Accept the ask [person] sent me, by person.
  Future<bool> acceptFrom(Person person) async {
    try {
      await _repo.acceptRequestFrom(person.id);
      _refresh();
      _toast(
        ExploreToast(
          message: '${_firstName(person.displayName)} is now in your circle',
          detail: 'You accepted their request',
          person: person,
        ),
      );
      return true;
    } on AppFailure catch (failure) {
      _fail(failure);
      return false;
    }
  }

  /// A friend row's Message button. The chat itself lives in another feature;
  /// this only reports that the tap was understood.
  void message(Person person) {
    _toast(
      ExploreToast(
        message: 'Opening chat with ${_firstName(person.displayName)}',
        detail: person.atHandle.isEmpty ? null : person.atHandle,
        person: person,
      ),
    );
  }

  static String _firstName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'They';
    return trimmed.split(RegExp(r'\s+')).first;
  }
}

final friendActionsProvider = Provider<FriendActions>(FriendActions.new);

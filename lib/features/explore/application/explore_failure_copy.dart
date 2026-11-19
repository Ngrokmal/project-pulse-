import '../../../core/error/app_failure.dart';

/// Every failure Explore can show, as one plain sentence.
///
/// The repository already reduced errors to typed [AppFailure]s with safe codes;
/// this is the only place that turns them into words, so the same problem never
/// reads two different ways on two screens.
String exploreFailureCopy(AppFailure failure) => switch (failure) {
  FeatureUnavailableFailure() => failure.userMessage,
  NetworkFailure() => failure.userMessage,
  PermissionFailure() => failure.userMessage,
  ConfigurationFailure() => failure.userMessage,
  ServerFailure() => switch (failure.safeCode) {
    'friend_request_not_open' =>
      'That request has already been answered. Refreshing…',
    'friend_request_not_yours' => 'That request is not yours to answer.',
    'friend_request_already_open' =>
      'There is already an open request between you two.',
    'friend_request_invalid' => 'That person can’t be added.',
    'friend_undo_unavailable' => 'Too late to undo that one.',
    _ => 'That didn’t go through. Please try again.',
  },
  _ => failure.userMessage,
};

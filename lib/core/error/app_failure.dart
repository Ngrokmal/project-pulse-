/// Typed, user-safe failures. Every boundary maps its errors into these —
/// no raw exception, stack trace or secret ever reaches the UI (§11).
sealed class AppFailure implements Exception {
  const AppFailure({this.correlationId});

  final String? correlationId;

  /// Short, non-technical message shown to the user.
  String get userMessage;

  /// True when a retry can plausibly succeed.
  bool get isRetryable;

  String get code;

  /// Convenience for screens that switch to the login form when signup is
  /// blocked by the project's mail limit.
  bool get isAuthEmailRateLimited =>
      this is AuthFailure && (this as AuthFailure).suggestLogin;

  @override
  String toString() => 'AppFailure($code): $userMessage';
}

class NetworkFailure extends AppFailure {
  const NetworkFailure({
    this.timedOut = false,
    this.detail,
    super.correlationId,
  });

  final bool timedOut;

  /// Short, secret-free technical cause (exception type + message). Shown in
  /// small print and copied by the connection check, so a report from a real
  /// device is actionable instead of "it says offline".
  final String? detail;

  @override
  String get code => timedOut ? 'network_timeout' : 'network_unavailable';

  @override
  String get userMessage => timedOut
      ? "The request took too long. Please try again."
      : "You appear to be offline. Check your connection.";

  @override
  bool get isRetryable => true;
}

class AuthFailure extends AppFailure {
  const AuthFailure(
    this._message, {
    this.kind = AuthFailureKind.unknown,
    super.correlationId,
  });
  final String _message;
  final AuthFailureKind kind;

  @override
  String get code => 'auth_${kind.name}';

  @override
  String get userMessage => _message;

  @override
  bool get isRetryable =>
      kind == AuthFailureKind.rateLimited || kind == AuthFailureKind.unknown;

  /// True when signing up is blocked by the project's mail limit and the user
  /// should log in with an existing account instead.
  bool get suggestLogin => kind == AuthFailureKind.emailRateLimited;
}

enum AuthFailureKind {
  invalidCredentials,
  emailNotConfirmed,
  emailInUse,
  weakPassword,
  rateLimited,
  emailRateLimited,
  notConfigured,
  unknown,
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(this.field, this._message);
  final String field;
  final String _message;

  @override
  String get code => 'validation_$field';

  @override
  String get userMessage => _message;

  @override
  bool get isRetryable => false;
}

class PermissionFailure extends AppFailure {
  const PermissionFailure(this.what, {this.permanentlyDenied = false});
  final String what;
  final bool permanentlyDenied;

  @override
  String get code => 'permission_$what';

  @override
  String get userMessage => permanentlyDenied
      ? "Permission permanently denied. Enable it in Android settings to continue."
      : "Permission needed to continue.";

  @override
  bool get isRetryable => !permanentlyDenied;
}

class ServerFailure extends AppFailure {
  const ServerFailure({this.statusCode, this.safeCode, super.correlationId});
  final int? statusCode;
  final String? safeCode;

  @override
  String get code => safeCode ?? 'server_error';

  @override
  String get userMessage =>
      "Something went wrong on our side. Please try again.";

  @override
  bool get isRetryable => (statusCode == null || statusCode! >= 500);
}

/// A failure inside the update download or its file handling.
///
/// It exists because the generic "something went wrong" is useless when the
/// person has just waited a minute for 28 MB: each case below says what actually
/// happened and what the next tap will do.
class UpdateFailure extends AppFailure {
  const UpdateFailure(this.safeCode, this._message, {super.correlationId});

  final String safeCode;
  final String _message;

  @override
  String get code => 'update_$safeCode';

  @override
  String get userMessage => _message;

  /// Every one of these is worth another tap.
  @override
  bool get isRetryable => true;
}

/// The server says this account may not act (§25).
///
/// It is not an error to retry: the same request will be refused until a human
/// lifts the hold, so the UI must never offer "try again" for it — it shows the
/// hold screen instead. `code` is the SQLSTATE the database guard raises, so a
/// failure that crossed three layers still says exactly what happened.
class AccountSuspendedFailure extends AppFailure {
  const AccountSuspendedFailure({this.detail, super.correlationId});

  final String? detail;

  @override
  String get code => 'account_suspended';

  @override
  String get userMessage =>
      'This account is on hold, so nothing can be sent or received. '
      'Open the notice to see why, or to ask a person to look again.';

  @override
  bool get isRetryable => false;
}

/// A server-authoritative per-user feature control rejected the action.
class AdminControlFailure extends AppFailure {
  const AdminControlFailure(this.controlCode);
  final String controlCode;

  @override
  String get code => controlCode;

  @override
  String get userMessage => switch (controlCode) {
    'message_send_disabled' => 'Messaging is not available for this account.',
    'call_start_disabled' =>
      'Starting calls is not available for this account.',
    'profile_photo_change_disabled' =>
      'Changing the profile photo is not available for this account.',
    _ => 'This action is not available for this account.',
  };

  @override
  bool get isRetryable => false;
}

/// The account already has an appeal waiting.
///
/// The server enforces one open appeal per account (a partial unique index), so
/// this is a real answer, not an error: the notice shows the receipt instead of
/// asking the person to write the same sentences twice.
class AppealAlreadyOpenFailure extends AppFailure {
  const AppealAlreadyOpenFailure();

  @override
  String get code => 'appeal_already_open';

  @override
  String get userMessage =>
      'An appeal from this account is already waiting to be read.';

  @override
  bool get isRetryable => false;
}

/// A feature whose backend half has not been applied yet.
///
/// This exists so the Explore tab can say the true thing ("run 0010_friends.sql")
/// instead of a vague "something went wrong", and so a partially migrated
/// backend is never mistaken for a bug in the app.
class FeatureUnavailableFailure extends AppFailure {
  const FeatureUnavailableFailure(this.feature);

  /// What is missing, in one or two words — e.g. `friends`.
  final String feature;

  @override
  String get code => 'feature_unavailable_$feature';

  @override
  String get userMessage =>
      'This build’s backend is missing the $feature tables. '
      'Apply supabase/migrations/0010_friends.sql and try again.';

  @override
  bool get isRetryable => true;
}

class ConfigurationFailure extends AppFailure {
  const ConfigurationFailure(this.detail);
  final String detail;

  @override
  String get code => 'configuration_missing';

  @override
  String get userMessage => "This build is missing backend configuration.";

  @override
  bool get isRetryable => false;
}

enum MediaFailureReason { unavailable, tooLarge, write, badUrl }

/// A file whose *bytes* could not be handed over, said plainly.
///
/// `unavailable` is the honest one: some attachments were stored under file
/// types the CDN refuses to serve (a Cloudinary account setting we cannot change
/// from the app), so the row exists but the bytes are gone. New uploads avoid
/// that by sending such documents as opaque blobs.
class MediaFailure extends AppFailure {
  const MediaFailure(this.reason, {super.correlationId});

  final MediaFailureReason reason;

  @override
  String get code => 'media_${reason.name}';

  @override
  String get userMessage => switch (reason) {
    MediaFailureReason.unavailable =>
      "This file can't be downloaded — it was sent before attachments were "
          "fixed and the media service no longer serves it.",
    MediaFailureReason.tooLarge =>
      'This file is too large to save on this device.',
    MediaFailureReason.write => "Couldn't save the file on this device.",
    MediaFailureReason.badUrl => 'This attachment link is not valid.',
  };

  @override
  bool get isRetryable =>
      reason == MediaFailureReason.write ||
      reason == MediaFailureReason.unavailable;
}

class StorageFailure extends AppFailure {
  const StorageFailure({required this.insufficientSpace});
  final bool insufficientSpace;

  @override
  String get code => insufficientSpace ? 'storage_full' : 'storage_error';

  @override
  String get userMessage => insufficientSpace
      ? "Not enough free storage on this device."
      : "Could not read or write the file on this device.";

  @override
  bool get isRetryable => !insufficientSpace;
}

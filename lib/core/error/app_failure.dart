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
}

enum AuthFailureKind {
  invalidCredentials,
  emailNotConfirmed,
  emailInUse,
  weakPassword,
  rateLimited,
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

abstract interface class ErrorMessageRepository {
  /// Returns null when there is no server override. Network failures may throw;
  /// callers must retain a safe local fallback.
  Future<String?> fetch(String code);
}

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

/// Structured logger with mandatory redaction (§11 LOGGING).
/// Never call this with tokens, passwords, service-account JSON or raw
/// private URLs — [redact] is the last line of defence, not an excuse.
class AppLogger {
  AppLogger(this.feature);

  final String feature;

  static final List<RegExp> _secretPatterns = [
    RegExp(
      r'eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}',
    ), // JWT
    RegExp(r'sb[a-z]?_[A-Za-z0-9_\-]{16,}'), // Supabase keys
    RegExp(r'gh[pousr]_[A-Za-z0-9]{20,}'), // GitHub token
    RegExp(r'"private_key"\s*:\s*"-----BEGIN[^"]+"'),
    RegExp(
      r'(apikey|api_key|token|password|secret)"?\s*[:=]\s*"?[^"\s,}]+',
      caseSensitive: false,
    ),
  ];

  static String redact(String input) {
    var out = input;
    for (final p in _secretPatterns) {
      out = out.replaceAll(p, '[REDACTED]');
    }
    return out;
  }

  void log(
    LogLevel level,
    String operation, {
    String? correlationId,
    Object? error,
    Map<String, Object?>? data,
  }) {
    if (!kDebugMode && level == LogLevel.debug) {
      return;
    }
    final buf = StringBuffer(
      '[${level.name.toUpperCase()}] $feature.$operation',
    );
    if (correlationId != null) {
      buf.write(' cid=$correlationId');
    }
    if (data != null && data.isNotEmpty) {
      buf.write(' ${redact(data.toString())}');
    }
    if (error != null) {
      buf.write(' err=${redact(error.toString())}');
    }
    debugPrint(buf.toString());
  }

  void info(String op, {String? correlationId, Map<String, Object?>? data}) =>
      log(LogLevel.info, op, correlationId: correlationId, data: data);

  void warning(
    String op, {
    String? correlationId,
    Object? error,
    Map<String, Object?>? data,
  }) => log(
    LogLevel.warning,
    op,
    correlationId: correlationId,
    error: error,
    data: data,
  );

  void error(
    String op, {
    String? correlationId,
    Object? error,
    Map<String, Object?>? data,
  }) => log(
    LogLevel.error,
    op,
    correlationId: correlationId,
    error: error,
    data: data,
  );
}

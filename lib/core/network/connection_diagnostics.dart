import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';

/// One step of a real connectivity check. Every field is measured, never guessed.
class DiagnosticStep {
  const DiagnosticStep({
    required this.name,
    required this.ok,
    this.milliseconds,
    this.detail,
    this.hint,
  });

  final String name;
  final bool ok;
  final int? milliseconds;
  final String? detail;

  /// What the user (or I) should do about this specific failure.
  final String? hint;

  String get label => ok ? 'OK' : 'FAILED';
}

/// Diagnoses *why* the app cannot reach Supabase instead of showing a blanket
/// "you appear to be offline". This exists because release APKs up to Phase 2
/// were built without the INTERNET permission and every request failed with no
/// way to tell whether the network, DNS, TLS or the key was at fault.
class ConnectionDiagnostics {
  const ConnectionDiagnostics();

  static const Duration timeout = Duration(seconds: 12);

  Future<List<DiagnosticStep>> run() async {
    final steps = <DiagnosticStep>[];
    final hasConfig = AppConfig.isBackendConfigured;
    steps.add(
      DiagnosticStep(
        name: 'Backend configuration',
        ok: hasConfig,
        detail: hasConfig
            ? 'URL + key embedded in this build'
            : 'SUPABASE_URL / SUPABASE_ANON_KEY missing',
        hint: hasConfig
            ? null
            : 'This APK was built without the build-time defines.',
      ),
    );
    if (!hasConfig) return steps;

    final uri = Uri.parse(AppConfig.supabaseUrl);
    steps.add(DiagnosticStep(name: 'Endpoint', ok: true, detail: uri.host));

    // 1. DNS
    final dns = Stopwatch()..start();
    try {
      final addresses = await InternetAddress.lookup(uri.host);
      dns.stop();
      steps.add(
        DiagnosticStep(
          name: 'DNS lookup',
          ok: addresses.isNotEmpty,
          milliseconds: dns.elapsedMilliseconds,
          detail: addresses.isEmpty
              ? 'no address returned'
              : addresses.map((a) => a.address).join(', '),
        ),
      );
    } catch (e) {
      dns.stop();
      steps.add(
        DiagnosticStep(
          name: 'DNS lookup',
          ok: false,
          milliseconds: dns.elapsedMilliseconds,
          detail: _short(e),
          hint: 'Change network (Wi-Fi ↔ mobile data) or check DNS/blocking.',
        ),
      );
      return steps; // nothing else can work
    }

    // 2. TLS + HTTP against the auth endpoint the app uses on first launch
    final http = Stopwatch()..start();
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(uri.replace(path: '/auth/v1/settings'))
          .timeout(timeout);
      request.headers.set('apikey', AppConfig.supabaseAnonKey);
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      http.stop();
      final healthy = response.statusCode == 200;
      steps.add(
        DiagnosticStep(
          name: 'HTTPS to Supabase',
          ok: healthy,
          milliseconds: http.elapsedMilliseconds,
          detail: 'HTTP ${response.statusCode}',
          hint: healthy ? null : _httpHint(response.statusCode, body),
        ),
      );
    } on TimeoutException {
      http.stop();
      steps.add(
        DiagnosticStep(
          name: 'HTTPS to Supabase',
          ok: false,
          milliseconds: http.elapsedMilliseconds,
          detail: 'timed out after ${timeout.inSeconds}s',
          hint: 'The network is reachable but very slow or filtering TLS.',
        ),
      );
      return steps;
    } catch (e) {
      http.stop();
      steps.add(
        DiagnosticStep(
          name: 'HTTPS to Supabase',
          ok: false,
          milliseconds: http.elapsedMilliseconds,
          detail: _short(e),
          hint:
              'If DNS works but HTTPS fails, a firewall/VPN or the device clock '
              'is the usual cause.',
        ),
      );
      return steps;
    } finally {
      client.close(force: true);
    }

    // 3. The REST layer with the project key (a 401/403 here is healthy: it
    //    proves PostgREST and the key are alive and RLS is doing its job).
    final rest = Stopwatch()..start();
    final restClient = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await restClient
          .getUrl(
            uri.replace(path: '/rest/v1/profiles', query: 'select=id&limit=1'),
          )
          .timeout(timeout);
      request.headers.set('apikey', AppConfig.supabaseAnonKey);
      request.headers.set(
        'Authorization',
        'Bearer ${AppConfig.supabaseAnonKey}',
      );
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      rest.stop();
      final healthy = [200, 401, 403].contains(response.statusCode);
      steps.add(
        DiagnosticStep(
          name: 'Database API',
          ok: healthy,
          milliseconds: rest.elapsedMilliseconds,
          detail:
              'HTTP ${response.statusCode}'
              '${response.statusCode == 401 || response.statusCode == 403 ? ' (expected without a session)' : ''}',
          hint: healthy ? null : _httpHint(response.statusCode, ''),
        ),
      );
    } catch (e) {
      rest.stop();
      steps.add(
        DiagnosticStep(
          name: 'Database API',
          ok: false,
          milliseconds: rest.elapsedMilliseconds,
          detail: _short(e),
        ),
      );
    } finally {
      restClient.close(force: true);
    }

    return steps;
  }

  static String _short(Object e) {
    final text = e.toString();
    return text.length > 140 ? '${text.substring(0, 140)}…' : text;
  }

  static String _httpHint(int status, String body) => switch (status) {
    401 ||
    403 => 'The project rejected this build key. Rebuild with the current key.',
    404 => 'Endpoint not found — check SUPABASE_URL.',
    429 => 'Rate limited. Wait a moment and retry.',
    >= 500 => 'Supabase is having trouble. Retry shortly.',
    _ => body.isEmpty ? 'Unexpected response.' : body,
  };
}

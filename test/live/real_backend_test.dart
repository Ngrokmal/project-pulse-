// Live probe of the exact client path the app uses (supabase_flutter's client,
// real network, real project). Not part of the CI suite: run it with
//
//   flutter test test/live/real_backend_test.dart \
//     --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
//
// It explains *why* a device would show a network error: DNS, TLS, HTTP status
// or a rejected key are each reported separately.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const url = String.fromEnvironment('SUPABASE_URL');
const key = String.fromEnvironment('SUPABASE_ANON_KEY');

void main() {
  // The CI suite runs without dart-defines, so this file skips itself instead of
  // failing the build. It only runs when pointed at a real project.
  if (url.isEmpty || key.isEmpty) {
    test(
      'live backend probe',
      () {},
      skip: 'run with --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
    );
    return;
  }

  test('config is present at build time', () {
    expect(url, isNotEmpty, reason: 'SUPABASE_URL missing');
    expect(key, isNotEmpty, reason: 'SUPABASE_ANON_KEY missing');
  });

  test('DNS + TLS + HTTP reachability of the project', () async {
    final uri = Uri.parse(url);
    final lookup = await InternetAddress.lookup(uri.host);
    expect(lookup, isNotEmpty, reason: 'DNS failed for ${uri.host}');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final sw = Stopwatch()..start();
    final req = await client.getUrl(uri.replace(path: '/auth/v1/settings'));
    req.headers.set('apikey', key);
    final res = await req.close();
    final body = await res.transform(const SystemEncoding().decoder).join();
    sw.stop();
    client.close();
    // ignore: avoid_print
    print(
      'HTTP ${res.statusCode} in ${sw.elapsedMilliseconds}ms :: ${body.substring(0, body.length.clamp(0, 120))}',
    );
    expect(res.statusCode, 200);
  });

  test('the SDK client can talk to GoTrue with this key', () async {
    final client = SupabaseClient(url, key);
    final sw = Stopwatch()..start();
    final session = await client.auth.getSession();
    sw.stop();
    // ignore: avoid_print
    print(
      'auth.getSession ok in ${sw.elapsedMilliseconds}ms '
      '(session=${session != null})',
    );
    expect(sw.elapsedMilliseconds, lessThan(15000));
  });

  test('an unauthenticated table read fails with a typed API error, not a socket error', () async {
    final client = SupabaseClient(url, key);
    try {
      await client.from('profiles').select('id').limit(1);
      // ignore: avoid_print
      print('unexpected success');
    } on PostgrestException catch (e) {
      // ignore: avoid_print
      print('PostgrestException code=${e.code} message=${e.message}');
      expect(e.code, isNotNull);
    }
  });
}

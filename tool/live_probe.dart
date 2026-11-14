// Standalone probe of the real backend using the same HTTP stack the app uses
// (package:supabase → package:http). Run:
//   dart run tool/live_probe.dart
import 'dart:io';

import 'package:supabase/supabase.dart';

Future<void> main() async {
  final env = <String, String>{};
  for (final line in File('/home/user/.secrets/env').readLinesSync()) {
    final i = line.indexOf('=');
    if (i > 0 && !line.startsWith('#')) env[line.substring(0, i)] = line.substring(i + 1);
  }
  final url = env['SUPABASE_URL']!;
  final key = env['SUPABASE_ANON_KEY']!;

  print('url host      : ${Uri.parse(url).host}');
  print('key kind      : ${key.startsWith('sb_publishable_') ? 'publishable (new format)' : 'anon JWT'}');
  print('key length    : ${key.length}');

  final sw = Stopwatch()..start();
  try {
    final lookup = await InternetAddress.lookup(Uri.parse(url).host);
    print('DNS           : ${lookup.map((a) => a.address).join(', ')} in ${sw.elapsedMilliseconds}ms');
  } catch (e) {
    print('DNS           : FAILED $e');
  }

  sw.reset();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse('$url/auth/v1/settings'));
    req.headers.set('apikey', key);
    final res = await req.close();
    final body = await res.transform(const SystemEncoding().decoder).join();
    print('raw HTTP      : ${res.statusCode} in ${sw.elapsedMilliseconds}ms :: ${body.substring(0, body.length.clamp(0, 100))}');
  } catch (e) {
    print('raw HTTP      : FAILED $e');
  } finally {
    client.close();
  }

  sw.reset();
  try {
    final sb = SupabaseClient(url, key);
    final session = await sb.auth.getSession();
    print('sdk getSession: ok in ${sw.elapsedMilliseconds}ms (session=${session.session != null})');
  } catch (e) {
    print('sdk getSession: FAILED ${e.runtimeType}: $e');
  }

  sw.reset();
  try {
    final sb = SupabaseClient(url, key);
    await sb.from('profiles').select('id').limit(1);
    print('sdk table read: unexpected success (RLS should deny anon)');
  } on PostgrestException catch (e) {
    print('sdk table read: PostgrestException ${e.code} in ${sw.elapsedMilliseconds}ms');
  } catch (e) {
    print('sdk table read: FAILED ${e.runtimeType}: $e');
  }
}

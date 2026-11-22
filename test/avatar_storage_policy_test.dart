import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/core/error/app_failure.dart';
import 'package:pulse/features/profile/data/supabase_profile_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final scenario in ['disabled', 'allowed', 'old_server']) {
    test('storage 403 maps safely when policy is $scenario', () async {
      var rpcCalls = 0;
      final client = SupabaseClient(
        'https://example.invalid',
        'fake-public-key',
        accessToken: () async => 'fake-token',
        httpClient: MockClient((request) async {
          if (request.url.path.contains('/storage/v1/object/')) {
            return http.Response(
              '{"statusCode":"403","error":"Unauthorized","message":"RLS denied"}',
              403,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith(
            '/rpc/pulse_own_photo_change_allowed',
          )) {
            rpcCalls++;
            return scenario == 'old_server'
                ? http.Response(
                    '{"code":"PGRST202","message":"missing"}',
                    404,
                    request: request,
                    headers: {'content-type': 'application/json'},
                  )
                : http.Response(
                    scenario == 'allowed' ? 'true' : 'false',
                    200,
                    request: request,
                    headers: {'content-type': 'application/json'},
                  );
          }
          throw StateError('Unexpected mocked path: ${request.url.path}');
        }),
      );
      addTearDown(client.dispose);
      if (scenario == 'disabled') {
        final value = await client.rpc('pulse_own_photo_change_allowed');
        expect(value, false);
        rpcCalls = 0;
      }
      final repo = SupabaseProfileRepository(client);
      await expectLater(
        repo.uploadAvatar(
          userId: 'test-user',
          bytes: Uint8List.fromList([1, 2]),
          mimeType: 'image/png',
          takenAt: DateTime.utc(2026),
        ),
        throwsA(
          scenario == 'disabled'
              ? isA<AdminControlFailure>().having(
                  (e) => e.code,
                  'code',
                  'profile_photo_change_disabled',
                )
              : isA<ServerFailure>().having(
                  (e) => e.safeCode,
                  'safeCode',
                  'avatar_upload_failed',
                ),
        ),
      );
      expect(rpcCalls, 1);
    });
  }
}

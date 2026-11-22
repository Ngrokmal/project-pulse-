import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/core/error/app_failure.dart';
import 'package:pulse/features/chat/data/supabase_chat_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final scenario in [
    'same',
    'changed',
    'missing',
    'lookup_denied',
    'constraint',
  ]) {
    test('idempotency recovery: $scenario', () async {
      var inserts = 0;
      var lookups = 0;
      final token =
          '${base64Url.encode(utf8.encode('{"alg":"none"}')).replaceAll('=', '')}.${base64Url.encode(utf8.encode('{"sub":"user-1","exp":4102444800}')).replaceAll('=', '')}.sig';
      final client = SupabaseClient(
        'https://example.invalid',
        'fake-public-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          http.Response response(String data, int status) => http.Response(
            data,
            status,
            request: request,
            headers: {'content-type': 'application/json'},
          );
          if (request.url.path.endsWith('/auth/v1/token')) {
            return response(
              jsonEncode({
                'access_token': token,
                'refresh_token': 'dummy',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': {'id': 'user-1', 'aud': 'authenticated'},
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/rest/v1/messages') &&
              request.method == 'POST') {
            inserts++;
            return scenario == 'constraint'
                ? response(
                    '{"code":"23514","message":"constraint violation"}',
                    400,
                  )
                : response(
                    '{"code":"23505","message":"unique violation"}',
                    409,
                  );
          }
          if (request.url.path.endsWith('/rest/v1/messages') &&
              request.method == 'GET') {
            lookups++;
            expect(request.url.queryParameters['sender_id'], 'eq.user-1');
            expect(request.url.queryParameters['client_id'], 'eq.client-key');
            if (scenario == 'lookup_denied') {
              return response('{"code":"42501","message":"not allowed"}', 403);
            }
            if (scenario == 'missing') return response('null', 200);
            return response(
              jsonEncode({
                'id': 'server-row',
                'conversation_id': 'conversation',
                'sender_id': 'user-1',
                'kind': 'text',
                'body': scenario == 'changed' ? 'different' : 'hello',
                'client_id': 'client-key',
                'created_at': '2026-01-01T00:00:00Z',
                'media_url': null,
                'media_name': null,
                'media_bytes': null,
                'duration_ms': null,
              }),
              200,
            );
          }
          throw StateError(
            'Unexpected mock request ${request.method} ${request.url.path}',
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        email: 'test@example.invalid',
        password: 'dummy',
      );
      final repo = SupabaseChatRepository(client);
      final future = repo.sendMessage(
        conversationId: 'conversation',
        clientId: 'client-key',
        body: 'hello',
      );
      if (scenario == 'same') {
        expect((await future).id, 'server-row');
      } else {
        await expectLater(
          future,
          throwsA(
            isA<ServerFailure>().having(
              (e) => e.isRetryable,
              'retryable',
              false,
            ),
          ),
        );
      }
      expect(inserts, 1);
      expect(lookups, scenario == 'constraint' ? 0 : 1);
    });
  }
}

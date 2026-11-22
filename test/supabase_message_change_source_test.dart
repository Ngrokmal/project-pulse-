import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/features/chat/data/supabase_message_change_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final scenario in ['normal', 'mismatch', 'denied']) {
    test('journal SDK adapter: $scenario', () async {
      final token =
          '${base64Url.encode(utf8.encode('{"alg":"none"}')).replaceAll('=', '')}.${base64Url.encode(utf8.encode('{"sub":"owner","exp":4102444800}')).replaceAll('=', '')}.sig';
      final client = SupabaseClient(
        'https://example.invalid',
        'fake-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          http.Response response(Object body, int status) => http.Response(
            jsonEncode(body),
            status,
            request: request,
            headers: {'content-type': 'application/json'},
          );
          if (request.url.path.endsWith('/auth/v1/token')) {
            return response({
              'access_token': token,
              'refresh_token': 'dummy',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {'id': 'owner', 'aud': 'authenticated'},
            }, 200);
          }
          expect(
            request.url.path,
            endsWith('/rest/v1/rpc/pulse_message_changes_since'),
          );
          expect(jsonDecode(request.body), {
            'p_conversation': 'conversation',
            'p_after': 0,
            'p_limit': 2,
          });
          if (scenario == 'denied') {
            return response({'code': '42501', 'message': 'denied'}, 403);
          }
          return response([
            {
              'revision': 1,
              'message_id': 'row',
              'message': {
                'id': scenario == 'mismatch' ? 'wrong' : 'row',
                'conversation_id': 'conversation',
                'sender_id': 'owner',
                'kind': 'text',
                'body': 'hello',
                'created_at': '2026-01-01T00:00:00Z',
              },
            },
            {'revision': 2, 'message_id': 'deleted', 'message': null},
          ], 200);
        }),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        email: 'fake@example.invalid',
        password: 'dummy',
      );
      final source = SupabaseMessageChangeSource(client, 'owner');
      if (scenario == 'normal') {
        final changes = await source.changes('conversation', 0, 2);
        expect(changes.first.message!.body, 'hello');
        expect(changes.last.deletedId, 'deleted');
      } else if (scenario == 'mismatch') {
        await expectLater(
          source.changes('conversation', 0, 2),
          throwsFormatException,
        );
      } else {
        await expectLater(
          source.changes('conversation', 0, 2),
          throwsA(isA<PostgrestException>()),
        );
      }
      await expectLater(
        SupabaseMessageChangeSource(
          client,
          'other',
        ).changes('conversation', 0, 2),
        throwsStateError,
      );
    });
  }
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/features/chat/data/supabase_chat_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'latest page has a stable total order even for equal timestamps',
    () async {
      Uri? requested;
      final client = SupabaseClient(
        'https://example.invalid',
        'fake-public-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requested = request.url;
          final rows = [
            {
              'id': 'b',
              'conversation_id': 'c',
              'sender_id': 'u',
              'kind': 'text',
              'body': 'b',
              'created_at': '2026-01-01T00:00:00Z',
            },
            {
              'id': 'a',
              'conversation_id': 'c',
              'sender_id': 'u',
              'kind': 'text',
              'body': 'a',
              'created_at': '2026-01-01T00:00:00Z',
            },
          ];
          return http.Response(
            jsonEncode(rows),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final rows = await SupabaseChatRepository(client).messages('c', limit: 2);
      expect(
        requested!.queryParameters['order'],
        'created_at.desc.nullslast,id.desc.nullslast',
      );
      expect(requested!.queryParameters['limit'], '2');
      expect(rows.map((row) => row.id), ['a', 'b']);
    },
  );
}

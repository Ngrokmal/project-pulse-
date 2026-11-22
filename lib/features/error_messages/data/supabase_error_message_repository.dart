import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/error_message_repository.dart';

class SupabaseErrorMessageRepository implements ErrorMessageRepository {
  SupabaseErrorMessageRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<String?> fetch(String code) async {
    final value = await _client.rpc(
      'pulse_error_message',
      params: {'p_code': code},
    );
    if (value is! String || value.trim().isEmpty || value.length > 500) {
      return null;
    }
    return value.trim();
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../data/supabase_error_message_repository.dart';
import '../domain/error_message_repository.dart';

final errorMessageRepositoryProvider = Provider<ErrorMessageRepository?>((ref) {
  if (!AppConfig.isBackendConfigured) return null;
  return SupabaseErrorMessageRepository(Supabase.instance.client);
});

/// Server text is optional, bounded and time-limited. Offline, a missing RPC,
/// malformed response or timeout must not hide the failure or lose a draft.
Future<String> resolveErrorMessage(WidgetRef ref, AppFailure failure) async {
  try {
    final repo = ref.read(errorMessageRepositoryProvider);
    final override = await repo
        ?.fetch(failure.code)
        .timeout(const Duration(seconds: 2));
    return override ?? failure.userMessage;
  } catch (_) {
    return failure.userMessage;
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../data/supabase_account_status_repository.dart';
import '../domain/account_status.dart';

final accountStatusRepositoryProvider = Provider<AccountStatusRepository>((
  ref,
) {
  if (!AppConfig.isBackendConfigured) {
    throw const ConfigurationFailure(
      'Supabase is not configured for this build.',
    );
  }
  return SupabaseAccountStatusRepository(Supabase.instance.client);
});

class AccountStatusController extends AsyncNotifier<AccountStatusInfo?> {
  @override
  Future<AccountStatusInfo?> build() async {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthSignedIn) return null;
    return ref.read(accountStatusRepositoryProvider).fetchMine(auth.user.id);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final auth = ref.read(authControllerProvider);
      if (auth is! AuthSignedIn) return null;
      return ref.read(accountStatusRepositoryProvider).fetchMine(auth.user.id);
    });
  }
}

final accountStatusControllerProvider =
    AsyncNotifierProvider<AccountStatusController, AccountStatusInfo?>(
      AccountStatusController.new,
    );

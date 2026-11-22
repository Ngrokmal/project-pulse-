import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../data/supabase_admin_repository.dart';
import '../domain/admin_repository.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  if (!AppConfig.isBackendConfigured) {
    throw const ConfigurationFailure('Supabase is not configured.');
  }
  return SupabaseAdminRepository(Supabase.instance.client);
});

/// This is only a presentation gate. Each server RPC independently authorises.
final adminAccessProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(authControllerProvider) is! AuthSignedIn) return false;
  return ref.read(adminRepositoryProvider).isAdmin();
});

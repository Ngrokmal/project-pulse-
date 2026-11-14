import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/application/auth_controller.dart';
import '../data/device_registration_service.dart';

final deviceRegistrationServiceProvider = Provider<DeviceRegistrationService>((
  ref,
) {
  if (!AppConfig.isBackendConfigured) {
    throw const ConfigurationFailure(
      'Supabase is not configured for this build.',
    );
  }
  return DeviceRegistrationService(client: Supabase.instance.client);
});

/// Runs once per session after sign-in. A failure is surfaced (never hidden),
/// but it does not block the app: device registration is security telemetry,
/// not a permission to use the product.
class DeviceRegistrationController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthSignedIn) return;
    await ref.read(deviceRegistrationServiceProvider).register();
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final auth = ref.read(authControllerProvider);
      if (auth is! AuthSignedIn) return;
      await ref.read(deviceRegistrationServiceProvider).register();
    });
    if (state.hasError) {
      AppLogger('device').warning('device_registration_retry_failed');
    }
  }
}

final deviceRegistrationControllerProvider =
    AsyncNotifierProvider<DeviceRegistrationController, void>(
      DeviceRegistrationController.new,
    );

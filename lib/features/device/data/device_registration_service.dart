import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/platform/device_identity.dart';

/// Registers this device with the trusted backend (§31.7).
/// All privileged work happens in the device-register Edge Function; the client
/// only proves who it is and hands over the Android ID over TLS.
class DeviceRegistrationService {
  DeviceRegistrationService({
    required SupabaseClient client,
    DeviceIdentity identity = const DeviceIdentity(),
    AppLogger? logger,
  }) : this._(client, identity, logger);

  DeviceRegistrationService._(this._client, this.identity, AppLogger? logger)
    : _log = logger ?? AppLogger('device');

  final SupabaseClient _client;
  final DeviceIdentity identity;
  final AppLogger _log;

  Future<void> register() async {
    final androidId = await identity.androidId();
    if (androidId == null) {
      // Not fatal: the device simply stays unregistered. Explicit, not hidden.
      throw const ServerFailure(safeCode: 'device_id_unavailable');
    }

    try {
      final res = await _client.functions.invoke(
        'device-register',
        body: {'androidId': androidId, 'platform': 'android'},
      );
      final data = res.data;
      if (data is Map && data['ok'] == false) {
        final error = data['error'];
        final code = error is Map ? (error['code'] as String?) : null;
        if (code == 'device_banned') {
          throw const ServerFailure(statusCode: 403, safeCode: 'device_banned');
        }
        throw ServerFailure(safeCode: code ?? 'device_register_failed');
      }
      _log.info('device_registered');
    } on AppFailure {
      rethrow;
    } catch (e) {
      _log.warning('device_register_failed', error: e);
      throw const ServerFailure(safeCode: 'device_register_failed');
    }
  }
}

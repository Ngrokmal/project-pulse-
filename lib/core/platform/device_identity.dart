import 'package:flutter/services.dart';

/// Reads Android's Settings.Secure.ANDROID_ID through a small platform channel.
///
/// The raw value is sent ONLY to the device-register Edge Function over TLS,
/// which stores a keyed HMAC of it. It is never persisted locally, never
/// logged, and never used as a hardware identifier (§31.7).
class DeviceIdentity {
  const DeviceIdentity({MethodChannel? channel})
    : _channel = channel ?? defaultChannel;

  static const MethodChannel defaultChannel = MethodChannel('pulse/device');

  final MethodChannel _channel;

  /// Returns null when the platform is unsupported or the value is unavailable.
  Future<String?> androidId() async {
    try {
      final value = await _channel.invokeMethod<String>('androidId');
      if (value == null || value.trim().isEmpty) return null;
      return value.trim();
    } on MissingPluginException {
      return null; // not an Android build (e.g. tests, web)
    } on PlatformException {
      return null; // restricted/unavailable on this device
    }
  }
}

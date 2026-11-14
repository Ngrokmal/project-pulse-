import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/platform/device_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pulse/device');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('returns the Android ID reported by the platform', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'androidId');
          return '9774d56d682e549c';
        });

    expect(await const DeviceIdentity().androidId(), '9774d56d682e549c');
  });

  test(
    'returns null (never throws) when the platform value is empty',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => '   ');
      expect(await const DeviceIdentity().androidId(), isNull);
    },
  );

  test('returns null when the platform reports an error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'android_id_unavailable');
        });
    expect(await const DeviceIdentity().androidId(), isNull);
  });

  test('returns null when there is no Android implementation', () async {
    // No handler registered → MissingPluginException on platforms without it.
    expect(await const DeviceIdentity().androidId(), isNull);
  });
}

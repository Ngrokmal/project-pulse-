import 'package:flutter/services.dart';

/// The three Android questions this feature cannot answer in Dart:
/// may this app install packages at all, take me to the setting that allows it,
/// and hand this file to the system installer.
///
/// All three live on one channel (`pulse/installer`, implemented in
/// MainActivity). The APK is handed over as a `content://` URI through the
/// app's own FileProvider, so nothing is world-readable.
class ApkInstaller {
  const ApkInstaller([this._channel = const MethodChannel(_channelName)]);

  static const String _channelName = 'pulse/installer';
  final MethodChannel _channel;

  /// False means Android will refuse the install until the user allows
  /// "install unknown apps" for Pulse.
  Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the per-app "install unknown apps" screen.
  Future<void> openInstallSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on PlatformException {
      // Nothing to do: the card simply stays until the user finds Settings.
    } on MissingPluginException {
      // Same.
    }
  }

  /// Starts the system installer. It asks for its own confirmation; that tap is
  /// Android's, not ours, and cannot be skipped by any non-system app.
  Future<void> install(String apkPath) async {
    try {
      await _channel.invokeMethod<void>('install', <String, Object?>{
        'path': apkPath,
      });
    } on PlatformException catch (error) {
      throw PlatformException(code: error.code, message: error.message);
    }
  }
}

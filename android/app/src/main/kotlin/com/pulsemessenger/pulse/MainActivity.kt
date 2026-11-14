package com.pulsemessenger.pulse

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes Android's Settings.Secure.ANDROID_ID so the app can send it to the
 * device-register Edge Function, which stores only a keyed HMAC of it.
 * The value is never logged and never persisted on device.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "pulse/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "androidId" -> {
                        try {
                            val id = Settings.Secure.getString(
                                contentResolver,
                                Settings.Secure.ANDROID_ID
                            )
                            result.success(id)
                        } catch (e: Exception) {
                            result.error("android_id_unavailable", "Android ID unavailable", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

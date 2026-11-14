package com.pulsemessenger.pulse

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.provider.Settings
import androidx.core.content.getSystemService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Two platform responsibilities live here:
 *
 * 1. `pulse/device` — exposes Settings.Secure.ANDROID_ID so the app can hand it
 *    to the device-register Edge Function, which stores only a keyed HMAC of it.
 *    The raw value is never logged and never persisted on device.
 * 2. A notification channel created before the first push can arrive, matching
 *    the channel id declared in AndroidManifest.xml (pulse_default).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "pulse/device"
    private val notificationChannelId = "pulse_default"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannel()

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

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService<NotificationManager>() ?: return
        if (manager.getNotificationChannel(notificationChannelId) != null) return

        val channel = NotificationChannel(
            notificationChannelId,
            "Messages and calls",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "New messages, incoming calls and Force Audio alerts"
            enableVibration(true)
            enableLights(true)
        }
        manager.createNotificationChannel(channel)
    }
}

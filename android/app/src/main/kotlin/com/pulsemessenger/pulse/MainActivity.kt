package com.pulsemessenger.pulse

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.content.getSystemService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Three platform responsibilities live here:
 *
 * 1. `pulse/device` — exposes Settings.Secure.ANDROID_ID so the app can hand it
 *    to the device-register Edge Function, which stores only a keyed HMAC of it.
 *    The raw value is never logged and never persisted on device.
 * 2. A notification channel created before the first push can arrive, matching
 *    the channel id declared in AndroidManifest.xml (pulse_default).
 * 3. `pulse/installer` — the only way a sideloaded app can update itself: ask
 *    whether Android allows installs, open the setting that allows them, and hand
 *    the verified APK to the system installer as a `content://` URI. The APK is
 *    never exposed as a file path to anyone but this activity.
 */
class MainActivity : FlutterActivity() {
    private val deviceChannelName = "pulse/device"
    private val installerChannelName = "pulse/installer"
    private val notificationChannelId = "pulse_default"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannelName)
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installerChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(canInstallPackages())
                    "openSettings" -> {
                        openInstallSettings()
                        result.success(null)
                    }
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("invalid_path", "No APK path was given", null)
                            return@setMethodCallHandler
                        }
                        try {
                            installApk(File(path))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("install_failed", e.message ?: "Installer refused", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Android 8+ gates package installs behind a per-app user grant. */
    private fun canInstallPackages(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName")
        ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
        startActivity(intent)
    }

    /**
     * Starts the system installer for a verified APK. The `content://` grant is
     * scoped to this launch — nothing on the device can read the file afterwards.
     */
    private fun installApk(file: File) {
        if (!file.exists()) {
            throw IllegalStateException("The downloaded update is missing")
        }

        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
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

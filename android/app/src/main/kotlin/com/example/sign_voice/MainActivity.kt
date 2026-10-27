package com.example.sign_voice

import android.content.ActivityNotFoundException
import android.content.Intent
import android.app.NotificationManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var hands: NativeHandTracker? = null
    private var google: NativeGoogleSignIn? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val googleSignIn = NativeGoogleSignIn(this)
        google = googleSignIn
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "signvoice/google")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "signIn" -> googleSignIn.signIn(call.argument("clientId"), call.argument("nonce"), result)
                    "clear" -> googleSignIn.clear(result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "signvoice/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> {
                        val manager = getSystemService(NotificationManager::class.java)
                        val blocked = Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel("signvoice_study")?.importance == NotificationManager.IMPORTANCE_NONE
                        result.success(mapOf("channelBlocked" to blocked))
                    }
                    "openNotificationSettings", "openBatterySettings" -> {
                        val intent = if (call.method == "openBatterySettings") Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            else Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        try { startActivity(intent); result.success(null) }
                        catch (_: ActivityNotFoundException) {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "signvoice/speech")
            .setMethodCallHandler { call, result ->
                if (call.method == "openVoiceSettings") result.success(openVoiceSettings())
                else result.notImplemented()
            }
        val tracker = NativeHandTracker(applicationContext)
        hands = tracker
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "signvoice/hands/events")
            .setStreamHandler(tracker)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "signvoice/hands")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> tracker.initialize(result)
                    "frame" -> {
                        @Suppress("UNCHECKED_CAST")
                        val frame = call.arguments as? Map<String, Any?>
                        if (frame == null) result.error("frame", "Missing frame", null)
                        else result.success(tracker.submit(frame))
                    }
                    "close" -> { tracker.stop(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openVoiceSettings(): Boolean {
        val engine = Settings.Secure.getString(contentResolver, "tts_default_synth")
        val install = Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA)
        if (!engine.isNullOrBlank()) install.setPackage(engine)
        for (intent in listOf(install, Intent("com.android.settings.TTS_SETTINGS"))) {
            try {
                startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
                // Some vendor engines provide settings but no installation activity.
            } catch (_: SecurityException) {
                // A vendor activity may be unavailable to third-party apps.
            }
        }
        return false
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        google?.close(); google = null
        hands?.close(); hands = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

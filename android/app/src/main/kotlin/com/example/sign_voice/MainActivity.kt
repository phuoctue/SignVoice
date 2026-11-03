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
    private var authLinks: MethodChannel? = null
    private var pendingResetRoute: String? = null

    private fun resetRoute(intent: Intent?): String? = if (intent?.action == Intent.ACTION_VIEW)
        PasswordResetLinks.route(intent.dataString, getString(R.string.signvoice_app_link_host)) else null

    override fun getInitialRoute(): String? = resetRoute(intent) ?: super.getInitialRoute()

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val route = resetRoute(intent) ?: return
        pendingResetRoute = route
        authLinks?.invokeMethod("open", route, object : MethodChannel.Result {
            override fun success(result: Any?) { if (pendingResetRoute == route) pendingResetRoute = null }
            override fun error(code: String, message: String?, details: Any?) {}
            override fun notImplemented() {}
        })
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        authLinks = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "signvoice/auth-links").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "takePending") {
                    val route = pendingResetRoute
                    pendingResetRoute = null
                    result.success(route)
                } else result.notImplemented()
            }
        }
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
        authLinks?.setMethodCallHandler(null); authLinks = null
        google?.close(); google = null
        hands?.close(); hands = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

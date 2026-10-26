package com.example.sign_voice

import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.Settings
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var hands: NativeHandTracker? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        hands?.close(); hands = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

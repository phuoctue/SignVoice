package com.example.sign_voice

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var hands: NativeHandTracker? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        hands?.close(); hands = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

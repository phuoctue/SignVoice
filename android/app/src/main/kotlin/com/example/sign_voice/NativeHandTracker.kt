package com.example.sign_voice

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Local measured joints never wait for JPEG, Wi-Fi, Python or word inference.
 * GPU creation/detection/disposal share one owner thread. Both queues keep latest.
 */
class NativeHandTracker(private val context: Context) : EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private val detectorThread = Executors.newSingleThreadExecutor()
    private val encoderThread = Executors.newSingleThreadExecutor()
    private val lock = Any()
    private var detector: HandLandmarker? = null
    @Volatile private var sink: EventChannel.EventSink? = null
    @Volatile private var active = false
    @Volatile private var generation = 0
    private var delegateName = "CPU"
    private var pending: Map<String, Any?>? = null
    private var detecting = false
    private var pendingJpeg: EncodeJob? = null
    private var encoding = false
    private var lastStamp = -1L
    private var lastEncodedStamp = -1000L
    private var pixelBuffer: IntArray? = null
    private val stamps = ArrayDeque<Long>()
    private val expectedHash = "fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1"
    private data class EncodeJob(val bitmap: Bitmap, val image: MPImage, val meta: Map<String, Any?>, val generation: Int)

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    fun initialize(result: MethodChannel.Result) {
        val token = ++generation
        active = false
        detectorThread.execute {
            try {
                detector?.close(); detector = null
                val bytes = context.assets.open("hand_landmarker.task").use { it.readBytes() }
                val hash = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
                check(hash == expectedHash) { "Hand model checksum mismatch" }
                fun create(delegate: Delegate): HandLandmarker {
                    val base = BaseOptions.builder().setModelAssetPath("hand_landmarker.task").setDelegate(delegate).build()
                    val options = HandLandmarker.HandLandmarkerOptions.builder()
                        .setBaseOptions(base).setRunningMode(RunningMode.VIDEO).setNumHands(2)
                        .setMinHandDetectionConfidence(0.15f).setMinHandPresenceConfidence(0.15f)
                        .setMinTrackingConfidence(0.22f).build()
                    return HandLandmarker.createFromOptions(context, options)
                }
                detector = try { create(Delegate.GPU).also { delegateName = "GPU" } }
                    catch (_: Exception) { create(Delegate.CPU).also { delegateName = "CPU" } }
                lastStamp = -1L; lastEncodedStamp = -1000L; stamps.clear()
                if (token != generation) { detector?.close(); detector = null }
                else active = true
                main.post { result.success(mapOf("ready" to active, "delegate" to delegateName,
                    "sdk" to "0.10.32", "model_sha256" to hash)) }
            } catch (error: Exception) {
                active = false
                main.post { result.error("hand_init", error.message, null) }
            }
        }
    }

    fun submit(frame: Map<String, Any?>): Boolean = synchronized(lock) {
        if (!active) return false
        pending = frame // at most one waiting raw frame; old references become collectible
        if (!detecting) {
            detecting = true
            val token = generation
            detectorThread.execute { drain(token) }
        }
        true
    }

    private fun drain(token: Int) {
        while (true) {
            val frame = synchronized(lock) {
                if (!active || token != generation) { pending = null; detecting = false; null }
                else pending.also { pending = null; if (it == null) detecting = false }
            } ?: return
            var bitmap: Bitmap? = null
            var image: MPImage? = null
            try {
                val stamp = (frame["timestamp_ms"] as Number).toLong()
                if (stamp <= lastStamp) continue
                lastStamp = stamp
                val begin = SystemClock.elapsedRealtimeNanos()
                val pixelCount = (frame["width"] as Number).toInt() * (frame["height"] as Number).toInt()
                require(pixelCount in 1..1920*1920)
                if (pixelBuffer?.size != pixelCount) pixelBuffer = IntArray(pixelCount)
                bitmap = bitmapFromFrame(frame, pixelBuffer)
                image = BitmapImageBuilder(bitmap).build()
                val found = detector!!.detectForVideo(image, stamp)
                val now = SystemClock.elapsedRealtimeNanos()
                stamps.addLast(now); if (stamps.size > 24) stamps.removeFirst()
                val fps = if (stamps.size > 1) 1e9 * (stamps.size - 1) / (now - stamps.first()) else 0.0
                val xyz = found.landmarks().map { hand -> hand.map { listOf(it.x(), it.y(), it.z()) } }
                require(found.handedness().size == xyz.size) { "Incomplete handedness result" }
                val categories = found.handedness().map {
                    it.firstOrNull()?.categoryName() ?: error("Missing measured handedness")
                }
                require(categories.all { it == "Left" || it == "Right" })
                val timing = (now - begin) / 1e6
                val meta = mapOf("format" to "jpeg", "width" to bitmap.width, "height" to bitmap.height,
                    "rotation" to 0, "timestamp_ms" to stamp, "processing_ms" to timing,
                    "hand_observation" to mapOf("schema" to "mediapipe_hand_3d_v1", "sdk" to "0.10.32",
                        "platform" to "android", "delegate" to delegateName.lowercase(), "model_sha256" to expectedHash,
                        "processing_ms" to timing, "fps" to fps,
                        "timestamp_ms" to stamp, "width" to bitmap.width, "height" to bitmap.height,
                        "landmarks" to xyz, "handedness" to categories))
                emit(mapOf("type" to "preview", "timestamp" to stamp,
                    "landmarks" to xyz.map { hand -> hand.map { it.take(2) } },
                    "fps" to fps, "processing_ms" to timing,
                    "hand_observation" to meta["hand_observation"],
                    "capture_source" to "android_${delegateName.lowercase()}"), token)
                // Local landmarks are emitted at detector speed. Only compress
                // frames the transport can accept, up to the model's 15 Hz input.
                if (frame["encode_frame"] != false && stamp - lastEncodedStamp >= 66L) {
                    lastEncodedStamp = stamp
                    queueJpeg(EncodeJob(bitmap, image, meta, token)); image = null; bitmap = null // encoder owns immutable pixels
                }
            } catch (error: Exception) {
                active = false
                emit(mapOf("type" to "unavailable", "reason" to (error.message ?: "Detector failed")), token)
            } finally {
                // MPImage owns its Bitmap and recycles it on close. The encoder
                // must finish before that close, otherwise JPEG sees dead pixels.
                if (image != null) image.close() else bitmap?.recycle()
            }
        }
    }

    private fun queueJpeg(job: EncodeJob) = synchronized(lock) {
        if (!active || job.generation != generation) { job.image.close(); return@synchronized }
        pendingJpeg?.image?.close(); pendingJpeg = job
        if (!encoding) { encoding = true; encoderThread.execute { encodeLatest() } }
    }
    private fun encodeLatest() {
        while (true) {
            val job = synchronized(lock) {
                pendingJpeg.also { pendingJpeg = null; if (it == null) encoding = false }
            } ?: return
            try {
                if (active && job.generation == generation) {
                    val begin = SystemClock.elapsedRealtimeNanos()
                    val bytes = ByteArrayOutputStream().use {
                        job.bitmap.compress(Bitmap.CompressFormat.JPEG, 78, it); it.toByteArray()
                    }
                    emit(mapOf("type" to "frame", "jpeg" to bytes,
                        "metadata" to job.meta + ("encode_ms" to (SystemClock.elapsedRealtimeNanos()-begin)/1e6)), job.generation)
                }
            } catch (error: Exception) {
                emit(mapOf("type" to "unavailable", "reason" to (error.message ?: "Encoder failed")), job.generation)
            } finally { job.image.close() }
        }
    }
    private fun emit(event: Map<String, Any?>, token: Int) {
        main.post { if (token == generation) sink?.success(event) }
    }
    fun stop() {
        active = false; generation++
        synchronized(lock) { pending = null; pendingJpeg?.image?.close(); pendingJpeg = null }
        detectorThread.execute { detector?.close(); detector = null; pixelBuffer = null }
    }
    fun close() { stop(); sink = null; detectorThread.shutdown(); encoderThread.shutdown() }

    companion object {
        @Suppress("UNCHECKED_CAST")
        internal fun bitmapFromFrame(frame: Map<String, Any?>, reuse: IntArray? = null): Bitmap {
            val width = (frame["width"] as Number).toInt()
            val height = (frame["height"] as Number).toInt()
            require(width in 1..1920 && height in 1..1920)
            val planes = frame["planes"] as List<Map<String, Any?>>
            val rotation=(frame["rotation"] as Number).toInt()
            require(rotation in listOf(0,90,180,270))
            // Fuse color conversion + sensor rotation into one output buffer.
            // Bitmap.createBitmap copies the array; the detector thread can
            // reuse it while the encoder still owns a previous immutable bitmap.
            val rgba = FramePixels.argb(width, height, frame["format"] as String, planes, rotation, reuse)
            val swap = rotation == 90 || rotation == 270
            return Bitmap.createBitmap(rgba,if (swap) height else width,if (swap) width else height,Bitmap.Config.ARGB_8888)
        }
    }
}

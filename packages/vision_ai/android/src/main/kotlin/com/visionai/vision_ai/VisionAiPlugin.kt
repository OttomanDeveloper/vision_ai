package com.visionai.vision_ai

import android.app.Activity
import android.os.Handler
import android.os.Looper
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.visionai.vision_ai.camera.CameraManager
import com.visionai.vision_ai.core.FrameProcessor
import com.visionai.vision_ai.core.ResultAggregator
import com.visionai.vision_ai.face.FaceDetectionProcessor
import com.visionai.vision_ai.hand.CustomGestureConfig
import com.visionai.vision_ai.hand.HandGestureProcessor
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import java.util.concurrent.Executors

// Single plugin entry point for both method calls (commands) and event channel (results).
// Threading model: all ML work runs on analysisExecutor (single background thread);
// results are posted back to mainHandler before reaching the Flutter event sink.
// analysisExecutor is a singleton for the plugin lifetime — processors are closed on it
// to avoid racing with in-flight inference when stopCamera/dispose is called.
class VisionAiPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    private lateinit var commandChannel: MethodChannel
    private lateinit var resultChannel: EventChannel
    private var textureRegistry: TextureRegistry? = null

    private val resultStreamHandler = ResultStreamHandler()
    private val mainHandler = Handler(Looper.getMainLooper()) // posts results to UI thread for EventSink
    private val analysisExecutor = Executors.newSingleThreadExecutor() // single thread keeps MediaPipe/ML Kit calls sequential

    private var cameraManager: CameraManager? = null
    private var frameProcessor: FrameProcessor? = null
    private var resultAggregator: ResultAggregator? = null
    private var handProcessor: HandGestureProcessor? = null
    private var faceProcessor: FaceDetectionProcessor? = null
    private var activity: Activity? = null
    private var lifecycleOwner: PluginLifecycleOwner? = null // synthetic owner; CameraX needs one even without a real Activity lifecycle

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        textureRegistry = binding.textureEntry()
        commandChannel = MethodChannel(binding.binaryMessenger, "com.visionai/commands")
        commandChannel.setMethodCallHandler(this)
        resultChannel = EventChannel(binding.binaryMessenger, "com.visionai/results")
        resultChannel.setStreamHandler(resultStreamHandler)
    }

    private fun FlutterPlugin.FlutterPluginBinding.textureEntry(): TextureRegistry {
        return this.textureRegistry
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startCamera" -> handleStartCamera(call, result)
            "stopCamera" -> handleStopCamera(result)
            "switchCamera" -> handleSwitchCamera(call, result)
            "updateHandConfig" -> handleUpdateHandConfig(call, result)
            "updateFaceConfig" -> handleUpdateFaceConfig(call, result)
            "dispose" -> handleDispose(result)
            else -> result.notImplemented()
        }
    }

    private fun handleStartCamera(call: MethodCall, result: Result) {
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "Plugin not attached to an activity", null)
            return
        }

        // Prevent double-start; Flutter can call this before the previous stream finishes tearing down
        if (cameraManager != null) {
            result.error("ALREADY_RUNNING", "Camera is already running. Call stopCamera first.", null)
            return
        }

        val facing = call.argument<Int>("cameraFacing") ?: 0   // 0=front, 1=back (matches CameraFacing.index)
        val resolution = call.argument<Int>("resolution") ?: 1 // maps to AnalysisResolution.index: 0=low,1=med,2=high
        val enableHand = call.argument<Boolean>("enableHand") ?: false
        val isFrontCamera = facing == 0 // passed to FrameProcessor to control mirror during rotation

        try {
            if (enableHand) {
                val maxHands = call.argument<Int>("maxHands") ?: 2
                val minDetection = call.argument<Double>("minDetectionConfidence")?.toFloat() ?: 0.5f
                val minPresence = call.argument<Double>("minPresenceConfidence")?.toFloat() ?: 0.5f
                val minTracking = call.argument<Double>("minTrackingConfidence")?.toFloat() ?: 0.5f
                val customGestureConfigs = parseCustomGestures(call)
                val gestureFilters = parseGestureFilters(call)

                handProcessor = HandGestureProcessor(act)
                handProcessor!!.initialize(
                    maxHands = maxHands,
                    minDetectionConfidence = minDetection,
                    minPresenceConfidence = minPresence,
                    minTrackingConfidence = minTracking,
                    customGestures = customGestureConfigs,
                    allowedGestures = gestureFilters.allowed,
                    deniedGestures = gestureFilters.denied,
                    gestureThresholds = gestureFilters.thresholds,
                )
            }

            val enableFace = call.argument<Boolean>("enableFace") ?: false
            if (enableFace) {
                val faceDetectEmotion = call.argument<Boolean>("detectEmotion") ?: true
                val faceDetectLandmarks = call.argument<Boolean>("detectLandmarks") ?: false
                val faceDetectContours = call.argument<Boolean>("detectContours") ?: false
                val faceMinSize = call.argument<Double>("minFaceSize")?.toFloat() ?: 0.1f // fraction of image width; smaller values are slower
                val faceEnableTracking = call.argument<Boolean>("enableFaceTracking") ?: true
                val faceMinEmotionConf = call.argument<Double>("minEmotionConfidence")?.toFloat() ?: 0.4f
                val faceAccurateMode = call.argument<Boolean>("accurateMode") ?: false

                faceProcessor = FaceDetectionProcessor(act)
                faceProcessor!!.initialize(
                    detectEmotion = faceDetectEmotion,
                    detectLandmarks = faceDetectLandmarks,
                    detectContours = faceDetectContours,
                    minFaceSize = faceMinSize,
                    enableTracking = faceEnableTracking,
                    minEmotionConfidence = faceMinEmotionConf,
                    accurateMode = faceAccurateMode,
                )
            }
        } catch (e: Exception) {
            // Partial init — clean up whatever did get created before surfacing the error
            handProcessor?.close()
            faceProcessor?.close()
            handProcessor = null
            faceProcessor = null
            result.error("INIT_ERROR", "Failed to initialize ML models: ${e.message}", e.stackTraceToString())
            return
        }

        val maxResults = call.argument<Int>("maxResultsPerSecond") ?: 0 // 0 = no throttle, pass every frame
        resultAggregator = ResultAggregator(mainHandler, { resultStreamHandler.eventSink }, maxResults)
        frameProcessor = FrameProcessor(
            resultAggregator = resultAggregator!!,
            handProcessor = handProcessor,
            faceProcessor = faceProcessor,
            isFrontCamera = isFrontCamera,
        )

        val owner = PluginLifecycleOwner()
        lifecycleOwner = owner

        cameraManager = CameraManager(
            context = act,
            textureRegistry = textureRegistry!!,
            analysisExecutor = analysisExecutor,
            lifecycleOwner = owner,
        )

        try {
            val textureId = cameraManager!!.start(
                facing = facing,
                resolution = resolution,
                frameProcessor = frameProcessor!!,
            )
            // Drive the lifecycle to RESUMED so CameraX starts delivering frames
            owner.handleLifecycleEvent(Lifecycle.Event.ON_START)
            owner.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)
            result.success(textureId) // Flutter Texture widget uses this id to render the preview
        } catch (e: Exception) {
            cameraManager?.release()
            handProcessor?.close()
            faceProcessor?.close()
            cameraManager = null
            frameProcessor = null
            resultAggregator = null
            handProcessor = null
            faceProcessor = null
            lifecycleOwner = null
            result.error("CAMERA_ERROR", "Failed to start camera: ${e.message}", e.stackTraceToString())
        }
    }

    private fun handleStopCamera(result: Result) {
        // Pause/stop lifecycle before unbinding to let CameraX flush in-flight frames cleanly
        lifecycleOwner?.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE)
        lifecycleOwner?.handleLifecycleEvent(Lifecycle.Event.ON_STOP)
        cameraManager?.release()
        // Capture references before nulling so the executor closure captures live objects
        val hp = handProcessor
        val fp = faceProcessor
        val pool = frameProcessor?.bitmapPool
        cameraManager = null
        frameProcessor = null
        resultAggregator = null
        handProcessor = null
        faceProcessor = null
        lifecycleOwner = null
        // Close ML resources on the analysis thread to avoid racing with any queued frame
        analysisExecutor.execute {
            hp?.close()
            fp?.close()
            pool?.release()
        }
        result.success(null)
    }

    private fun handleSwitchCamera(call: MethodCall, result: Result) {
        val facing = call.argument<Int>("facing") ?: 0
        cameraManager?.switchCamera(facing)
        result.success(null)
    }

    private fun handleUpdateHandConfig(call: MethodCall, result: Result) {
        val act = activity
        // No-op if hand detection was not enabled at startup
        if (act == null || handProcessor == null) {
            result.success(null)
            return
        }

        val maxHands = call.argument<Int>("maxHands") ?: 2
        val minDetection = call.argument<Double>("minDetectionConfidence")?.toFloat() ?: 0.5f
        val minPresence = call.argument<Double>("minPresenceConfidence")?.toFloat() ?: 0.5f
        val minTracking = call.argument<Double>("minTrackingConfidence")?.toFloat() ?: 0.5f
        val customGestureConfigs = parseCustomGestures(call)
        val gestureFilters = parseGestureFilters(call)

        // initialize() closes and recreates the recognizer — briefly drops a frame
        handProcessor!!.initialize(
            maxHands = maxHands,
            minDetectionConfidence = minDetection,
            minPresenceConfidence = minPresence,
            minTrackingConfidence = minTracking,
            customGestures = customGestureConfigs,
            allowedGestures = gestureFilters.allowed,
            deniedGestures = gestureFilters.denied,
            gestureThresholds = gestureFilters.thresholds,
        )
        result.success(null)
    }

    private fun handleUpdateFaceConfig(call: MethodCall, result: Result) {
        val act = activity
        // No-op if face detection was not enabled at startup
        if (act == null || faceProcessor == null) {
            result.success(null)
            return
        }

        val detectEmotion = call.argument<Boolean>("detectEmotion") ?: true
        val detectContours = call.argument<Boolean>("detectContours") ?: false
        val minFaceSize = call.argument<Double>("minFaceSize")?.toFloat() ?: 0.1f
        val enableTracking = call.argument<Boolean>("enableFaceTracking") ?: true
        val minEmotionConf = call.argument<Double>("minEmotionConfidence")?.toFloat() ?: 0.4f
        val accurateMode = call.argument<Boolean>("accurateMode") ?: false

        faceProcessor!!.initialize(
            detectEmotion = detectEmotion,
            detectContours = detectContours,
            minFaceSize = minFaceSize,
            enableTracking = enableTracking,
            minEmotionConfidence = minEmotionConf,
            accurateMode = accurateMode,
        )
        result.success(null)
    }

    @Suppress("UNCHECKED_CAST")
    private fun parseCustomGestures(call: MethodCall): List<CustomGestureConfig> {
        val rawList = call.argument<List<Map<String, Any>>>("customGestures") ?: return emptyList()
        return rawList.mapNotNull { map ->
            val name = map["name"] as? String ?: return@mapNotNull null
            val states = map["fingerStates"] as? List<Int> ?: return@mapNotNull null
            if (states.size != 5) return@mapNotNull null // must have exactly one state per finger
            CustomGestureConfig(name, states.toIntArray())
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun parseGestureFilters(call: MethodCall): GestureFilterConfig {
        val allowed = call.argument<List<String>>("allowedGestures")?.toSet()
        val denied = call.argument<List<String>>("deniedGestures")?.toSet()
        val rawThresholds = call.argument<Map<String, Any>>("gestureThresholds")
        val thresholds = rawThresholds?.mapValues { (it.value as Number).toFloat() }
        return GestureFilterConfig(
            allowed = allowed?.ifEmpty { null },  // empty set is treated as "no filter" to avoid blocking all gestures
            denied = denied?.ifEmpty { null },
            thresholds = thresholds?.ifEmpty { null },
        )
    }

    private fun handleDispose(result: Result) {
        lifecycleOwner?.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
        cameraManager?.release()
        val hp = handProcessor
        val fp = faceProcessor
        val pool = frameProcessor?.bitmapPool
        cameraManager = null
        frameProcessor = null
        resultAggregator = null
        handProcessor = null
        faceProcessor = null
        lifecycleOwner = null
        analysisExecutor.execute {
            hp?.close()
            fp?.close()
            pool?.release()
        }
        result.success(null)
    }

    // ActivityAware
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null // camera keeps running; activity ref is not used during streaming
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        commandChannel.setMethodCallHandler(null)
        resultChannel.setStreamHandler(null)
        cameraManager?.release()
        handProcessor?.close()
        faceProcessor?.close()
        analysisExecutor.shutdown() // does not cancel in-flight tasks, just stops accepting new ones
    }
}

// Holds the active EventSink so ResultAggregator can post to it via a lambda, avoiding a hard reference
class ResultStreamHandler : EventChannel.StreamHandler {
    var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}

// Synthetic LifecycleOwner because the plugin doesn't have a Fragment/Activity to borrow from.
// CameraX requires a LifecycleOwner to manage camera bind/unbind automatically.
class PluginLifecycleOwner : LifecycleOwner {
    private val lifecycleRegistry = LifecycleRegistry(this)

    override val lifecycle: Lifecycle
        get() = lifecycleRegistry

    // Caller must drive transitions in order (ON_CREATE → ON_START → ON_RESUME → …)
    fun handleLifecycleEvent(event: Lifecycle.Event) {
        lifecycleRegistry.handleLifecycleEvent(event)
    }
}

// Immutable snapshot of filter settings parsed from a single method call; null = no filter applied
data class GestureFilterConfig(
    val allowed: Set<String>?,  // only these gestures pass through; null = allow all
    val denied: Set<String>?,   // these gestures are suppressed; null = deny none
    val thresholds: Map<String, Float>?, // per-gesture minimum confidence, range [0.0, 1.0]
)

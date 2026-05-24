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

class VisionAiPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    private lateinit var commandChannel: MethodChannel
    private lateinit var resultChannel: EventChannel
    private var textureRegistry: TextureRegistry? = null

    private val resultStreamHandler = ResultStreamHandler()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val analysisExecutor = Executors.newSingleThreadExecutor()

    private var cameraManager: CameraManager? = null
    private var frameProcessor: FrameProcessor? = null
    private var resultAggregator: ResultAggregator? = null
    private var activity: Activity? = null
    private var lifecycleOwner: PluginLifecycleOwner? = null

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
            "updateHandConfig" -> result.success(null) // Phase 2
            "updateFaceConfig" -> result.success(null) // Phase 4
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

        val facing = call.argument<Int>("cameraFacing") ?: 0
        val resolution = call.argument<Int>("resolution") ?: 1

        resultAggregator = ResultAggregator(mainHandler) { resultStreamHandler.eventSink }
        frameProcessor = FrameProcessor(resultAggregator!!)

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
            owner.handleLifecycleEvent(Lifecycle.Event.ON_START)
            owner.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)
            result.success(textureId)
        } catch (e: Exception) {
            result.error("CAMERA_ERROR", e.message, null)
        }
    }

    private fun handleStopCamera(result: Result) {
        lifecycleOwner?.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE)
        lifecycleOwner?.handleLifecycleEvent(Lifecycle.Event.ON_STOP)
        cameraManager?.stop()
        result.success(null)
    }

    private fun handleSwitchCamera(call: MethodCall, result: Result) {
        val facing = call.argument<Int>("facing") ?: 0
        cameraManager?.switchCamera(facing)
        result.success(null)
    }

    private fun handleDispose(result: Result) {
        lifecycleOwner?.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
        cameraManager?.release()
        cameraManager = null
        frameProcessor = null
        resultAggregator = null
        lifecycleOwner = null
        result.success(null)
    }

    // ActivityAware
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
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
        analysisExecutor.shutdown()
    }
}

class ResultStreamHandler : EventChannel.StreamHandler {
    var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}

class PluginLifecycleOwner : LifecycleOwner {
    private val lifecycleRegistry = LifecycleRegistry(this)

    override val lifecycle: Lifecycle
        get() = lifecycleRegistry

    fun handleLifecycleEvent(event: Lifecycle.Event) {
        lifecycleRegistry.handleLifecycleEvent(event)
    }
}

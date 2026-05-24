package com.visionai.vision_ai.hand

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizer
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizerResult

// MediaPipe GestureRecognizer runs in LIVE_STREAM mode: recognizeAsync() is non-blocking and
// delivers results via the result listener on an internal MediaPipe thread. getLatestResult()
// is called from the analysis thread each frame to pick up whatever arrived since the last call.
// GPU delegate is attempted first; if the device doesn't support it (e.g. some emulators),
// we silently fall back to CPU so initialization doesn't blow up in the caller's face.
class HandGestureProcessor(private val context: Context) {

    private var gestureRecognizer: GestureRecognizer? = null
    private var customClassifier: CustomGestureClassifier? = null

    @Volatile
    private var latestResult: HandProcessorResult? = null

    fun initialize(
        maxHands: Int = 2,
        minDetectionConfidence: Float = 0.5f,
        minPresenceConfidence: Float = 0.5f,
        minTrackingConfidence: Float = 0.5f,
        customGestures: List<CustomGestureConfig> = emptyList(),
    ) {
        close()

        val baseOptions = try {
            BaseOptions.builder()
                .setModelAssetPath("gesture_recognizer.task")
                .setDelegate(Delegate.GPU)
                .build()
        } catch (e: Exception) {
            Log.w(TAG, "GPU delegate failed, falling back to CPU", e)
            BaseOptions.builder()
                .setModelAssetPath("gesture_recognizer.task")
                .setDelegate(Delegate.CPU)
                .build()
        }

        val options = GestureRecognizer.GestureRecognizerOptions.builder()
            .setBaseOptions(baseOptions)
            .setNumHands(maxHands)
            .setMinHandDetectionConfidence(minDetectionConfidence)
            .setMinHandPresenceConfidence(minPresenceConfidence)
            .setMinTrackingConfidence(minTrackingConfidence)
            .setRunningMode(RunningMode.LIVE_STREAM)
            .setResultListener { result, _ -> onResult(result) }
            .setErrorListener { e -> Log.e(TAG, "MediaPipe error: ${e.message}") }
            .build()

        gestureRecognizer = GestureRecognizer.createFromOptions(context, options)
        customClassifier = CustomGestureClassifier(customGestures)
    }

    fun processFrame(bitmap: Bitmap, timestampMs: Long) {
        val mpImage = BitmapImageBuilder(bitmap).build()
        gestureRecognizer?.recognizeAsync(mpImage, timestampMs)
    }

    fun getLatestResult(): HandProcessorResult? {
        val result = latestResult
        latestResult = null
        return result
    }

    private fun onResult(result: GestureRecognizerResult) {
        if (result.landmarks().isEmpty()) {
            latestResult = HandProcessorResult(emptyList())
            return
        }

        val hands = mutableListOf<SingleHandResult>()

        for (i in result.landmarks().indices) {
            val landmarks = result.landmarks()[i]
            val worldLandmarks = result.worldLandmarks()[i]
            val handedness = result.handednesses()[i]

            val gestures = result.gestures()
            var gestureName = if (i < gestures.size && gestures[i].isNotEmpty()) {
                gestures[i][0].categoryName() ?: "None"
            } else {
                "None"
            }
            var gestureScore = if (i < gestures.size && gestures[i].isNotEmpty()) {
                gestures[i][0].score().toDouble()
            } else {
                0.0
            }
            var customGestureName: String? = null

            val isLeft = handedness.isNotEmpty() &&
                    handedness[0].categoryName().equals("Left", ignoreCase = true)
            val handednessScore = if (handedness.isNotEmpty()) handedness[0].score() else 0f

            val fingerStates = computeFingerStates(landmarks, isLeft)

            // When MediaPipe doesn't recognize a built-in gesture, try custom classification
            if (gestureName == "None" && customClassifier != null) {
                val customMatch = customClassifier!!.classify(landmarks, fingerStates, isLeft)
                if (customMatch != null) {
                    gestureName = customMatch.gestureName
                    gestureScore = customMatch.confidence
                    // If it's a user-defined custom gesture (not ok/counting), set customGestureName
                    if (gestureName !in BUILT_IN_CUSTOM_NAMES) {
                        customGestureName = gestureName
                    }
                }
            }

            val normalizedLandmarks = DoubleArray(63)
            for (j in landmarks.indices) {
                normalizedLandmarks[j * 3] = landmarks[j].x().toDouble()
                normalizedLandmarks[j * 3 + 1] = landmarks[j].y().toDouble()
                normalizedLandmarks[j * 3 + 2] = landmarks[j].z().toDouble()
            }

            val worldLandmarkArray = DoubleArray(63)
            for (j in worldLandmarks.indices) {
                worldLandmarkArray[j * 3] = worldLandmarks[j].x().toDouble()
                worldLandmarkArray[j * 3 + 1] = worldLandmarks[j].y().toDouble()
                worldLandmarkArray[j * 3 + 2] = worldLandmarks[j].z().toDouble()
            }

            hands.add(
                SingleHandResult(
                    gestureName = gestureName,
                    gestureConfidence = gestureScore,
                    customGestureName = customGestureName,
                    landmarks = normalizedLandmarks,
                    worldLandmarks = worldLandmarkArray,
                    isLeftHand = isLeft,
                    handednessConfidence = handednessScore.toDouble(),
                    fingerStates = fingerStates,
                )
            )
        }

        latestResult = HandProcessorResult(hands)
    }

    private fun computeFingerStates(
        landmarks: List<com.google.mediapipe.tasks.components.containers.NormalizedLandmark>,
        isLeft: Boolean,
    ): IntArray {
        val states = IntArray(5)

        val thumbTip = landmarks[4]
        val thumbIp = landmarks[3]
        states[0] = if (isLeft) {
            if (thumbTip.x() > thumbIp.x()) 1 else 0
        } else {
            if (thumbTip.x() < thumbIp.x()) 1 else 0
        }

        states[1] = if (landmarks[8].y() < landmarks[6].y()) 1 else 0
        states[2] = if (landmarks[12].y() < landmarks[10].y()) 1 else 0
        states[3] = if (landmarks[16].y() < landmarks[14].y()) 1 else 0
        states[4] = if (landmarks[20].y() < landmarks[18].y()) 1 else 0

        return states
    }

    fun close() {
        gestureRecognizer?.close()
        gestureRecognizer = null
        customClassifier = null
        latestResult = null
    }

    companion object {
        private const val TAG = "HandGestureProcessor"
        private val BUILT_IN_CUSTOM_NAMES = setOf("ok", "one", "two", "three", "four", "five")
    }
}

data class SingleHandResult(
    val gestureName: String,
    val gestureConfidence: Double,
    val customGestureName: String?,
    val landmarks: DoubleArray,
    val worldLandmarks: DoubleArray,
    val isLeftHand: Boolean,
    val handednessConfidence: Double,
    val fingerStates: IntArray,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "gesture" to gestureName,
        "gestureConfidence" to gestureConfidence,
        "customGestureName" to customGestureName,
        "landmarks" to landmarks,
        "worldLandmarks" to worldLandmarks,
        "isLeftHand" to isLeftHand,
        "handednessConfidence" to handednessConfidence,
        "fingerStates" to fingerStates.toList(),
    )
}

data class HandProcessorResult(val hands: List<SingleHandResult>) {
    fun toMapList(): List<Map<String, Any?>> = hands.map { it.toMap() }
}

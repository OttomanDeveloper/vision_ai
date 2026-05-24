package com.visionai.vision_ai.hand

import android.content.Context
import android.graphics.Bitmap
import android.os.SystemClock
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizer
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizerResult

class HandGestureProcessor(private val context: Context) {

    private var gestureRecognizer: GestureRecognizer? = null

    @Volatile
    private var latestResult: HandProcessorResult? = null

    fun initialize(
        maxHands: Int = 2,
        minDetectionConfidence: Float = 0.5f,
        minPresenceConfidence: Float = 0.5f,
        minTrackingConfidence: Float = 0.5f,
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
            val gestureName = if (i < gestures.size && gestures[i].isNotEmpty()) {
                gestures[i][0].categoryName() ?: "None"
            } else {
                "None"
            }
            val gestureScore = if (i < gestures.size && gestures[i].isNotEmpty()) {
                gestures[i][0].score()
            } else {
                0f
            }

            val isLeft = handedness.isNotEmpty() &&
                    handedness[0].categoryName().equals("Left", ignoreCase = true)
            val handednessScore = if (handedness.isNotEmpty()) handedness[0].score() else 0f

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

            val fingerStates = computeFingerStates(landmarks, isLeft)

            hands.add(
                SingleHandResult(
                    gestureName = gestureName,
                    gestureConfidence = gestureScore.toDouble(),
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

        // Thumb: compare tip.x vs ip.x relative to hand orientation
        val thumbTip = landmarks[4]
        val thumbIp = landmarks[3]
        states[0] = if (isLeft) {
            if (thumbTip.x() > thumbIp.x()) 1 else 0
        } else {
            if (thumbTip.x() < thumbIp.x()) 1 else 0
        }

        // Index: tip above PIP (lower y = higher in image)
        states[1] = if (landmarks[8].y() < landmarks[6].y()) 1 else 0

        // Middle
        states[2] = if (landmarks[12].y() < landmarks[10].y()) 1 else 0

        // Ring
        states[3] = if (landmarks[16].y() < landmarks[14].y()) 1 else 0

        // Pinky
        states[4] = if (landmarks[20].y() < landmarks[18].y()) 1 else 0

        return states // 1 = extended, 0 = closed
    }

    fun close() {
        gestureRecognizer?.close()
        gestureRecognizer = null
        latestResult = null
    }

    companion object {
        private const val TAG = "HandGestureProcessor"
    }
}

data class SingleHandResult(
    val gestureName: String,
    val gestureConfidence: Double,
    val landmarks: DoubleArray,
    val worldLandmarks: DoubleArray,
    val isLeftHand: Boolean,
    val handednessConfidence: Double,
    val fingerStates: IntArray,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "gesture" to gestureName,
        "gestureConfidence" to gestureConfidence,
        "customGestureName" to null,
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

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
    private var allowedGestures: Set<String>? = null // null means no allowlist (pass everything)
    private var deniedGestures: Set<String>? = null  // null means no denylist
    private var gestureThresholds: Map<String, Float>? = null // per-gesture minimum confidence, [0.0,1.0]

    @Volatile
    private var latestResult: HandProcessorResult? = null // written by MediaPipe thread, read by analysis thread

    fun initialize(
        maxHands: Int = 2,
        minDetectionConfidence: Float = 0.5f,   // [0.0, 1.0]; lower = more false positives
        minPresenceConfidence: Float = 0.5f,    // [0.0, 1.0]; guards against tracking ghosts
        minTrackingConfidence: Float = 0.5f,    // [0.0, 1.0]; below this, re-detection runs
        customGestures: List<CustomGestureConfig> = emptyList(),
        allowedGestures: Set<String>? = null,
        deniedGestures: Set<String>? = null,
        gestureThresholds: Map<String, Float>? = null,
    ) {
        close() // always tear down the old recognizer before rebuilding to free GPU resources

        this.allowedGestures = allowedGestures
        this.deniedGestures = deniedGestures
        this.gestureThresholds = gestureThresholds

        val baseOptions = try {
            BaseOptions.builder()
                .setModelAssetPath("gesture_recognizer.task") // bundled in assets/
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
            .setRunningMode(RunningMode.LIVE_STREAM) // non-blocking; result arrives on a MediaPipe-internal thread
            .setResultListener { result, _ -> onResult(result) }
            .setErrorListener { e -> Log.e(TAG, "MediaPipe error: ${e.message}") }
            .build()

        gestureRecognizer = GestureRecognizer.createFromOptions(context, options)
        customClassifier = CustomGestureClassifier(customGestures)
    }

    // Non-blocking; MediaPipe queues the frame and calls onResult() asynchronously
    fun processFrame(bitmap: Bitmap, timestampMs: Long) {
        val mpImage = BitmapImageBuilder(bitmap).build()
        gestureRecognizer?.recognizeAsync(mpImage, timestampMs)
    }

    // Consumes and returns the most recent result; returns null if MediaPipe hasn't responded yet for this frame
    fun getLatestResult(): HandProcessorResult? {
        val result = latestResult
        latestResult = null // clear so the next call doesn't return a stale result
        return result
    }

    // Called on a MediaPipe-internal thread; only writes latestResult (volatile), never reads UI state
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

            // Per-gesture filtering: allow/deny lists and per-gesture thresholds.
            // Filtered gestures become "None" so custom gesture fallback still runs.
            if (gestureName != "None") {
                val allowed = allowedGestures
                val denied = deniedGestures
                val thresholds = gestureThresholds
                if (allowed != null && gestureName !in allowed) {
                    gestureName = "None"
                    gestureScore = 0.0
                } else if (denied != null && gestureName in denied) {
                    gestureName = "None"
                    gestureScore = 0.0
                } else if (thresholds != null && thresholds.containsKey(gestureName)) {
                    if (gestureScore < thresholds[gestureName]!!) {
                        gestureName = "None"
                        gestureScore = 0.0
                    }
                }
            }

            // MediaPipe labels from the camera's perspective; front camera "Left" == user's right hand
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
                    // customGestureName distinguishes user-defined gestures from built-in "custom" ones (ok, counting)
                    if (gestureName !in BUILT_IN_CUSTOM_NAMES) {
                        customGestureName = gestureName
                    }
                }
            }

            // Flattened to a DoubleArray for efficient Flutter codec serialization (63 = 21 landmarks × 3 axes)
            val normalizedLandmarks = DoubleArray(63)
            for (j in landmarks.indices) {
                normalizedLandmarks[j * 3] = landmarks[j].x().toDouble()     // normalized [0,1] relative to image width
                normalizedLandmarks[j * 3 + 1] = landmarks[j].y().toDouble() // normalized [0,1] relative to image height
                normalizedLandmarks[j * 3 + 2] = landmarks[j].z().toDouble() // depth relative to wrist; negative = closer to camera
            }

            // World landmarks are in metric space (meters) relative to the hand's geometric center
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

    // Returns IntArray[5]: [thumb, index, middle, ring, pinky], 1=extended 0=closed.
    // Thumb uses X-axis because it extends sideways; other fingers use Y-axis (tip above pip = extended).
    // isLeft flips the thumb X comparison because the hand is mirrored.
    private fun computeFingerStates(
        landmarks: List<com.google.mediapipe.tasks.components.containers.NormalizedLandmark>,
        isLeft: Boolean,
    ): IntArray {
        val states = IntArray(5)

        val thumbTip = landmarks[4]  // landmark index 4 = thumb tip
        val thumbIp = landmarks[3]   // landmark index 3 = thumb IP joint (one below tip)
        // Left hand: thumb extended when tip X > IP X (extends rightward in image space)
        states[0] = if (isLeft) {
            if (thumbTip.x() > thumbIp.x()) 1 else 0
        } else {
            if (thumbTip.x() < thumbIp.x()) 1 else 0
        }

        // Finger tip landmark indices: 8=index, 12=middle, 16=ring, 20=pinky
        // PIP joint indices (knuckle): 6=index, 10=middle, 14=ring, 18=pinky
        // Lower Y = higher on screen = finger extended upward
        states[1] = if (landmarks[8].y() < landmarks[6].y()) 1 else 0
        states[2] = if (landmarks[12].y() < landmarks[10].y()) 1 else 0
        states[3] = if (landmarks[16].y() < landmarks[14].y()) 1 else 0
        states[4] = if (landmarks[20].y() < landmarks[18].y()) 1 else 0

        return states
    }

    // Safe to call multiple times; also called by initialize() to reset before rebuilding
    fun close() {
        gestureRecognizer?.close()
        gestureRecognizer = null
        customClassifier = null
        latestResult = null
    }

    companion object {
        private const val TAG = "HandGestureProcessor"
        // These names are produced by CustomGestureClassifier but are not user-defined, so customGestureName stays null for them
        private val BUILT_IN_CUSTOM_NAMES = setOf("ok", "one", "two", "three", "four", "five")
    }
}

data class SingleHandResult(
    val gestureName: String,
    val gestureConfidence: Double,   // [0.0, 1.0]
    val customGestureName: String?,  // non-null only for user-defined custom gestures
    val landmarks: DoubleArray,      // 63 doubles: [x0,y0,z0, x1,y1,z1, ...] normalized image coords
    val worldLandmarks: DoubleArray, // 63 doubles: metric coords relative to hand center
    val isLeftHand: Boolean,         // from camera's perspective; not necessarily the user's left
    val handednessConfidence: Double, // [0.0, 1.0]; low values mean ambiguous hand orientation
    val fingerStates: IntArray,       // [thumb, index, middle, ring, pinky], 1=extended 0=closed
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

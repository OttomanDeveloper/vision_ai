package com.visionai.vision_ai.hand

import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import kotlin.math.sqrt

// Classification priority: ok → counting gestures → user-defined customs.
// ok and counting gestures only fire when MediaPipe returns "None", so they fill gaps in the
// built-in recognizer without conflicting with it.
// Finger state convention: 1 = extended, 0 = closed, -1 = any (wildcard in custom configs).
// Thumb extension is determined by X position (left vs right hand), not Y, because the thumb
// extends sideways rather than upward.
class CustomGestureClassifier(
    private val customGestures: List<CustomGestureConfig> = emptyList(),
) {
    fun classify(
        landmarks: List<NormalizedLandmark>,
        fingerStates: IntArray,
        isLeftHand: Boolean,
    ): GestureMatch? {
        val okResult = detectOkGesture(landmarks, fingerStates)
        if (okResult != null) return okResult

        val countResult = detectCountingGesture(fingerStates)
        if (countResult != null) return countResult

        val customResult = detectCustomGesture(fingerStates)
        if (customResult != null) return customResult

        return null
    }

    private fun detectOkGesture(
        landmarks: List<NormalizedLandmark>,
        fingerStates: IntArray,
    ): GestureMatch? {
        if (landmarks.size < 21) return null

        val thumbTip = landmarks[4]
        val indexTip = landmarks[8]

        val dx = (thumbTip.x() - indexTip.x()).toDouble()
        val dy = (thumbTip.y() - indexTip.y()).toDouble()
        val distance = sqrt(dx * dx + dy * dy)

        val threshold = 0.06

        // Thumb tip and index tip must be close together
        // Middle, ring, pinky should be extended
        if (distance < threshold &&
            fingerStates[2] == 1 && // middle extended
            fingerStates[3] == 1 && // ring extended
            fingerStates[4] == 1    // pinky extended
        ) {
            val confidence = (1.0 - (distance / threshold)).coerceIn(0.5, 1.0)
            return GestureMatch("ok", confidence)
        }

        return null
    }

    private fun detectCountingGesture(fingerStates: IntArray): GestureMatch? {
        if (fingerStates.size < 5) return null

        val thumb = fingerStates[0] == 1
        val index = fingerStates[1] == 1
        val middle = fingerStates[2] == 1
        val ring = fingerStates[3] == 1
        val pinky = fingerStates[4] == 1

        // ONE: only index extended, all others (including thumb) closed
        if (index && !middle && !ring && !pinky && !thumb) {
            return GestureMatch("one", 0.85)
        }

        // TWO: index + middle only
        if (index && middle && !ring && !pinky && !thumb) {
            return GestureMatch("two", 0.85)
        }

        // THREE: index + middle + ring (no thumb, no pinky)
        if (index && middle && ring && !pinky && !thumb) {
            return GestureMatch("three", 0.85)
        }

        // FOUR: all except thumb
        if (index && middle && ring && pinky && !thumb) {
            return GestureMatch("four", 0.85)
        }

        // FIVE: all extended — MediaPipe should already catch this as Open_Palm
        // but as a fallback:
        if (thumb && index && middle && ring && pinky) {
            return GestureMatch("five", 0.80)
        }

        return null
    }

    private fun detectCustomGesture(fingerStates: IntArray): GestureMatch? {
        if (fingerStates.size < 5) return null

        for (gesture in customGestures) {
            var matches = true
            var matchedCount = 0
            var totalRequired = 0

            for (i in 0 until 5) {
                val required = gesture.fingerStates[i]
                if (required < 0) continue // -1 means "any state", skip

                totalRequired++
                val actual = fingerStates[i]
                if (required == actual) {
                    matchedCount++
                } else {
                    matches = false
                    break
                }
            }

            if (matches && totalRequired > 0) {
                val confidence = matchedCount.toDouble() / 5.0
                return GestureMatch(gesture.name, confidence.coerceIn(0.5, 1.0))
            }
        }

        return null
    }
}

data class CustomGestureConfig(
    val name: String,
    // [thumb, index, middle, ring, pinky]
    // 0 = closed, 1 = extended, -1 = any
    val fingerStates: IntArray,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is CustomGestureConfig) return false
        return name == other.name && fingerStates.contentEquals(other.fingerStates)
    }

    override fun hashCode(): Int {
        var result = name.hashCode()
        result = 31 * result + fingerStates.contentHashCode()
        return result
    }
}

data class GestureMatch(
    val gestureName: String,
    val confidence: Double,
)

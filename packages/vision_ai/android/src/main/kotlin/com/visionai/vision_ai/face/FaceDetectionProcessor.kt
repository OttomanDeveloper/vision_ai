package com.visionai.vision_ai.face

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.android.gms.tasks.Tasks

class FaceDetectionProcessor(private val context: Context) {

    private var faceDetector: FaceDetector? = null
    private var emotionClassifier: EmotionClassifier? = null
    private var detectEmotion = true
    private var minEmotionConfidence = 0.4f

    fun initialize(
        detectEmotion: Boolean = true,
        minFaceSize: Float = 0.1f,
        enableTracking: Boolean = true,
        minEmotionConfidence: Float = 0.4f,
    ) {
        close()

        this.detectEmotion = detectEmotion
        this.minEmotionConfidence = minEmotionConfidence

        val optionsBuilder = FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .setMinFaceSize(minFaceSize)

        if (enableTracking) {
            optionsBuilder.enableTracking()
        }

        faceDetector = FaceDetection.getClient(optionsBuilder.build())

        if (detectEmotion) {
            emotionClassifier = EmotionClassifier(context)
            emotionClassifier!!.initialize()
        }
    }

    fun processFrame(bitmap: Bitmap, rotationDegrees: Int): FaceProcessorResult {
        val detector = faceDetector ?: return FaceProcessorResult.empty()

        val inputImage = InputImage.fromBitmap(bitmap, 0)

        val faces: List<Face> = try {
            Tasks.await(detector.process(inputImage))
        } catch (e: Exception) {
            Log.e(TAG, "Face detection failed", e)
            return FaceProcessorResult.empty()
        }

        if (faces.isEmpty()) return FaceProcessorResult.empty()

        val results = mutableListOf<SingleFaceResult>()

        for (face in faces) {
            var emotionResult = EmotionResult.none()

            if (detectEmotion && emotionClassifier != null) {
                val croppedFace = cropFace(bitmap, face.boundingBox)
                if (croppedFace != null) {
                    emotionResult = emotionClassifier!!.classify(croppedFace)
                    croppedFace.recycle()
                }
            }

            results.add(
                SingleFaceResult(
                    emotion = emotionResult.primaryEmotion,
                    emotionConfidence = emotionResult.confidence,
                    emotionScores = emotionResult.scores,
                    boundingBox = face.boundingBox,
                    headEulerAngleX = (face.headEulerAngleX).toDouble(),
                    headEulerAngleY = (face.headEulerAngleY).toDouble(),
                    headEulerAngleZ = (face.headEulerAngleZ).toDouble(),
                    smilingProbability = face.smilingProbability?.toDouble(),
                    leftEyeOpenProbability = face.leftEyeOpenProbability?.toDouble(),
                    rightEyeOpenProbability = face.rightEyeOpenProbability?.toDouble(),
                    trackingId = face.trackingId ?: -1,
                )
            )
        }

        return FaceProcessorResult(results)
    }

    private fun cropFace(bitmap: Bitmap, bbox: Rect): Bitmap? {
        // Expand bounding box by 20% on each side
        val padX = (bbox.width() * 0.2).toInt()
        val padY = (bbox.height() * 0.2).toInt()

        val left = (bbox.left - padX).coerceAtLeast(0)
        val top = (bbox.top - padY).coerceAtLeast(0)
        val right = (bbox.right + padX).coerceAtMost(bitmap.width)
        val bottom = (bbox.bottom + padY).coerceAtMost(bitmap.height)

        val width = right - left
        val height = bottom - top

        if (width <= 0 || height <= 0) return null

        return try {
            Bitmap.createBitmap(bitmap, left, top, width, height)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to crop face", e)
            null
        }
    }

    fun close() {
        faceDetector?.close()
        emotionClassifier?.close()
        faceDetector = null
        emotionClassifier = null
    }

    companion object {
        private const val TAG = "FaceDetectionProcessor"
    }
}

data class SingleFaceResult(
    val emotion: String,
    val emotionConfidence: Double,
    val emotionScores: DoubleArray,
    val boundingBox: Rect,
    val headEulerAngleX: Double,
    val headEulerAngleY: Double,
    val headEulerAngleZ: Double,
    val smilingProbability: Double?,
    val leftEyeOpenProbability: Double?,
    val rightEyeOpenProbability: Double?,
    val trackingId: Int,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "emotion" to emotion,
        "emotionConfidence" to emotionConfidence,
        "emotionScores" to emotionScores,
        "boundingBox" to listOf(
            boundingBox.left.toDouble(),
            boundingBox.top.toDouble(),
            boundingBox.right.toDouble(),
            boundingBox.bottom.toDouble(),
        ),
        "eulerAngles" to listOf(headEulerAngleX, headEulerAngleY, headEulerAngleZ),
        "smilingProbability" to smilingProbability,
        "leftEyeOpenProbability" to leftEyeOpenProbability,
        "rightEyeOpenProbability" to rightEyeOpenProbability,
        "trackingId" to trackingId,
    )
}

data class FaceProcessorResult(val faces: List<SingleFaceResult>) {
    fun toMapList(): List<Map<String, Any?>> = faces.map { it.toMap() }

    companion object {
        fun empty() = FaceProcessorResult(emptyList())
    }
}

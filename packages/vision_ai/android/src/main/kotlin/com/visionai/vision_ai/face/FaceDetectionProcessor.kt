package com.visionai.vision_ai.face

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceContour
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import com.google.android.gms.tasks.Tasks
import com.visionai.vision_ai.core.BitmapPool

// ML Kit limitation: contour mode and face tracking cannot be enabled simultaneously —
// the SDK silently ignores tracking when contours are on, so we guard it explicitly.
// Landmark mode produces 10 sparse points (eyes, nose, ears, cheeks, mouth corners);
// contour mode gives per-region point sequences suitable for drawing face meshes.
// Both sets use pixel coordinates relative to the input bitmap, not normalized [0,1].
class FaceDetectionProcessor(private val context: Context) {

    private var faceDetector: FaceDetector? = null
    private var emotionClassifier: EmotionClassifier? = null
    private var detectEmotion = true
    private var detectContours = false
    private var detectLandmarks = false
    private var minEmotionConfidence = 0.4f // results below this threshold are discarded as unreliable

    fun initialize(
        detectEmotion: Boolean = true,
        detectContours: Boolean = false,
        detectLandmarks: Boolean = false,
        minFaceSize: Float = 0.1f,       // fraction of the shorter image dimension; smaller = more CPU
        enableTracking: Boolean = true,  // silently disabled when detectContours=true (ML Kit constraint)
        minEmotionConfidence: Float = 0.4f,
        accurateMode: Boolean = false,   // PERFORMANCE_MODE_ACCURATE is slower but catches distant/angled faces
    ) {
        close() // release existing detector/classifier before rebuilding

        this.detectEmotion = detectEmotion
        this.detectContours = detectContours
        this.detectLandmarks = detectLandmarks
        this.minEmotionConfidence = minEmotionConfidence

        val performanceMode = if (accurateMode)
            FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE
        else
            FaceDetectorOptions.PERFORMANCE_MODE_FAST

        val optionsBuilder = FaceDetectorOptions.Builder()
            .setPerformanceMode(performanceMode)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL) // enables smiling + eye-open probabilities
            .setMinFaceSize(minFaceSize)

        if (detectLandmarks) {
            optionsBuilder.setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
        }

        if (detectContours) {
            optionsBuilder.setContourMode(FaceDetectorOptions.CONTOUR_MODE_ALL)
        }

        if (enableTracking && !detectContours) {
            // ML Kit: tracking and contour mode can't be used together
            optionsBuilder.enableTracking()
        }

        faceDetector = FaceDetection.getClient(optionsBuilder.build())

        if (detectEmotion) {
            emotionClassifier = EmotionClassifier(context)
            emotionClassifier!!.initialize() // loads and mmap's the TFLite model from assets
        }
    }

    // Synchronous (Tasks.await); blocks the analysis thread until ML Kit returns results
    // rotationDegrees is informational only here — the bitmap is already upright from ImageConverter
    fun processFrame(bitmap: Bitmap, rotationDegrees: Int, pool: BitmapPool): FaceProcessorResult {
        val detector = faceDetector ?: return FaceProcessorResult.empty()

        // Pass rotation=0 because ImageConverter already applied the rotation to the bitmap
        val inputImage = InputImage.fromBitmap(bitmap, 0)

        val faces: List<Face> = try {
            Tasks.await(detector.process(inputImage)) // blocking; safe because we're on the analysis thread
        } catch (e: Exception) {
            Log.e(TAG, "Face detection failed", e)
            return FaceProcessorResult.empty()
        }

        if (faces.isEmpty()) return FaceProcessorResult.empty()

        val results = mutableListOf<SingleFaceResult>()

        for (face in faces) {
            var emotionResult = EmotionResult.none()

            if (detectEmotion && emotionClassifier != null) {
                // Crop with padding so the model sees forehead/chin context, not just inner face
                val cropped = cropFace(bitmap, face.boundingBox, pool)
                if (cropped != null) {
                    emotionResult = emotionClassifier!!.classify(cropped, pool)
                }
            }

            // Extract 10 face landmarks if enabled
            var landmarkPoints: DoubleArray? = null
            if (detectLandmarks) {
                landmarkPoints = extractLandmarks(face)
            }

            // Extract contour points if enabled
            var contourPoints: DoubleArray? = null
            var contourSizes: IntArray? = null
            if (detectContours) {
                val extracted = extractContours(face)
                contourPoints = extracted.first
                contourSizes = extracted.second // number of points per contour region, in fixed order
            }

            results.add(
                SingleFaceResult(
                    emotion = emotionResult.primaryEmotion,
                    emotionConfidence = emotionResult.confidence,
                    emotionScores = emotionResult.scores,
                    boundingBox = face.boundingBox, // pixel coords in the input bitmap space
                    headEulerAngleX = (face.headEulerAngleX).toDouble(), // pitch: positive=looking up, degrees
                    headEulerAngleY = (face.headEulerAngleY).toDouble(), // yaw: positive=turned right, degrees
                    headEulerAngleZ = (face.headEulerAngleZ).toDouble(), // roll: positive=head tilted right, degrees
                    smilingProbability = face.smilingProbability?.toDouble(),      // null when not in classification mode
                    leftEyeOpenProbability = face.leftEyeOpenProbability?.toDouble(),
                    rightEyeOpenProbability = face.rightEyeOpenProbability?.toDouble(),
                    trackingId = face.trackingId ?: -1, // -1 when tracking is disabled or face is new
                    landmarkPoints = landmarkPoints,
                    contourPoints = contourPoints,
                    contourSizes = contourSizes,
                )
            )
        }

        return FaceProcessorResult(results)
    }

    // Extracts 10 face landmark positions as flat [x0,y0, x1,y1, ...] array.
    // Order: leftEye, rightEye, noseBase, mouthLeft, mouthRight, mouthBottom,
    //        leftEar, rightEar, leftCheek, rightCheek
    // Missing landmarks (face turned away) get -1,-1.
    private fun extractLandmarks(face: Face): DoubleArray {
        val types = intArrayOf(
            FaceLandmark.LEFT_EYE, FaceLandmark.RIGHT_EYE,
            FaceLandmark.NOSE_BASE,
            FaceLandmark.MOUTH_LEFT, FaceLandmark.MOUTH_RIGHT, FaceLandmark.MOUTH_BOTTOM,
            FaceLandmark.LEFT_EAR, FaceLandmark.RIGHT_EAR,
            FaceLandmark.LEFT_CHEEK, FaceLandmark.RIGHT_CHEEK,
        )
        val result = DoubleArray(types.size * 2) // flattened for efficient Flutter codec transfer
        for (i in types.indices) {
            val lm = face.getLandmark(types[i])
            if (lm != null) {
                result[i * 2] = lm.position.x.toDouble()     // pixel x in input bitmap
                result[i * 2 + 1] = lm.position.y.toDouble() // pixel y in input bitmap
            } else {
                result[i * 2] = -1.0     // sentinel for "not visible" (face turned away)
                result[i * 2 + 1] = -1.0
            }
        }
        return result
    }

    // Extracts all 15 ML Kit contour types as a flat array + sizes per contour.
    // Contour order: face, leftEyebrowTop, leftEyebrowBottom, rightEyebrowTop,
    // rightEyebrowBottom, leftEye, rightEye, upperLipTop, upperLipBottom,
    // lowerLipTop, lowerLipBottom, noseBridge, noseBottom, leftCheek, rightCheek
    private fun extractContours(face: Face): Pair<DoubleArray, IntArray> {
        val contourTypes = intArrayOf(
            FaceContour.FACE,
            FaceContour.LEFT_EYEBROW_TOP,
            FaceContour.LEFT_EYEBROW_BOTTOM,
            FaceContour.RIGHT_EYEBROW_TOP,
            FaceContour.RIGHT_EYEBROW_BOTTOM,
            FaceContour.LEFT_EYE,
            FaceContour.RIGHT_EYE,
            FaceContour.UPPER_LIP_TOP,
            FaceContour.UPPER_LIP_BOTTOM,
            FaceContour.LOWER_LIP_TOP,
            FaceContour.LOWER_LIP_BOTTOM,
            FaceContour.NOSE_BRIDGE,
            FaceContour.NOSE_BOTTOM,
            FaceContour.LEFT_CHEEK,
            FaceContour.RIGHT_CHEEK,
        )

        val allPoints = mutableListOf<Double>() // flat [x0,y0, x1,y1, ...] across all contours
        val sizes = IntArray(contourTypes.size)  // point count per contour; needed to split allPoints on Dart side

        for (i in contourTypes.indices) {
            val contour = face.getContour(contourTypes[i])
            val points = contour?.points ?: emptyList() // null when face is turned too far for this region
            sizes[i] = points.size
            for (pt in points) {
                allPoints.add(pt.x.toDouble())
                allPoints.add(pt.y.toDouble())
            }
        }

        return Pair(allPoints.toDoubleArray(), sizes)
    }

    // Crops and pads the bounding box; 20% padding gives the emotion model forehead/chin context
    private fun cropFace(bitmap: Bitmap, bbox: Rect, pool: BitmapPool): Bitmap? {
        val padX = (bbox.width() * 0.2).toInt()
        val padY = (bbox.height() * 0.2).toInt()

        // Clamp to bitmap bounds to avoid illegal crop rectangles at image edges
        val left = (bbox.left - padX).coerceAtLeast(0)
        val top = (bbox.top - padY).coerceAtLeast(0)
        val right = (bbox.right + padX).coerceAtMost(bitmap.width)
        val bottom = (bbox.bottom + padY).coerceAtMost(bitmap.height)

        val width = right - left
        val height = bottom - top

        if (width <= 0 || height <= 0) return null // can happen when face is partially off-screen

        return try {
            pool.getCropBitmap(bitmap, left, top, width, height)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to crop face", e)
            null
        }
    }

    // Safe to call multiple times; also called by initialize() before rebuilding
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
    val emotionConfidence: Double,     // [0.0, 1.0] confidence for primaryEmotion
    val emotionScores: DoubleArray,    // [0.0,1.0] × 7: scores for all emotion classes in FER2013 order
    val boundingBox: Rect,             // pixel coords in input bitmap; not normalized
    val headEulerAngleX: Double,       // pitch in degrees; positive = looking up
    val headEulerAngleY: Double,       // yaw in degrees; positive = turned right
    val headEulerAngleZ: Double,       // roll in degrees; positive = head tilted right
    val smilingProbability: Double?,   // null when ML Kit classification is disabled
    val leftEyeOpenProbability: Double?,
    val rightEyeOpenProbability: Double?,
    val trackingId: Int,               // -1 when tracking disabled or face has no ID yet
    val landmarkPoints: DoubleArray?,  // null when detectLandmarks=false; 20 doubles (10 landmarks × [x,y])
    val contourPoints: DoubleArray?,   // null when detectContours=false; flat [x,y,...] across all contour regions
    val contourSizes: IntArray?,       // null when detectContours=false; point count per contour region
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
        "landmarkPoints" to landmarkPoints,
        "contourPoints" to contourPoints,
        "contourSizes" to contourSizes?.toList(),
    )
}

data class FaceProcessorResult(val faces: List<SingleFaceResult>) {
    fun toMapList(): List<Map<String, Any?>> = faces.map { it.toMap() }

    companion object {
        fun empty() = FaceProcessorResult(emptyList())
    }
}

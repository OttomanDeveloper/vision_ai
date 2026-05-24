package com.visionai.vision_ai.core

import android.graphics.Bitmap
import android.os.SystemClock
import android.util.Log
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.visionai.vision_ai.face.FaceDetectionProcessor
import com.visionai.vision_ai.hand.HandGestureProcessor

class FrameProcessor(
    private val resultAggregator: ResultAggregator,
    private val handProcessor: HandGestureProcessor? = null,
    private val faceProcessor: FaceDetectionProcessor? = null,
    private val isFrontCamera: Boolean = true,
) : ImageAnalysis.Analyzer {

    private var frameCount = 0L

    override fun analyze(imageProxy: ImageProxy) {
        try {
            val startTime = SystemClock.uptimeMillis()
            val timestamp = SystemClock.uptimeMillis()

            frameCount++
            if (frameCount % 100 == 0L) {
                Log.d(TAG, "Processed $frameCount frames")
            }

            // Convert frame once, reuse for both processors
            var bitmap: Bitmap? = null
            if (handProcessor != null || faceProcessor != null) {
                bitmap = ImageConverter.imageProxyToBitmap(imageProxy, isFrontCamera)
            }

            // Hand gesture detection (async via MediaPipe LIVE_STREAM)
            if (handProcessor != null && bitmap != null) {
                handProcessor.processFrame(bitmap, timestamp)
            }

            // Face emotion detection (sync via ML Kit)
            val faceResult = if (faceProcessor != null && bitmap != null) {
                faceProcessor.processFrame(bitmap, imageProxy.imageInfo.rotationDegrees)
            } else {
                null
            }

            val handResult = handProcessor?.getLatestResult()

            val inferenceTime = SystemClock.uptimeMillis() - startTime

            val imageWidth: Int
            val imageHeight: Int
            val rotation = imageProxy.imageInfo.rotationDegrees
            if (rotation == 90 || rotation == 270) {
                imageWidth = imageProxy.height
                imageHeight = imageProxy.width
            } else {
                imageWidth = imageProxy.width
                imageHeight = imageProxy.height
            }

            resultAggregator.emit(
                handResults = handResult?.toMapList() ?: emptyList(),
                faceResults = faceResult?.toMapList() ?: emptyList(),
                timestampMs = timestamp,
                inferenceTimeMs = inferenceTime,
                imageWidth = imageWidth,
                imageHeight = imageHeight,
            )
        } catch (e: Exception) {
            Log.e(TAG, "Frame processing error", e)
        } finally {
            imageProxy.close()
        }
    }

    companion object {
        private const val TAG = "VisionAI.FrameProcessor"
    }
}

package com.visionai.vision_ai.core

import android.os.SystemClock
import android.util.Log
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.visionai.vision_ai.hand.HandGestureProcessor

class FrameProcessor(
    private val resultAggregator: ResultAggregator,
    private val handProcessor: HandGestureProcessor? = null,
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

            if (handProcessor != null) {
                val bitmap = ImageConverter.imageProxyToBitmap(imageProxy, isFrontCamera)
                handProcessor.processFrame(bitmap, timestamp)
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
                faceResults = emptyList(),
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

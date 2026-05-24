package com.visionai.vision_ai.core

import android.graphics.Bitmap
import android.os.SystemClock
import android.util.Log
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.visionai.vision_ai.face.FaceDetectionProcessor
import com.visionai.vision_ai.hand.HandGestureProcessor

// Must run on a single thread — both MediaPipe (LIVE_STREAM) and ML Kit (Tasks.await) are
// called synchronously here. The ImageAnalysis backpressure strategy (STRATEGY_KEEP_ONLY_LATEST)
// means the executor never queues more than one pending frame, so slow inference naturally
// self-throttles rather than building up a backlog.
class FrameProcessor(
    private val resultAggregator: ResultAggregator,
    private val handProcessor: HandGestureProcessor? = null,
    private val faceProcessor: FaceDetectionProcessor? = null,
    private val isFrontCamera: Boolean = true, // controls horizontal mirror applied during rotation
) : ImageAnalysis.Analyzer {

    private var frameCount = 0L // monotonic counter; never resets across config changes
    val bitmapPool = BitmapPool() // shared with FaceDetectionProcessor to avoid duplicate allocations

    override fun analyze(imageProxy: ImageProxy) {
        try {
            val startTime = SystemClock.uptimeMillis()
            val timestamp = SystemClock.uptimeMillis() // ms since boot; used as MediaPipe timeline key

            frameCount++
            // Periodic log to confirm processing is alive without spamming logcat
            if (frameCount % 100 == 0L) {
                Log.d(TAG, "Processed $frameCount frames")
            }

            // Only convert to Bitmap when at least one processor needs pixel data
            var bitmap: Bitmap? = null
            if (handProcessor != null || faceProcessor != null) {
                bitmap = ImageConverter.imageProxyToBitmap(imageProxy, isFrontCamera, bitmapPool)
            }

            // Hand processor is async (recognizeAsync); result arrives on a MediaPipe internal thread
            if (handProcessor != null && bitmap != null) {
                handProcessor.processFrame(bitmap, timestamp)
            }

            // Face processor is synchronous (Tasks.await); result is available immediately
            val faceResult = if (faceProcessor != null && bitmap != null) {
                faceProcessor.processFrame(bitmap, imageProxy.imageInfo.rotationDegrees, bitmapPool)
            } else {
                null
            }

            // Picks up whatever hand result arrived since the previous frame (may be null if MediaPipe is still processing)
            val handResult = handProcessor?.getLatestResult()

            val inferenceTime = SystemClock.uptimeMillis() - startTime // ms; includes both hand+face

            // Swap width/height when the sensor is portrait-rotated so coordinates match the display orientation
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
            imageProxy.close() // must always close; not closing stalls the camera pipeline
        }
    }

    fun release() {
        bitmapPool.release()
    }

    companion object {
        private const val TAG = "VisionAI.FrameProcessor"
    }
}

package com.visionai.vision_ai.core

import android.os.SystemClock
import android.util.Log
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy

class FrameProcessor(
    private val resultAggregator: ResultAggregator,
) : ImageAnalysis.Analyzer {

    private var frameCount = 0L

    override fun analyze(imageProxy: ImageProxy) {
        try {
            val startTime = SystemClock.uptimeMillis()
            val timestamp = SystemClock.uptimeMillis()

            frameCount++
            if (frameCount % 60 == 0L) {
                Log.d("VisionAI", "Processed $frameCount frames")
            }

            val inferenceTime = SystemClock.uptimeMillis() - startTime

            resultAggregator.emit(
                handResults = emptyList(),
                faceResults = emptyList(),
                timestampMs = timestamp,
                inferenceTimeMs = inferenceTime,
                imageWidth = imageProxy.width,
                imageHeight = imageProxy.height,
            )
        } finally {
            imageProxy.close()
        }
    }
}

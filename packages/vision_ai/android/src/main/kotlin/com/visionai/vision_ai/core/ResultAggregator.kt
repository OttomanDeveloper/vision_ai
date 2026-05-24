package com.visionai.vision_ai.core

import android.os.Handler
import android.os.SystemClock
import io.flutter.plugin.common.EventChannel

class ResultAggregator(
    private val mainHandler: Handler,
    private val eventSinkProvider: () -> EventChannel.EventSink?,
    maxResultsPerSecond: Int = 0,
) {
    // Minimum time between emissions in ms. 0 = no throttle (emit every frame).
    private val minIntervalMs: Long = if (maxResultsPerSecond > 0) {
        1000L / maxResultsPerSecond.toLong()
    } else {
        0L
    }

    private var lastEmitTime: Long = 0L

    fun emit(
        handResults: List<Map<String, Any?>>,
        faceResults: List<Map<String, Any?>>,
        timestampMs: Long,
        inferenceTimeMs: Long,
        imageWidth: Int,
        imageHeight: Int,
    ) {
        // Skip this result if we emitted too recently
        if (minIntervalMs > 0) {
            val now = SystemClock.uptimeMillis()
            if (now - lastEmitTime < minIntervalMs) return
            lastEmitTime = now
        }

        val resultMap = hashMapOf<String, Any?>(
            "timestamp" to timestampMs,
            "inferenceTime" to inferenceTimeMs,
            "imageWidth" to imageWidth,
            "imageHeight" to imageHeight,
            "hands" to handResults,
            "faces" to faceResults,
        )

        mainHandler.post {
            eventSinkProvider()?.success(resultMap)
        }
    }
}

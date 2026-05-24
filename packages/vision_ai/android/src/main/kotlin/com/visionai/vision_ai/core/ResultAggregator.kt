package com.visionai.vision_ai.core

import android.os.Handler
import android.os.SystemClock
import io.flutter.plugin.common.EventChannel

// EventChannel.EventSink.success() must be called on the main thread — that's why every emit
// goes through mainHandler.post(). The throttle (minIntervalMs) is enforced on the analysis
// thread before posting, so we never queue up redundant main-thread work at high frame rates.
class ResultAggregator(
    private val mainHandler: Handler,
    private val eventSinkProvider: () -> EventChannel.EventSink?, // lambda avoids holding a stale sink reference
    maxResultsPerSecond: Int = 0,
) {
    // Minimum time between emissions in ms. 0 = no throttle (emit every frame).
    private val minIntervalMs: Long = if (maxResultsPerSecond > 0) {
        1000L / maxResultsPerSecond.toLong()
    } else {
        0L
    }

    // Tracks when the last result was posted; read+written only on the analysis thread (no sync needed)
    private var lastEmitTime: Long = 0L

    fun emit(
        handResults: List<Map<String, Any?>>,
        faceResults: List<Map<String, Any?>>,
        timestampMs: Long,    // ms since boot (SystemClock.uptimeMillis), not wall clock
        inferenceTimeMs: Long, // total ms spent in FrameProcessor.analyze for this frame
        imageWidth: Int,       // display-orientation width (already swapped for 90°/270° rotation)
        imageHeight: Int,
    ) {
        // Drop frame early on the analysis thread rather than posting a no-op to the main thread
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

        // eventSinkProvider() is evaluated on the main thread; avoids a race where sink is nulled between check and call
        mainHandler.post {
            eventSinkProvider()?.success(resultMap)
        }
    }
}

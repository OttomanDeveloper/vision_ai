package com.visionai.vision_ai.core

import android.os.Handler
import io.flutter.plugin.common.EventChannel

class ResultAggregator(
    private val mainHandler: Handler,
    private val eventSinkProvider: () -> EventChannel.EventSink?,
) {
    fun emit(
        handResults: List<Map<String, Any?>>,
        faceResults: List<Map<String, Any?>>,
        timestampMs: Long,
        inferenceTimeMs: Long,
        imageWidth: Int,
        imageHeight: Int,
    ) {
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

package com.visionai.vision_ai.core

import android.graphics.Bitmap
import androidx.camera.core.ImageProxy

object ImageConverter {

    fun imageProxyToBitmap(imageProxy: ImageProxy, isFrontCamera: Boolean, pool: BitmapPool): Bitmap {
        val buffer = imageProxy.planes[0].buffer
        val pixelStride = imageProxy.planes[0].pixelStride
        val rowStride = imageProxy.planes[0].rowStride
        val rowPadding = rowStride - pixelStride * imageProxy.width

        val rawWidth = imageProxy.width + rowPadding / pixelStride
        val rawHeight = imageProxy.height
        val raw = pool.getRawBitmap(rawWidth, rawHeight)
        buffer.rewind()
        raw.copyPixelsFromBuffer(buffer)

        val srcWidth = imageProxy.width
        val srcHeight = imageProxy.height

        val rotationDegrees = imageProxy.imageInfo.rotationDegrees
        if (rotationDegrees == 0 && !isFrontCamera && rowPadding == 0) {
            return raw
        }

        // Use the pool's source region (handles padding crop + rotation + mirror in one pass)
        val source = if (rowPadding > 0) {
            // Need to use only the valid region; drawRotated handles this via srcWidth/srcHeight
            raw
        } else {
            raw
        }

        return pool.drawRotated(source, srcWidth, srcHeight, rotationDegrees, isFrontCamera)
    }
}

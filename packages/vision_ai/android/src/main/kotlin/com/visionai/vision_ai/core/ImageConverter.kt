package com.visionai.vision_ai.core

import android.graphics.Bitmap
import androidx.camera.core.ImageProxy

// Assumes ImageProxy is in RGBA_8888 format (configured in CameraManager).
// The row stride may include padding bytes beyond the declared width — rawWidth accounts for this
// so copyPixelsFromBuffer reads the full buffer correctly before we crop via drawRotated.
object ImageConverter {

    fun imageProxyToBitmap(imageProxy: ImageProxy, isFrontCamera: Boolean, pool: BitmapPool): Bitmap {
        val buffer = imageProxy.planes[0].buffer  // plane[0] is the only plane in RGBA_8888
        val pixelStride = imageProxy.planes[0].pixelStride // always 4 for RGBA_8888
        val rowStride = imageProxy.planes[0].rowStride     // bytes per row including hardware padding
        val rowPadding = rowStride - pixelStride * imageProxy.width // extra bytes at the end of each row

        // rawWidth includes the padding columns; without this, copyPixelsFromBuffer reads out of bounds
        val rawWidth = imageProxy.width + rowPadding / pixelStride
        val rawHeight = imageProxy.height
        val raw = pool.getRawBitmap(rawWidth, rawHeight)
        buffer.rewind() // position must be 0 before copyPixelsFromBuffer
        raw.copyPixelsFromBuffer(buffer)

        val srcWidth = imageProxy.width
        val srcHeight = imageProxy.height

        val rotationDegrees = imageProxy.imageInfo.rotationDegrees
        // Fast path: no rotation, no mirror (back camera), no padding — return raw directly
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

        // drawRotated crops to srcWidth×srcHeight, applies rotation, then mirrors for front camera
        return pool.drawRotated(source, srcWidth, srcHeight, rotationDegrees, isFrontCamera)
    }
}

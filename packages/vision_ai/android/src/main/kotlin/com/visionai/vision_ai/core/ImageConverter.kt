package com.visionai.vision_ai.core

import android.graphics.Bitmap
import android.graphics.Matrix
import androidx.camera.core.ImageProxy

object ImageConverter {

    fun imageProxyToBitmap(imageProxy: ImageProxy, isFrontCamera: Boolean): Bitmap {
        val buffer = imageProxy.planes[0].buffer
        val pixelStride = imageProxy.planes[0].pixelStride
        val rowStride = imageProxy.planes[0].rowStride
        val rowPadding = rowStride - pixelStride * imageProxy.width

        val bitmap = Bitmap.createBitmap(
            imageProxy.width + rowPadding / pixelStride,
            imageProxy.height,
            Bitmap.Config.ARGB_8888
        )
        buffer.rewind()
        bitmap.copyPixelsFromBuffer(buffer)

        val croppedBitmap = if (rowPadding > 0) {
            Bitmap.createBitmap(bitmap, 0, 0, imageProxy.width, imageProxy.height)
        } else {
            bitmap
        }

        val rotationDegrees = imageProxy.imageInfo.rotationDegrees
        if (rotationDegrees == 0 && !isFrontCamera) return croppedBitmap

        val matrix = Matrix()
        if (rotationDegrees != 0) {
            matrix.postRotate(rotationDegrees.toFloat())
        }
        if (isFrontCamera) {
            matrix.postScale(-1f, 1f)
        }

        return Bitmap.createBitmap(
            croppedBitmap, 0, 0,
            croppedBitmap.width, croppedBitmap.height,
            matrix, true
        )
    }
}

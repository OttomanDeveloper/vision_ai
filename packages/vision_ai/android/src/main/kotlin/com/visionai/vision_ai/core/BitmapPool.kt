package com.visionai.vision_ai.core

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import java.nio.ByteBuffer
import java.nio.ByteOrder

// At 20+ FPS, creating a new Bitmap per frame saturates the GC — each 640x480 ARGB_8888 frame
// is ~1.2 MB. This pool keeps one instance of each logical bitmap and reuses it if the
// dimensions match, erasing it with eraseColor(0) rather than re-allocating.
// Bitmaps must be released on the analysis thread (via FrameProcessor.release) before the
// pool goes out of scope; recycling on a different thread while inference is running will crash.
class BitmapPool {

    private var rawBitmap: Bitmap? = null
    private var rotatedBitmap: Bitmap? = null
    private var faceCropBitmap: Bitmap? = null
    private var faceResizedBitmap: Bitmap? = null
    private var tfliteBuffer: ByteBuffer? = null
    private var pixelArray: IntArray? = null

    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val matrix = Matrix()

    fun getRawBitmap(width: Int, height: Int): Bitmap {
        val existing = rawBitmap
        if (existing != null && existing.width == width && existing.height == height && !existing.isRecycled) {
            existing.eraseColor(0)
            return existing
        }
        existing?.recycle()
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        rawBitmap = bmp
        return bmp
    }

    fun getRotatedBitmap(width: Int, height: Int): Bitmap {
        val existing = rotatedBitmap
        if (existing != null && existing.width == width && existing.height == height && !existing.isRecycled) {
            existing.eraseColor(0)
            return existing
        }
        existing?.recycle()
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        rotatedBitmap = bmp
        return bmp
    }

    fun drawRotated(source: Bitmap, srcWidth: Int, srcHeight: Int, rotationDegrees: Int, mirror: Boolean): Bitmap {
        matrix.reset()
        if (rotationDegrees != 0) {
            matrix.postRotate(rotationDegrees.toFloat())
        }
        if (mirror) {
            matrix.postScale(-1f, 1f)
        }

        val dstWidth: Int
        val dstHeight: Int
        if (rotationDegrees == 90 || rotationDegrees == 270) {
            dstWidth = srcHeight
            dstHeight = srcWidth
        } else {
            dstWidth = srcWidth
            dstHeight = srcHeight
        }

        // Translate to keep in bounds after rotation/mirror
        val values = FloatArray(9)
        matrix.getValues(values)
        val dx = if (values[Matrix.MTRANS_X] < 0 || (mirror && rotationDegrees == 0)) dstWidth.toFloat() else 0f
        val dy = if (values[Matrix.MTRANS_Y] < 0) dstHeight.toFloat() else 0f

        matrix.reset()
        if (rotationDegrees != 0) matrix.postRotate(rotationDegrees.toFloat())
        if (mirror) matrix.postScale(-1f, 1f)

        // Recalculate proper translation
        val testPts = floatArrayOf(0f, 0f, srcWidth.toFloat(), 0f, 0f, srcHeight.toFloat(), srcWidth.toFloat(), srcHeight.toFloat())
        matrix.mapPoints(testPts)
        var minX = Float.MAX_VALUE
        var minY = Float.MAX_VALUE
        for (i in testPts.indices step 2) {
            if (testPts[i] < minX) minX = testPts[i]
            if (testPts[i + 1] < minY) minY = testPts[i + 1]
        }
        matrix.postTranslate(-minX, -minY)

        val dst = getRotatedBitmap(dstWidth, dstHeight)
        val canvas = Canvas(dst)
        canvas.drawBitmap(source, matrix, paint)
        return dst
    }

    fun getCropBitmap(source: Bitmap, left: Int, top: Int, width: Int, height: Int): Bitmap {
        val existing = faceCropBitmap
        if (existing != null && existing.width == width && existing.height == height && !existing.isRecycled) {
            existing.eraseColor(0)
        } else {
            existing?.recycle()
            faceCropBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        }
        val dst = faceCropBitmap!!
        val canvas = Canvas(dst)
        val srcRect = Rect(left, top, left + width, top + height)
        val dstRect = Rect(0, 0, width, height)
        canvas.drawBitmap(source, srcRect, dstRect, paint)
        return dst
    }

    fun getResizedBitmap(source: Bitmap, targetWidth: Int, targetHeight: Int): Bitmap {
        val existing = faceResizedBitmap
        if (existing != null && existing.width == targetWidth && existing.height == targetHeight && !existing.isRecycled) {
            existing.eraseColor(0)
        } else {
            existing?.recycle()
            faceResizedBitmap = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
        }
        val dst = faceResizedBitmap!!
        val canvas = Canvas(dst)
        val srcRect = Rect(0, 0, source.width, source.height)
        val dstRect = Rect(0, 0, targetWidth, targetHeight)
        canvas.drawBitmap(source, srcRect, dstRect, paint)
        return dst
    }

    fun getTfliteBuffer(size: Int): ByteBuffer {
        val existing = tfliteBuffer
        if (existing != null && existing.capacity() == size) {
            existing.rewind()
            return existing
        }
        val buf = ByteBuffer.allocateDirect(size)
        buf.order(ByteOrder.nativeOrder())
        tfliteBuffer = buf
        return buf
    }

    fun getPixelArray(size: Int): IntArray {
        val existing = pixelArray
        if (existing != null && existing.size == size) return existing
        val arr = IntArray(size)
        pixelArray = arr
        return arr
    }

    fun release() {
        rawBitmap?.recycle()
        rotatedBitmap?.recycle()
        faceCropBitmap?.recycle()
        faceResizedBitmap?.recycle()
        rawBitmap = null
        rotatedBitmap = null
        faceCropBitmap = null
        faceResizedBitmap = null
        tfliteBuffer = null
        pixelArray = null
    }
}

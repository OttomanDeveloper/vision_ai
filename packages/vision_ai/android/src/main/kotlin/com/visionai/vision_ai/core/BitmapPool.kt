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

    private var rawBitmap: Bitmap? = null         // full-stride frame from ImageProxy (may include padding columns)
    private var rotatedBitmap: Bitmap? = null     // frame after rotation+mirror; handed to ML processors
    private var faceCropBitmap: Bitmap? = null    // cropped region around a detected face
    private var faceResizedBitmap: Bitmap? = null // face crop scaled to model input size
    private var tfliteBuffer: ByteBuffer? = null  // direct ByteBuffer for TFLite input tensor; nativeOrder required
    private var pixelArray: IntArray? = null      // intermediate ARGB pixels for preprocessing; avoids per-frame int[] alloc

    private val paint = Paint(Paint.FILTER_BITMAP_FLAG) // bilinear filtering during scale/rotate for better quality
    private val matrix = Matrix() // reused across drawRotated calls to avoid allocation

    // Returns a bitmap of exactly (width × height) ARGB_8888; recycles if dimensions changed
    fun getRawBitmap(width: Int, height: Int): Bitmap {
        val existing = rawBitmap
        if (existing != null && existing.width == width && existing.height == height && !existing.isRecycled) {
            existing.eraseColor(0) // clear stale pixel data from last frame
            return existing
        }
        existing?.recycle()
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        rawBitmap = bmp
        return bmp
    }

    // Returns a bitmap sized for the post-rotation output; dimensions swap for 90°/270° rotations
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

    // Applies rotation and optional horizontal mirror to source, writing into the pooled rotated bitmap.
    // srcWidth/srcHeight define the valid region inside source (may be smaller than source.width due to row padding).
    // mirror=true flips horizontally, which corrects the selfie-camera mirroring for front-facing use.
    fun drawRotated(source: Bitmap, srcWidth: Int, srcHeight: Int, rotationDegrees: Int, mirror: Boolean): Bitmap {
        matrix.reset()
        if (rotationDegrees != 0) {
            matrix.postRotate(rotationDegrees.toFloat())
        }
        if (mirror) {
            matrix.postScale(-1f, 1f)
        }

        // After rotation, logical width and height swap for 90°/270°
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

        // Map all four corners to find the true min offset after transform, then translate back to origin
        val testPts = floatArrayOf(0f, 0f, srcWidth.toFloat(), 0f, 0f, srcHeight.toFloat(), srcWidth.toFloat(), srcHeight.toFloat())
        matrix.mapPoints(testPts)
        var minX = Float.MAX_VALUE
        var minY = Float.MAX_VALUE
        for (i in testPts.indices step 2) {
            if (testPts[i] < minX) minX = testPts[i]
            if (testPts[i + 1] < minY) minY = testPts[i + 1]
        }
        matrix.postTranslate(-minX, -minY) // shifts result so top-left corner is at (0,0)

        val dst = getRotatedBitmap(dstWidth, dstHeight)
        val canvas = Canvas(dst)
        canvas.drawBitmap(source, matrix, paint)
        return dst
    }

    // Crops a region from source and draws it into a pooled bitmap; pads bounding box by the caller
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

    // Scales source to (targetWidth × targetHeight) using bilinear filtering; for TFLite input preparation
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

    // Returns a direct ByteBuffer sized for a TFLite input tensor; nativeOrder matches TFLite's expectation
    // size = 4 * width * height * channels (float32 per channel)
    fun getTfliteBuffer(size: Int): ByteBuffer {
        val existing = tfliteBuffer
        if (existing != null && existing.capacity() == size) {
            existing.rewind() // reset position so TFLite reads from the start
            return existing
        }
        val buf = ByteBuffer.allocateDirect(size) // direct allocation bypasses JVM heap; required for TFLite
        buf.order(ByteOrder.nativeOrder())
        tfliteBuffer = buf
        return buf
    }

    // Returns an int array for getPixels(); reused to avoid per-frame IntArray allocation during preprocessing
    fun getPixelArray(size: Int): IntArray {
        val existing = pixelArray
        if (existing != null && existing.size == size) return existing
        val arr = IntArray(size)
        pixelArray = arr
        return arr
    }

    // Must be called on the analysis thread before this pool is garbage collected
    fun release() {
        rawBitmap?.recycle()
        rotatedBitmap?.recycle()
        faceCropBitmap?.recycle()
        faceResizedBitmap?.recycle()
        rawBitmap = null
        rotatedBitmap = null
        faceCropBitmap = null
        faceResizedBitmap = null
        tfliteBuffer = null // direct ByteBuffer is freed by the JVM; nulling allows GC to reclaim faster
        pixelArray = null
    }
}

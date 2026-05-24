package com.visionai.vision_ai.face

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.util.Log
import com.visionai.vision_ai.core.BitmapPool
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel

// Model input shape is read at runtime so we can swap in a different .tflite asset without
// code changes (e.g. a 64x64 RGB model vs the default 48x48 grayscale FER2013 model).
// Label order assumes FER2013 convention; if a replacement model uses a different label order
// the debug logging (every 60 frames) will make mismatches obvious during testing.
class EmotionClassifier(private val context: Context) {

    private var interpreter: Interpreter? = null
    private var inputWidth = 48   // px; overridden at runtime from model tensor shape
    private var inputHeight = 48  // px; overridden at runtime from model tensor shape
    private var inputChannels = 1 // 1=grayscale (FER2013), 3=RGB; overridden from model tensor shape
    private var numClasses = 7    // overridden from model output tensor shape

    // FER2013 standard label order (most common for emotion models)
    // Index: 0=Angry, 1=Disgust, 2=Fear, 3=Happy, 4=Sad, 5=Surprise, 6=Neutral
    private val labelMap = arrayOf("angry", "disgusted", "fearful", "happy", "sad", "surprised", "neutral")

    // Dart expects: angry(0), disgusted(1), fearful(2), happy(3), sad(4), surprised(5), neutral(6)
    // FER2013 order matches Dart order exactly — no remapping needed
    private val toDartIndex = intArrayOf(0, 1, 2, 3, 4, 5, 6)

    private val output = Array(1) { FloatArray(7) } // reused across inferences; batch size is always 1
    private val dartScores = DoubleArray(7)           // reused to avoid per-frame allocation when copying to Dart
    private var debugFrameCount = 0L                  // monotonic; used to rate-limit debug logs

    fun initialize() {
        val modelBuffer = loadModelFile("emotion_classifier.tflite")
        val options = Interpreter.Options().apply {
            numThreads = 2 // 2 threads balances throughput vs battery; single thread is often slower on modern SoCs
        }
        interpreter = Interpreter(modelBuffer, options)

        // Read actual tensor shapes so we handle non-FER2013 model variants automatically
        val inputShape = interpreter!!.getInputTensor(0).shape()  // [batch, height, width, channels]
        val outputShape = interpreter!!.getOutputTensor(0).shape() // [batch, numClasses]

        if (inputShape.size == 4) {
            inputHeight = inputShape[1]
            inputWidth = inputShape[2]
            inputChannels = inputShape[3]
        }
        numClasses = outputShape[1]

        Log.d(TAG, "Emotion model loaded: input=${inputWidth}x${inputHeight}x$inputChannels, classes=$numClasses")
    }

    // faceBitmap must be the cropped face region from BitmapPool; classify() will resize it internally
    fun classify(faceBitmap: Bitmap, pool: BitmapPool): EmotionResult {
        val interp = interpreter ?: return EmotionResult.none()

        val resized = pool.getResizedBitmap(faceBitmap, inputWidth, inputHeight) // scales to model input size
        val inputBuffer = preprocessFace(resized, pool)

        output[0].fill(0f) // clear stale values in case inference throws before writing output

        try {
            interp.run(inputBuffer, output)
        } catch (e: Exception) {
            // Can happen if close() races with an in-flight inference during teardown
            Log.w(TAG, "TFLite inference failed (interpreter may be closing)", e)
            return EmotionResult.none()
        }

        val probabilities = output[0]

        var maxIdx = 0
        var maxVal = probabilities[0]
        for (i in 1 until numClasses.coerceAtMost(probabilities.size)) {
            if (probabilities[i] > maxVal) {
                maxVal = probabilities[i]
                maxIdx = i
            }
        }

        val primaryEmotion = if (maxIdx < labelMap.size) labelMap[maxIdx] else "neutral"

        // Debug: log raw probabilities every ~60 frames to verify label order
        debugFrameCount++
        if (debugFrameCount % 60 == 0L) {
            val scores = probabilities.mapIndexed { i, v ->
                "${labelMap.getOrElse(i) { "?" }}=${String.format("%.2f", v)}"
            }.joinToString(", ")
            Log.d(TAG, "Emotion scores: [$scores] → $primaryEmotion")
        }

        // Map model output indices to Dart-side indices via toDartIndex (identity for FER2013)
        dartScores.fill(0.0)
        for (i in probabilities.indices) {
            if (i < toDartIndex.size && toDartIndex[i] < 7) {
                dartScores[toDartIndex[i]] = probabilities[i].toDouble()
            }
        }

        return EmotionResult(
            primaryEmotion = primaryEmotion,
            confidence = maxVal.toDouble(), // [0.0, 1.0]; raw softmax output, not temperature-scaled
            scores = dartScores.copyOf(),   // copy so dartScores can be reused next frame
        )
    }

    // Converts bitmap to a float32 TFLite input buffer; grayscale uses BT.601 luma weights
    private fun preprocessFace(bitmap: Bitmap, pool: BitmapPool): ByteBuffer {
        val bufferSize = 4 * inputWidth * inputHeight * inputChannels // 4 bytes per float32
        val buffer = pool.getTfliteBuffer(bufferSize)

        val pixelCount = inputWidth * inputHeight
        val pixels = pool.getPixelArray(pixelCount)
        bitmap.getPixels(pixels, 0, inputWidth, 0, 0, inputWidth, inputHeight)

        for (pixel in pixels) {
            val r = Color.red(pixel)
            val g = Color.green(pixel)
            val b = Color.blue(pixel)

            if (inputChannels == 1) {
                // BT.601 luma coefficients; matches what most FER2013 models were trained with
                val gray = (0.299f * r + 0.587f * g + 0.114f * b) / 255.0f
                buffer.putFloat(gray)
            } else {
                // RGB model — normalize each channel to [0.0, 1.0]
                buffer.putFloat(r / 255.0f)
                buffer.putFloat(g / 255.0f)
                buffer.putFloat(b / 255.0f)
            }
        }

        buffer.rewind() // TFLite reads from position 0; rewind after filling
        return buffer
    }

    // Uses memory-mapped file I/O so the OS can page-out the model when not in use, reducing RAM pressure
    private fun loadModelFile(filename: String): MappedByteBuffer {
        val assetFd = context.assets.openFd(filename)
        return assetFd.use { fd ->
            val inputStream = FileInputStream(fd.fileDescriptor)
            inputStream.use { stream ->
                val fileChannel = stream.channel
                fileChannel.map(
                    FileChannel.MapMode.READ_ONLY,
                    fd.startOffset,
                    fd.declaredLength
                )
            }
        }
    }

    // Must be called on the analysis thread; interpreter.close() is not thread-safe
    fun close() {
        interpreter?.close()
        interpreter = null
    }

    companion object {
        private const val TAG = "EmotionClassifier"
    }
}

data class EmotionResult(
    val primaryEmotion: String, // label of the highest-scoring class
    val confidence: Double,     // [0.0, 1.0] raw softmax score for primaryEmotion
    val scores: DoubleArray,    // [0.0,1.0] × 7 scores for all classes in Dart label order
) {
    companion object {
        // Returned when the interpreter is unavailable or inference fails; avoids nullable in callers
        fun none() = EmotionResult(
            primaryEmotion = "none",
            confidence = 0.0,
            scores = DoubleArray(7),
        )
    }
}

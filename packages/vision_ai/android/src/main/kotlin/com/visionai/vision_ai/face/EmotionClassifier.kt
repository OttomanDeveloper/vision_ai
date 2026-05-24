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
    private var inputWidth = 48
    private var inputHeight = 48
    private var inputChannels = 1
    private var numClasses = 7

    // FER2013 standard label order (most common for emotion models)
    // Index: 0=Angry, 1=Disgust, 2=Fear, 3=Happy, 4=Sad, 5=Surprise, 6=Neutral
    private val labelMap = arrayOf("angry", "disgusted", "fearful", "happy", "sad", "surprised", "neutral")

    // Dart expects: angry(0), disgusted(1), fearful(2), happy(3), sad(4), surprised(5), neutral(6)
    // FER2013 order matches Dart order exactly — no remapping needed
    private val toDartIndex = intArrayOf(0, 1, 2, 3, 4, 5, 6)

    private val output = Array(1) { FloatArray(7) }
    private val dartScores = DoubleArray(7)
    private var debugFrameCount = 0L

    fun initialize() {
        val modelBuffer = loadModelFile("emotion_classifier.tflite")
        val options = Interpreter.Options().apply {
            numThreads = 2
        }
        interpreter = Interpreter(modelBuffer, options)

        val inputShape = interpreter!!.getInputTensor(0).shape()
        val outputShape = interpreter!!.getOutputTensor(0).shape()

        if (inputShape.size == 4) {
            inputHeight = inputShape[1]
            inputWidth = inputShape[2]
            inputChannels = inputShape[3]
        }
        numClasses = outputShape[1]

        Log.d(TAG, "Emotion model loaded: input=${inputWidth}x${inputHeight}x$inputChannels, classes=$numClasses")
    }

    fun classify(faceBitmap: Bitmap, pool: BitmapPool): EmotionResult {
        val interp = interpreter ?: return EmotionResult.none()

        val resized = pool.getResizedBitmap(faceBitmap, inputWidth, inputHeight)
        val inputBuffer = preprocessFace(resized, pool)

        output[0].fill(0f)

        try {
            interp.run(inputBuffer, output)
        } catch (e: Exception) {
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

        dartScores.fill(0.0)
        for (i in probabilities.indices) {
            if (i < toDartIndex.size && toDartIndex[i] < 7) {
                dartScores[toDartIndex[i]] = probabilities[i].toDouble()
            }
        }

        return EmotionResult(
            primaryEmotion = primaryEmotion,
            confidence = maxVal.toDouble(),
            scores = dartScores.copyOf(),
        )
    }

    private fun preprocessFace(bitmap: Bitmap, pool: BitmapPool): ByteBuffer {
        val bufferSize = 4 * inputWidth * inputHeight * inputChannels
        val buffer = pool.getTfliteBuffer(bufferSize)

        val pixelCount = inputWidth * inputHeight
        val pixels = pool.getPixelArray(pixelCount)
        bitmap.getPixels(pixels, 0, inputWidth, 0, 0, inputWidth, inputHeight)

        for (pixel in pixels) {
            val r = Color.red(pixel)
            val g = Color.green(pixel)
            val b = Color.blue(pixel)

            if (inputChannels == 1) {
                val gray = (0.299f * r + 0.587f * g + 0.114f * b) / 255.0f
                buffer.putFloat(gray)
            } else {
                buffer.putFloat(r / 255.0f)
                buffer.putFloat(g / 255.0f)
                buffer.putFloat(b / 255.0f)
            }
        }

        buffer.rewind()
        return buffer
    }

    private fun loadModelFile(filename: String): MappedByteBuffer {
        val assetFd = context.assets.openFd(filename)
        val inputStream = FileInputStream(assetFd.fileDescriptor)
        val fileChannel = inputStream.channel
        return fileChannel.map(
            FileChannel.MapMode.READ_ONLY,
            assetFd.startOffset,
            assetFd.declaredLength
        )
    }

    fun close() {
        interpreter?.close()
        interpreter = null
    }

    companion object {
        private const val TAG = "EmotionClassifier"
    }
}

data class EmotionResult(
    val primaryEmotion: String,
    val confidence: Double,
    val scores: DoubleArray,
) {
    companion object {
        fun none() = EmotionResult(
            primaryEmotion = "none",
            confidence = 0.0,
            scores = DoubleArray(7),
        )
    }
}

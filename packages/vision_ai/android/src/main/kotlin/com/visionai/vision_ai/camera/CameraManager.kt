package com.visionai.vision_ai.camera

import android.content.Context
import android.util.Size
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.visionai.vision_ai.core.FrameProcessor
import io.flutter.view.TextureRegistry
import java.util.concurrent.ExecutorService

class CameraManager(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    private val analysisExecutor: ExecutorService,
    private val lifecycleOwner: LifecycleOwner,
) {
    private var cameraProvider: ProcessCameraProvider? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var currentFacing: Int = 0

    fun start(facing: Int, resolution: Int, frameProcessor: FrameProcessor): Long {
        currentFacing = facing
        val entry = textureRegistry.createSurfaceTexture()
        textureEntry = entry

        val targetSize = when (resolution) {
            0 -> Size(320, 240)
            2 -> Size(1280, 720)
            else -> Size(640, 480)
        }

        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        val provider = cameraProviderFuture.get()
        cameraProvider = provider

        val cameraSelector = if (facing == 0) {
            CameraSelector.DEFAULT_FRONT_CAMERA
        } else {
            CameraSelector.DEFAULT_BACK_CAMERA
        }

        val surfaceTexture = entry.surfaceTexture()

        val preview = Preview.Builder()
            .build()
            .also {
                it.setSurfaceProvider { request ->
                    surfaceTexture.setDefaultBufferSize(
                        request.resolution.width,
                        request.resolution.height
                    )
                    val surface = android.view.Surface(surfaceTexture)
                    request.provideSurface(surface, ContextCompat.getMainExecutor(context)) {
                        surface.release()
                    }
                }
            }

        val imageAnalysis = ImageAnalysis.Builder()
            .setTargetResolution(targetSize)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
            .also {
                it.setAnalyzer(analysisExecutor, frameProcessor)
            }

        provider.unbindAll()
        provider.bindToLifecycle(
            lifecycleOwner,
            cameraSelector,
            preview,
            imageAnalysis
        )

        return entry.id()
    }

    fun switchCamera(facing: Int) {
        currentFacing = facing
        // Rebind would need frameProcessor reference; for now, a full restart is needed
    }

    fun stop() {
        cameraProvider?.unbindAll()
    }

    fun release() {
        cameraProvider?.unbindAll()
        textureEntry?.release()
        textureEntry = null
        cameraProvider = null
    }
}

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

// We own the camera entirely on the native side so we can feed raw frames to ML processors
// before Flutter ever sees them. The TextureRegistry entry gives Flutter a surface to render
// the preview without going through a platform view.
//
// OUTPUT_IMAGE_FORMAT_RGBA_8888 is chosen because MediaPipe's BitmapImageBuilder and ML Kit's
// InputImage.fromBitmap both expect ARGB_8888 bitmaps — using RGBA avoids a YUV→RGB conversion
// step that would otherwise happen on every frame.
class CameraManager(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    private val analysisExecutor: ExecutorService, // frames are delivered on this thread; must be single-threaded
    private val lifecycleOwner: LifecycleOwner,
) {
    private var cameraProvider: ProcessCameraProvider? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var currentFacing: Int = 0 // 0=front, 1=back; mirrors CameraFacing.index in Dart

    // Retained from start() so switchCamera can rebind the use cases without a full restart.
    private var frameProcessor: FrameProcessor? = null
    private var resolution: Int = 1

    // Returns the Flutter texture id that the Texture widget uses to render the preview.
    // Blocks the calling thread on ProcessCameraProvider.get() — call off the main thread if latency matters.
    fun start(facing: Int, resolution: Int, frameProcessor: FrameProcessor): Long {
        currentFacing = facing
        this.resolution = resolution
        this.frameProcessor = frameProcessor

        val entry = textureRegistry.createSurfaceTexture()
        textureEntry = entry

        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        val provider = cameraProviderFuture.get() // blocking; safe here because start() is called on analysisExecutor
        cameraProvider = provider

        bindUseCases(facing)

        return entry.id() // Flutter side creates a Texture(textureId: id) with this value
    }

    // Builds the preview + analysis use cases and binds them for the given facing.
    // Reuses the existing texture entry so the Flutter texture id stays valid across a camera switch.
    private fun bindUseCases(facing: Int) {
        val provider = cameraProvider ?: return
        val entry = textureEntry ?: return
        val processor = frameProcessor ?: return

        // Resolution is a hint; CameraX may choose the nearest available size
        val targetSize = when (resolution) {
            0 -> Size(320, 240)  // low — suitable for fast gesture detection
            2 -> Size(1280, 720) // high — better for small faces or distant hands
            else -> Size(640, 480) // medium default
        }

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
                    // Resize the surface to match the actual camera resolution CameraX negotiated
                    surfaceTexture.setDefaultBufferSize(
                        request.resolution.width,
                        request.resolution.height
                    )
                    val surface = android.view.Surface(surfaceTexture)
                    // Surface is released in the callback once CameraX is done with it
                    request.provideSurface(surface, ContextCompat.getMainExecutor(context)) {
                        surface.release()
                    }
                }
            }

        val imageAnalysis = ImageAnalysis.Builder()
            .setTargetResolution(targetSize)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888) // avoids per-frame YUV→RGB in ImageConverter
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST) // drops stale frames instead of queuing; keeps inference latency bounded
            .build()
            .also {
                it.setAnalyzer(analysisExecutor, processor)
            }

        provider.unbindAll() // detach any previous session before binding the new one
        provider.bindToLifecycle(
            lifecycleOwner,
            cameraSelector,
            preview,
            imageAnalysis
        )
    }

    // Rebinds the camera to the new facing in place, reusing the existing Flutter texture so the
    // preview never drops. No-op if the camera isn't running or the facing is unchanged.
    fun switchCamera(facing: Int) {
        if (cameraProvider == null || textureEntry == null) return
        if (facing == currentFacing) return
        currentFacing = facing
        // Keep the mirror in sync: front camera frames are mirrored, back camera frames are not.
        frameProcessor?.isFrontCamera = facing == 0
        bindUseCases(facing)
    }

    // Releases both camera and the Flutter texture; call this before dropping the CameraManager reference
    fun release() {
        cameraProvider?.unbindAll()
        textureEntry?.release() // frees the SurfaceTexture so Flutter can reclaim the GL texture slot
        textureEntry = null
        cameraProvider = null
        frameProcessor = null
    }
}

import AVFoundation
import Flutter

// Owns the AVCaptureSession lifecycle and bridges camera frames to Flutter's texture system.
// Frames are delivered to FrameProcessor on the analysis queue, and the latest pixel buffer
// is served to Flutter via the FlutterTexture protocol for preview rendering.
class CameraManager: NSObject {

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var textureId: Int64 = -1
    private weak var textureRegistry: FlutterTextureRegistry?
    private var latestPixelBuffer: CVPixelBuffer? // served to Flutter for preview
    private var frameProcessor: FrameProcessor?
    private var currentFacing: Int = 0 // 0=front, 1=back

    // Creates and starts a camera session, registers a Flutter texture, returns textureId.
    // Throws if camera setup fails (no permission, no device, etc.)
    static func create(
        registrar: FlutterPluginRegistrar,
        facing: Int,
        resolution: Int,
        analysisQueue: DispatchQueue,
        frameProcessor: FrameProcessor,
        completion: (CameraManager) -> Void
    ) throws -> Int64 {
        let manager = CameraManager()
        manager.frameProcessor = frameProcessor
        manager.currentFacing = facing
        manager.textureRegistry = registrar.textures()

        // Register as FlutterTexture — Flutter polls copyPixelBuffer() each frame
        manager.textureId = registrar.textures().register(manager)

        try manager.setupSession(facing: facing, resolution: resolution, analysisQueue: analysisQueue)
        completion(manager)
        return manager.textureId
    }

    private func setupSession(facing: Int, resolution: Int, analysisQueue: DispatchQueue) throws {
        let session = AVCaptureSession()

        // Resolution mapping matches Android: 0=low, 1=medium(640x480), 2=high(720p)
        switch resolution {
        case 0:  session.sessionPreset = .low
        case 2:  session.sessionPreset = .hd1280x720
        default: session.sessionPreset = .vga640x480
        }

        // Select front or back camera
        let position: AVCaptureDevice.Position = facing == 0 ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw NSError(domain: "VisionAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "No camera available for position \(position.rawValue)"])
        }

        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) {
            session.addInput(input)
        }

        // Video output in BGRA (iOS native format); frames delivered on analysis queue
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true // equivalent to STRATEGY_KEEP_ONLY_LATEST
        output.setSampleBufferDelegate(self, queue: analysisQueue)

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        // Mirror front camera output to match Android CameraX behavior
        if let connection = output.connection(with: .video) {
            if connection.isVideoMirroringSupported && facing == 0 {
                connection.isVideoMirrored = true
            }
            // Lock orientation to portrait; rotation handled in ImageConverter if needed
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }

        videoOutput = output
        captureSession = session

        // Start capture on a background thread so it doesn't block the main thread
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    // Switches the active camera in place, reusing the existing capture session and Flutter
    // texture so the preview never drops. No-op if not running or the facing is unchanged.
    // Call off the main thread (e.g. the analysis queue) — session reconfiguration can block.
    func switchCamera(facing: Int) {
        guard let session = captureSession, facing != currentFacing else { return }

        let position: AVCaptureDevice.Position = facing == 0 ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let newInput = try? AVCaptureDeviceInput(device: device) else {
            return // requested camera unavailable; keep the current one
        }

        session.beginConfiguration()
        // Swap the camera input; the video output (and its connection) is preserved
        session.inputs.forEach { session.removeInput($0) }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
        }
        currentFacing = facing
        // Re-apply mirroring + orientation: front is mirrored to match Android, back is not
        if let connection = videoOutput?.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = facing == 0
            }
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }
        session.commitConfiguration()
    }

    func release() {
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
        latestPixelBuffer = nil
        if textureId >= 0 {
            textureRegistry?.unregisterTexture(textureId)
            textureId = -1
        }
        frameProcessor = nil
    }
}

// MARK: - FlutterTexture

extension CameraManager: FlutterTexture {
    // Flutter calls this on the raster thread to get the latest frame for the Texture widget
    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let buffer = latestPixelBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Store for Flutter texture preview
        latestPixelBuffer = pixelBuffer
        textureRegistry?.textureFrameAvailable(textureId)

        // Feed to ML processors
        frameProcessor?.processFrame(pixelBuffer: pixelBuffer, isFrontCamera: currentFacing == 0)
    }
}

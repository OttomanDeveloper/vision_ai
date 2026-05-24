import AVFoundation
import CoreVideo

// Orchestrates hand + face ML processing for each camera frame.
// Called on the analysis queue by CameraManager's AVCaptureVideoDataOutputSampleBufferDelegate.
// Hand processing is async (MediaPipe LIVE_STREAM); face processing is synchronous (ML Kit).
class FrameProcessor {

    let resultAggregator: ResultAggregator
    var handProcessor: HandGestureProcessor?
    var faceProcessor: FaceDetectionProcessor?
    let pixelBufferPool = PixelBufferPool() // shared across processors to reduce allocations
    private var frameCount: Int64 = 0

    init(
        resultAggregator: ResultAggregator,
        handProcessor: HandGestureProcessor?,
        faceProcessor: FaceDetectionProcessor?
    ) {
        self.resultAggregator = resultAggregator
        self.handProcessor = handProcessor
        self.faceProcessor = faceProcessor
    }

    // Called on analysis queue for each camera frame
    func processFrame(pixelBuffer: CVPixelBuffer, isFrontCamera: Bool) {
        let startTime = ProcessInfo.processInfo.systemUptime
        let timestampMs = Int(startTime * 1000)

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        frameCount += 1
        if frameCount % 100 == 0 {
            print("VisionAI.FrameProcessor: Processed \(frameCount) frames")
        }

        // Hand: async — feed frame to MediaPipe, pick up latest result
        if let hp = handProcessor {
            hp.processFrame(pixelBuffer: pixelBuffer, timestampMs: timestampMs)
        }

        // Face: synchronous — blocks until ML Kit returns (same as Android's Tasks.await)
        var faceResult: FaceProcessorResult?
        if let fp = faceProcessor {
            faceResult = fp.processFrame(pixelBuffer: pixelBuffer, pool: pixelBufferPool)
        }

        // Collect hand results (may be from previous frame due to async)
        let handResult = handProcessor?.getLatestResult()
        let handMaps = handResult?.toMapList() ?? []
        let faceMaps = faceResult?.toMapList() ?? []

        let inferenceTimeMs = Int((ProcessInfo.processInfo.systemUptime - startTime) * 1000)

        resultAggregator.emit(
            hands: handMaps,
            faces: faceMaps,
            imageWidth: width,
            imageHeight: height,
            inferenceTimeMs: inferenceTimeMs
        )
    }

    func release() {
        pixelBufferPool.release()
    }
}

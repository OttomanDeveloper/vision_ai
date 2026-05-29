import Flutter
import Foundation
import CoreVideo
import CoreGraphics
import MLKitFaceDetection
import MLKitVision

// Wraps ML Kit FaceDetector with optional TFLite emotion classification.
// Synchronous — blocks the analysis queue until ML Kit returns (same as Android Tasks.await).
// Contour mode and tracking cannot be used simultaneously (ML Kit limitation on both platforms).
class FaceDetectionProcessor {

    private var faceDetector: FaceDetector?
    private var emotionClassifier: EmotionClassifier?
    private var detectEmotion = true
    private var detectContours = false
    var detectLandmarks = false // public so VisionAiPlugin can preserve it across updateFaceConfig
    private var minEmotionConfidence: Float = 0.4

    func initialize(
        emotionModelPath: String,
        detectEmotion: Bool = true,
        detectLandmarks: Bool = false,
        detectContours: Bool = false,
        minFaceSize: Float = 0.1,
        enableTracking: Bool = true,
        minEmotionConfidence: Float = 0.4,
        accurateMode: Bool = false
    ) throws {
        close()

        self.detectEmotion = detectEmotion
        self.detectContours = detectContours
        self.detectLandmarks = detectLandmarks
        self.minEmotionConfidence = minEmotionConfidence

        let options = FaceDetectorOptions()
        options.performanceMode = accurateMode ? .accurate : .fast
        options.classificationMode = .all // always — enables smile + eye-open probabilities
        options.minFaceSize = CGFloat(minFaceSize)

        if detectLandmarks {
            options.landmarkMode = .all
        }
        if detectContours {
            options.contourMode = .all
        }
        // ML Kit: tracking and contour mode can't be used together
        if enableTracking && !detectContours {
            options.isTrackingEnabled = true
        }

        faceDetector = FaceDetector.faceDetector(options: options)

        if detectEmotion {
            emotionClassifier = EmotionClassifier()
            try emotionClassifier!.initialize(modelPath: emotionModelPath)
        }
    }

    // Synchronous face detection — blocks calling thread (analysis queue)
    func processFrame(pixelBuffer: CVPixelBuffer, pool: PixelBufferPool? = nil) -> FaceProcessorResult {
        guard let detector = faceDetector else { return FaceProcessorResult.empty() }

        let visionImage = VisionImage(buffer: createSampleBuffer(from: pixelBuffer))
        visionImage.orientation = .up // buffer is already oriented correctly

        var detectedFaces: [Face] = []
        do {
            detectedFaces = try detector.results(in: visionImage)
        } catch {
            print("VisionAI.FaceDetectionProcessor: Face detection failed: \(error.localizedDescription)")
            return FaceProcessorResult.empty()
        }

        if detectedFaces.isEmpty { return FaceProcessorResult.empty() }

        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)

        var results: [SingleFaceResult] = []

        for face in detectedFaces {
            var emotionResult = EmotionResult.none()

            if detectEmotion, let classifier = emotionClassifier {
                if let croppedFace = cropFace(pixelBuffer: pixelBuffer, boundingBox: face.frame, imageWidth: imageWidth, imageHeight: imageHeight, pool: pool) {
                    emotionResult = classifier.classify(faceImage: croppedFace, pool: pool)
                }
            }

            // Extract landmarks if enabled
            var landmarkPoints: [Double]? = nil
            if detectLandmarks {
                landmarkPoints = extractLandmarks(face: face)
            }

            // Extract contours if enabled
            var contourPoints: [Double]? = nil
            var contourSizes: [Int]? = nil
            if detectContours {
                let extracted = extractContours(face: face)
                contourPoints = extracted.points
                contourSizes = extracted.sizes
            }

            results.append(SingleFaceResult(
                emotion: emotionResult.primaryEmotion,
                emotionConfidence: emotionResult.confidence,
                emotionScores: emotionResult.scores,
                boundingBox: face.frame, // pixel coords in input image space
                headEulerAngleX: Double(face.headEulerAngleX), // pitch: positive=looking up
                headEulerAngleY: Double(face.headEulerAngleY), // yaw: positive=turned right
                headEulerAngleZ: Double(face.headEulerAngleZ), // roll: positive=tilted right
                smilingProbability: face.hasSmilingProbability ? Double(face.smilingProbability) : nil,
                leftEyeOpenProbability: face.hasLeftEyeOpenProbability ? Double(face.leftEyeOpenProbability) : nil,
                rightEyeOpenProbability: face.hasRightEyeOpenProbability ? Double(face.rightEyeOpenProbability) : nil,
                trackingId: face.hasTrackingID ? Int(face.trackingID) : -1,
                landmarkPoints: landmarkPoints,
                contourPoints: contourPoints,
                contourSizes: contourSizes
            ))
        }

        return FaceProcessorResult(faces: results)
    }

    // MARK: - Landmarks (10 points, exact order matching Android)

    private func extractLandmarks(face: Face) -> [Double] {
        let types: [FaceLandmarkType] = [
            .leftEye, .rightEye, .noseBase,
            .mouthLeft, .mouthRight, .mouthBottom,
            .leftEar, .rightEar, .leftCheek, .rightCheek
        ]

        var result = [Double](repeating: -1.0, count: types.count * 2)
        for (i, type) in types.enumerated() {
            if let landmark = face.landmark(ofType: type) {
                result[i * 2] = Double(landmark.position.x)
                result[i * 2 + 1] = Double(landmark.position.y)
            }
            // Missing landmarks keep -1,-1 sentinel
        }
        return result
    }

    // MARK: - Contours (15 types, exact order matching Android)

    private func extractContours(face: Face) -> (points: [Double], sizes: [Int]) {
        let types: [FaceContourType] = [
            .face,
            .leftEyebrowTop, .leftEyebrowBottom,
            .rightEyebrowTop, .rightEyebrowBottom,
            .leftEye, .rightEye,
            .upperLipTop, .upperLipBottom,
            .lowerLipTop, .lowerLipBottom,
            .noseBridge, .noseBottom,
            .leftCheek, .rightCheek
        ]

        var allPoints: [Double] = []
        var sizes = [Int](repeating: 0, count: types.count)

        for (i, type) in types.enumerated() {
            if let contour = face.contour(ofType: type) {
                let points = contour.points
                sizes[i] = points.count
                for pt in points {
                    allPoints.append(Double(pt.x))
                    allPoints.append(Double(pt.y))
                }
            }
            // Missing contour → size stays 0, no points added
        }

        return (points: allPoints, sizes: sizes)
    }

    // MARK: - Face crop (20% padding, clamped to image bounds)

    private func cropFace(pixelBuffer: CVPixelBuffer, boundingBox: CGRect, imageWidth: Int, imageHeight: Int, pool: PixelBufferPool? = nil) -> CGImage? {
        let padX = boundingBox.width * 0.20
        let padY = boundingBox.height * 0.20

        let left = max(0, Int(boundingBox.origin.x - padX))
        let top = max(0, Int(boundingBox.origin.y - padY))
        let right = min(imageWidth, Int(boundingBox.origin.x + boundingBox.width + padX))
        let bottom = min(imageHeight, Int(boundingBox.origin.y + boundingBox.height + padY))

        let cropWidth = right - left
        let cropHeight = bottom - top
        guard cropWidth > 0 && cropHeight > 0 else { return nil }

        // Convert pixel buffer to CGImage, then crop
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = pool?.ciContext ?? CIContext()
        guard let fullImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        let cropRect = CGRect(x: left, y: top, width: cropWidth, height: cropHeight)
        return fullImage.cropping(to: cropRect)
    }

    // MARK: - Helpers

    // Create a VisionImage-compatible sample buffer from a pixel buffer
    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer {
        var sampleBuffer: CMSampleBuffer!
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: CMTime.zero,
            decodeTimeStamp: CMTime.invalid
        )
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription!,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }

    func close() {
        faceDetector = nil
        emotionClassifier?.close()
        emotionClassifier = nil
    }
}

// MARK: - Result types

struct SingleFaceResult {
    let emotion: String
    let emotionConfidence: Double
    let emotionScores: [Double]  // 7 values in Dart label order
    let boundingBox: CGRect      // pixel coords
    let headEulerAngleX: Double  // pitch degrees
    let headEulerAngleY: Double  // yaw degrees
    let headEulerAngleZ: Double  // roll degrees
    let smilingProbability: Double?
    let leftEyeOpenProbability: Double?
    let rightEyeOpenProbability: Double?
    let trackingId: Int          // -1 when tracking disabled
    let landmarkPoints: [Double]?   // 20 values (10 points × x,y)
    let contourPoints: [Double]?    // flat array of x,y pairs
    let contourSizes: [Int]?        // 15 values, points per contour

    func toMap() -> [String: Any?] {
        var map: [String: Any?] = [
            "emotion": emotion,
            "emotionConfidence": emotionConfidence,
            "emotionScores": FlutterStandardTypedData(float64: Data(bytes: emotionScores, count: emotionScores.count * 8)),
            "boundingBox": [boundingBox.origin.x, boundingBox.origin.y,
                           boundingBox.origin.x + boundingBox.width,
                           boundingBox.origin.y + boundingBox.height].map { Double($0) },
            "eulerAngles": [headEulerAngleX, headEulerAngleY, headEulerAngleZ],
            "smilingProbability": smilingProbability,
            "leftEyeOpenProbability": leftEyeOpenProbability,
            "rightEyeOpenProbability": rightEyeOpenProbability,
            "trackingId": trackingId,
        ]

        if let lp = landmarkPoints {
            map["landmarkPoints"] = FlutterStandardTypedData(float64: Data(bytes: lp, count: lp.count * 8))
        } else {
            map["landmarkPoints"] = nil
        }

        if let cp = contourPoints {
            map["contourPoints"] = FlutterStandardTypedData(float64: Data(bytes: cp, count: cp.count * 8))
        } else {
            map["contourPoints"] = nil
        }

        // contourSizes sent as List<Int> (not typed data) — matches Android's .toList()
        map["contourSizes"] = contourSizes

        return map
    }
}

struct FaceProcessorResult {
    let faces: [SingleFaceResult]

    func toMapList() -> [[String: Any?]] {
        return faces.map { $0.toMap() }
    }

    static func empty() -> FaceProcessorResult {
        return FaceProcessorResult(faces: [])
    }
}

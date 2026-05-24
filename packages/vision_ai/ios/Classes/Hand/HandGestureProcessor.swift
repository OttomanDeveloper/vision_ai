import Flutter
import Foundation
import MediaPipeTasksVision
import CoreVideo

// Wraps MediaPipe GestureRecognizer in LIVE_STREAM mode.
// Result arrives async on a MediaPipe internal thread, stored via @Atomic-like pattern.
// getLatestResult() returns then clears — stale results never returned twice.
class HandGestureProcessor {

    private var gestureRecognizer: GestureRecognizer?
    private var customClassifier: CustomGestureClassifier?
    private var allowedGestures: Set<String>?
    private var deniedGestures: Set<String>?
    private var gestureThresholds: [String: Float]?

    // Written by MediaPipe callback thread, read by analysis queue
    private let resultLock = NSLock()
    private var latestResult: HandProcessorResult?

    // Names that are built-in custom gestures (ok + counting); don't set customGestureName for these
    private static let builtInCustomNames: Set<String> = ["ok", "one", "two", "three", "four", "five"]

    func initialize(
        modelPath: String,
        maxHands: Int,
        minDetectionConfidence: Float,
        minPresenceConfidence: Float,
        minTrackingConfidence: Float,
        customGestures: [CustomGestureConfig],
        allowedGestures: Set<String>?,
        deniedGestures: Set<String>?,
        gestureThresholds: [String: Float]?
    ) throws {
        close()

        self.allowedGestures = allowedGestures
        self.deniedGestures = deniedGestures
        self.gestureThresholds = gestureThresholds

        let options = GestureRecognizerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.numHands = maxHands
        options.minHandDetectionConfidence = minDetectionConfidence
        options.minHandPresenceConfidence = minPresenceConfidence
        options.minTrackingConfidence = minTrackingConfidence
        options.runningMode = .liveStream
        options.gestureRecognizerLiveStreamDelegate = self

        gestureRecognizer = try GestureRecognizer(options: options)
        customClassifier = CustomGestureClassifier(customGestures: customGestures)
    }

    // Feed a frame to MediaPipe — non-blocking, result arrives via delegate callback
    func processFrame(pixelBuffer: CVPixelBuffer, timestampMs: Int) {
        guard let recognizer = gestureRecognizer else { return }
        let mpImage = try? MPImage(pixelBuffer: pixelBuffer)
        guard let image = mpImage else { return }
        try? recognizer.recognizeAsync(image: image, timestampInMilliseconds: timestampMs)
    }

    // Returns the latest result and clears it. Returns nil if no new result since last call.
    func getLatestResult() -> HandProcessorResult? {
        resultLock.lock()
        let result = latestResult
        latestResult = nil
        resultLock.unlock()
        return result
    }

    func close() {
        gestureRecognizer = nil
        customClassifier = nil
        resultLock.lock()
        latestResult = nil
        resultLock.unlock()
    }

    // MARK: - Result processing (called on MediaPipe's internal thread)

    private func handleResult(_ result: GestureRecognizerResult, timestampMs: Int) {
        guard !result.landmarks.isEmpty else {
            resultLock.lock()
            latestResult = HandProcessorResult(hands: [])
            resultLock.unlock()
            return
        }

        var hands: [SingleHandResult] = []

        for i in 0..<result.landmarks.count {
            let landmarks = result.landmarks[i]
            let worldLandmarks = result.worldLandmarks[i]
            let handedness = result.handedness[i]

            // Get MediaPipe's gesture classification
            var gestureName: String
            var gestureScore: Double

            if i < result.gestures.count && !result.gestures[i].isEmpty {
                gestureName = result.gestures[i][0].categoryName ?? "None"
                gestureScore = Double(result.gestures[i][0].score)
            } else {
                gestureName = "None"
                gestureScore = 0.0
            }

            var customGestureName: String? = nil

            // Per-gesture filtering: allow/deny lists and per-gesture thresholds.
            // Filtered gestures become "None" so custom gesture fallback still runs.
            if gestureName != "None" {
                if let allowed = allowedGestures, !allowed.contains(gestureName) {
                    gestureName = "None"
                    gestureScore = 0.0
                } else if let denied = deniedGestures, denied.contains(gestureName) {
                    gestureName = "None"
                    gestureScore = 0.0
                } else if let threshold = gestureThresholds?[gestureName], gestureScore < Double(threshold) {
                    gestureName = "None"
                    gestureScore = 0.0
                }
            }

            let isLeft = !handedness.isEmpty &&
                handedness[0].categoryName?.lowercased() == "left"
            let handednessScore = !handedness.isEmpty ? Double(handedness[0].score) : 0.0

            let fingerStates = computeFingerStates(landmarks: landmarks, isLeft: isLeft)

            // When MediaPipe doesn't recognize a built-in gesture, try custom classification
            if gestureName == "None", let classifier = customClassifier {
                if let match = classifier.classify(landmarks: landmarks, fingerStates: fingerStates, isLeft: isLeft) {
                    gestureName = match.gestureName
                    gestureScore = match.confidence
                    if !Self.builtInCustomNames.contains(gestureName) {
                        customGestureName = gestureName
                    }
                }
            }

            // Pack normalized landmarks as flat [x0,y0,z0, x1,y1,z1, ...] stride-3
            var normalizedLandmarks = [Double](repeating: 0, count: 63)
            for j in 0..<min(landmarks.count, 21) {
                normalizedLandmarks[j * 3] = Double(landmarks[j].x)
                normalizedLandmarks[j * 3 + 1] = Double(landmarks[j].y)
                normalizedLandmarks[j * 3 + 2] = Double(landmarks[j].z)
            }

            // Pack world landmarks (meters, relative to hand center)
            var worldLandmarkArray = [Double](repeating: 0, count: 63)
            for j in 0..<min(worldLandmarks.count, 21) {
                worldLandmarkArray[j * 3] = Double(worldLandmarks[j].x)
                worldLandmarkArray[j * 3 + 1] = Double(worldLandmarks[j].y)
                worldLandmarkArray[j * 3 + 2] = Double(worldLandmarks[j].z)
            }

            hands.append(SingleHandResult(
                gestureName: gestureName,
                gestureConfidence: gestureScore,
                customGestureName: customGestureName,
                landmarks: normalizedLandmarks,
                worldLandmarks: worldLandmarkArray,
                isLeftHand: isLeft,
                handednessConfidence: handednessScore,
                fingerStates: fingerStates
            ))
        }

        resultLock.lock()
        latestResult = HandProcessorResult(hands: hands)
        resultLock.unlock()
    }

    // MARK: - Finger state computation (matches Android exactly)

    // Thumb uses X-axis comparison (lateral movement), others use Y-axis (tip above PIP = extended)
    private func computeFingerStates(landmarks: [NormalizedLandmark], isLeft: Bool) -> [Int] {
        guard landmarks.count >= 21 else { return [0, 0, 0, 0, 0] }

        var states = [Int](repeating: 0, count: 5)

        // Thumb: tip(4) vs IP(3) on X axis; handedness flips the comparison
        let thumbTip = landmarks[4]
        let thumbIp = landmarks[3]
        if isLeft {
            states[0] = thumbTip.x > thumbIp.x ? 1 : 0
        } else {
            states[0] = thumbTip.x < thumbIp.x ? 1 : 0
        }

        // Index through pinky: tip.y < pip.y means extended (lower Y = higher on screen)
        states[1] = landmarks[8].y < landmarks[6].y ? 1 : 0   // index: tip(8) vs PIP(6)
        states[2] = landmarks[12].y < landmarks[10].y ? 1 : 0  // middle: tip(12) vs PIP(10)
        states[3] = landmarks[16].y < landmarks[14].y ? 1 : 0  // ring: tip(16) vs PIP(14)
        states[4] = landmarks[20].y < landmarks[18].y ? 1 : 0  // pinky: tip(20) vs PIP(18)

        return states
    }
}

// MARK: - GestureRecognizerLiveStreamDelegate

extension HandGestureProcessor: GestureRecognizerLiveStreamDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: GestureRecognizer,
        didFinishRecognition result: GestureRecognizerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        if let error = error {
            print("VisionAI.HandGestureProcessor: MediaPipe error: \(error.localizedDescription)")
            return
        }
        guard let result = result else { return }
        handleResult(result, timestampMs: timestampInMilliseconds)
    }
}

// MARK: - Result types

struct SingleHandResult {
    let gestureName: String
    let gestureConfidence: Double
    let customGestureName: String?
    let landmarks: [Double]      // 63 values: 21 × (x,y,z) normalized [0,1]
    let worldLandmarks: [Double]  // 63 values: 21 × (x,y,z) in meters
    let isLeftHand: Bool
    let handednessConfidence: Double
    let fingerStates: [Int]      // 5 values: 1=extended, 0=closed

    func toMap() -> [String: Any?] {
        return [
            "gesture": gestureName,
            "gestureConfidence": gestureConfidence,
            "customGestureName": customGestureName,
            "landmarks": FlutterStandardTypedData(float64: Data(bytes: landmarks, count: landmarks.count * 8)),
            "worldLandmarks": FlutterStandardTypedData(float64: Data(bytes: worldLandmarks, count: worldLandmarks.count * 8)),
            "isLeftHand": isLeftHand,
            "handednessConfidence": handednessConfidence,
            "fingerStates": fingerStates,
        ]
    }
}

struct HandProcessorResult {
    let hands: [SingleHandResult]

    func toMapList() -> [[String: Any?]] {
        return hands.map { $0.toMap() }
    }
}

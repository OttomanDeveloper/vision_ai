import Foundation
import MediaPipeTasksVision

// Finger-state rule engine for custom gesture classification.
// Classification priority: OK → counting (1-5) → user-defined.
// Ported from Kotlin CustomGestureClassifier — same thresholds and logic.
class CustomGestureClassifier {

    private let customGestures: [CustomGestureConfig]

    init(customGestures: [CustomGestureConfig]) {
        self.customGestures = customGestures
    }

    func classify(
        landmarks: [NormalizedLandmark],
        fingerStates: [Int],
        isLeft: Bool
    ) -> GestureMatch? {
        // Priority 1: OK gesture
        if let ok = detectOkGesture(landmarks: landmarks, fingerStates: fingerStates) {
            return ok
        }
        // Priority 2: counting 1-5
        if let counting = detectCountingGesture(fingerStates: fingerStates) {
            return counting
        }
        // Priority 3: user-defined gestures (first match wins)
        if let custom = detectCustomGesture(fingerStates: fingerStates) {
            return custom
        }
        return nil
    }

    // MARK: - OK gesture

    // Thumb-index tip distance < 0.06 in normalized image space, with middle+ring+pinky extended
    private func detectOkGesture(landmarks: [NormalizedLandmark], fingerStates: [Int]) -> GestureMatch? {
        guard landmarks.count >= 21 else { return nil }

        let thumbTip = landmarks[4]
        let indexTip = landmarks[8]
        let dx = Double(thumbTip.x - indexTip.x)
        let dy = Double(thumbTip.y - indexTip.y)
        let distance = (dx * dx + dy * dy).squareRoot()

        let threshold = 0.06

        // Middle, ring, pinky must all be extended
        guard distance < threshold,
              fingerStates[2] == 1,  // middle
              fingerStates[3] == 1,  // ring
              fingerStates[4] == 1   // pinky
        else { return nil }

        // Confidence: higher when fingers are closer together; floor at 0.5
        let confidence = max(0.5, min(1.0, 1.0 - distance / threshold))
        return GestureMatch(gestureName: "ok", confidence: confidence)
    }

    // MARK: - Counting gestures (1-5)

    // Exact finger patterns; confidence is fixed per gesture
    private func detectCountingGesture(fingerStates: [Int]) -> GestureMatch? {
        let t = fingerStates[0] == 1  // thumb
        let i = fingerStates[1] == 1  // index
        let m = fingerStates[2] == 1  // middle
        let r = fingerStates[3] == 1  // ring
        let p = fingerStates[4] == 1  // pinky

        // Order matters: check most specific first
        if !t && i && !m && !r && !p { return GestureMatch(gestureName: "one", confidence: 0.85) }
        if !t && i && m && !r && !p  { return GestureMatch(gestureName: "two", confidence: 0.85) }
        if !t && i && m && r && !p   { return GestureMatch(gestureName: "three", confidence: 0.85) }
        if !t && i && m && r && p    { return GestureMatch(gestureName: "four", confidence: 0.85) }
        // Five has lower confidence — MediaPipe usually catches Open_Palm before this
        if t && i && m && r && p     { return GestureMatch(gestureName: "five", confidence: 0.80) }

        return nil
    }

    // MARK: - User-defined custom gestures

    // First match wins; wildcard (-1) skips that finger
    private func detectCustomGesture(fingerStates: [Int]) -> GestureMatch? {
        for gesture in customGestures {
            guard gesture.fingerStates.count == 5 else { continue }

            var matchedCount = 0
            var totalRequired = 0
            var isMatch = true

            for j in 0..<5 {
                let required = gesture.fingerStates[j]
                if required < 0 { continue } // wildcard — skip
                totalRequired += 1
                if fingerStates[j] == required {
                    matchedCount += 1
                } else {
                    isMatch = false
                    break
                }
            }

            // Prevent all-wildcard configs from always matching
            if isMatch && totalRequired > 0 {
                let confidence = max(0.5, min(1.0, Double(matchedCount) / 5.0))
                return GestureMatch(gestureName: gesture.name, confidence: confidence)
            }
        }
        return nil
    }
}

struct GestureMatch {
    let gestureName: String
    let confidence: Double // always >= 0.5
}

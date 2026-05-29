import Flutter
import AVFoundation

// Single plugin entry point mirroring VisionAiPlugin.kt on Android.
// All ML work runs on analysisQueue (serial); results dispatch to main for EventSink.
public class VisionAiPlugin: NSObject, FlutterPlugin {

    private var registrar: FlutterPluginRegistrar
    private var eventSink: FlutterEventSink?

    // Serial queue keeps MediaPipe/ML Kit calls sequential — same role as Android's analysisExecutor
    private let analysisQueue = DispatchQueue(label: "com.visionai.analysis", qos: .userInitiated)

    private var cameraManager: CameraManager?
    private var frameProcessor: FrameProcessor?
    private var resultAggregator: ResultAggregator?
    private var handProcessor: HandGestureProcessor?
    private var faceProcessor: FaceDetectionProcessor?

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let commandChannel = FlutterMethodChannel(
            name: "com.visionai/commands",
            binaryMessenger: registrar.messenger()
        )
        let resultChannel = FlutterEventChannel(
            name: "com.visionai/results",
            binaryMessenger: registrar.messenger()
        )

        let instance = VisionAiPlugin(registrar: registrar)
        commandChannel.setMethodCallHandler(instance.handle)
        resultChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startCamera":
            handleStartCamera(call, result: result)
        case "stopCamera":
            handleStopCamera(result: result)
        case "switchCamera":
            handleSwitchCamera(call, result: result)
        case "updateHandConfig":
            handleUpdateHandConfig(call, result: result)
        case "updateFaceConfig":
            handleUpdateFaceConfig(call, result: result)
        case "dispose":
            handleDispose(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - startCamera

    private func handleStartCamera(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Arguments must be a map", details: nil))
            return
        }

        // Prevent double-start; Flutter can call this before the previous stream finishes tearing down
        if cameraManager != nil {
            result(FlutterError(code: "ALREADY_RUNNING", message: "Camera is already running. Call stopCamera first.", details: nil))
            return
        }

        let facing = args["cameraFacing"] as? Int ?? 0       // 0=front, 1=back
        let resolution = args["resolution"] as? Int ?? 1     // 0=low, 1=medium, 2=high
        let enableHand = args["enableHand"] as? Bool ?? false
        let enableFace = args["enableFace"] as? Bool ?? false
        let maxResults = args["maxResultsPerSecond"] as? Int ?? 0

        do {
            if enableHand {
                let maxHands = args["maxHands"] as? Int ?? 2
                let minDetection = Float(args["minDetectionConfidence"] as? Double ?? 0.5)
                let minPresence = Float(args["minPresenceConfidence"] as? Double ?? 0.5)
                let minTracking = Float(args["minTrackingConfidence"] as? Double ?? 0.5)
                let customGestures = Self.parseCustomGestures(args["customGestures"])
                let filters = Self.parseGestureFilters(args)

                handProcessor = HandGestureProcessor()
                try handProcessor!.initialize(
                    modelPath: assetPath(for: "gesture_recognizer.task"),
                    maxHands: maxHands,
                    minDetectionConfidence: minDetection,
                    minPresenceConfidence: minPresence,
                    minTrackingConfidence: minTracking,
                    customGestures: customGestures,
                    allowedGestures: filters.allowed,
                    deniedGestures: filters.denied,
                    gestureThresholds: filters.thresholds
                )
            }

            if enableFace {
                let detectEmotion = args["detectEmotion"] as? Bool ?? true
                let detectLandmarks = args["detectLandmarks"] as? Bool ?? false
                let detectContours = args["detectContours"] as? Bool ?? false
                let minFaceSize = Float(args["minFaceSize"] as? Double ?? 0.1)
                let enableTracking = args["enableFaceTracking"] as? Bool ?? true
                let minEmotionConf = Float(args["minEmotionConfidence"] as? Double ?? 0.4)
                let accurateMode = args["accurateMode"] as? Bool ?? false

                faceProcessor = FaceDetectionProcessor()
                try faceProcessor!.initialize(
                    emotionModelPath: assetPath(for: "emotion_classifier.tflite"),
                    detectEmotion: detectEmotion,
                    detectLandmarks: detectLandmarks,
                    detectContours: detectContours,
                    minFaceSize: minFaceSize,
                    enableTracking: enableTracking,
                    minEmotionConfidence: minEmotionConf,
                    accurateMode: accurateMode
                )
            }
        } catch {
            // Partial init cleanup
            handProcessor?.close()
            faceProcessor?.close()
            handProcessor = nil
            faceProcessor = nil
            result(FlutterError(code: "INIT_ERROR", message: "Failed to initialize ML models: \(error.localizedDescription)", details: "\(error)"))
            return
        }

        let sinkProvider: () -> FlutterEventSink? = { [weak self] in self?.eventSink }
        resultAggregator = ResultAggregator(sinkProvider: sinkProvider, maxResultsPerSecond: maxResults)

        frameProcessor = FrameProcessor(
            resultAggregator: resultAggregator!,
            handProcessor: handProcessor,
            faceProcessor: faceProcessor
        )

        do {
            let textureId = try CameraManager.create(
                registrar: registrar,
                facing: facing,
                resolution: resolution,
                analysisQueue: analysisQueue,
                frameProcessor: frameProcessor!,
                completion: { [weak self] manager in
                    self?.cameraManager = manager
                }
            )
            result(textureId)
        } catch {
            handProcessor?.close()
            faceProcessor?.close()
            handProcessor = nil
            faceProcessor = nil
            frameProcessor = nil
            resultAggregator = nil
            result(FlutterError(code: "CAMERA_ERROR", message: "Failed to start camera: \(error.localizedDescription)", details: "\(error)"))
        }
    }

    // MARK: - stopCamera

    private func handleStopCamera(result: @escaping FlutterResult) {
        let hp = handProcessor
        let fp = faceProcessor
        let pool = frameProcessor?.pixelBufferPool

        cameraManager?.release()
        cameraManager = nil
        frameProcessor = nil
        resultAggregator = nil
        handProcessor = nil
        faceProcessor = nil

        // Close ML processors on analysis queue to avoid racing with in-flight inference
        analysisQueue.async {
            hp?.close()
            fp?.close()
            pool?.release()
        }
        result(nil)
    }

    // MARK: - switchCamera

    private func handleSwitchCamera(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let facing = (call.arguments as? [String: Any])?["facing"] as? Int ?? 0
        // Reconfigure on the analysis queue so it serializes with frame delivery
        // (CameraManager.currentFacing is read on that queue in captureOutput).
        analysisQueue.async { [weak self] in
            self?.cameraManager?.switchCamera(facing: facing)
        }
        result(nil)
    }

    // MARK: - updateHandConfig

    private func handleUpdateHandConfig(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any], let hp = handProcessor else {
            result(nil)
            return
        }

        let maxHands = args["maxHands"] as? Int ?? 2
        let minDetection = Float(args["minDetectionConfidence"] as? Double ?? 0.5)
        let minPresence = Float(args["minPresenceConfidence"] as? Double ?? 0.5)
        let minTracking = Float(args["minTrackingConfidence"] as? Double ?? 0.5)
        let customGestures = Self.parseCustomGestures(args["customGestures"])
        let filters = Self.parseGestureFilters(args)

        do {
            try hp.initialize(
                modelPath: assetPath(for: "gesture_recognizer.task"),
                maxHands: maxHands,
                minDetectionConfidence: minDetection,
                minPresenceConfidence: minPresence,
                minTrackingConfidence: minTracking,
                customGestures: customGestures,
                allowedGestures: filters.allowed,
                deniedGestures: filters.denied,
                gestureThresholds: filters.thresholds
            )
        } catch {
            // Silent — matches Android behavior of re-init on same thread
        }
        result(nil)
    }

    // MARK: - updateFaceConfig
    // NOTE: detectLandmarks is startCamera-only — preserved here (not read from args), matching
    // Android and the design. Dart does not send the key in updateFaceConfig.

    private func handleUpdateFaceConfig(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any], let fp = faceProcessor else {
            result(nil)
            return
        }

        let detectEmotion = args["detectEmotion"] as? Bool ?? true
        let detectContours = args["detectContours"] as? Bool ?? false
        let minFaceSize = Float(args["minFaceSize"] as? Double ?? 0.1)
        let enableTracking = args["enableFaceTracking"] as? Bool ?? true
        let minEmotionConf = Float(args["minEmotionConfidence"] as? Double ?? 0.4)
        let accurateMode = args["accurateMode"] as? Bool ?? false

        do {
            try fp.initialize(
                emotionModelPath: assetPath(for: "emotion_classifier.tflite"),
                detectEmotion: detectEmotion,
                detectLandmarks: fp.detectLandmarks, // preserve from startCamera
                detectContours: detectContours,
                minFaceSize: minFaceSize,
                enableTracking: enableTracking,
                minEmotionConfidence: minEmotionConf,
                accurateMode: accurateMode
            )
        } catch {
            // Silent
        }
        result(nil)
    }

    // MARK: - dispose

    private func handleDispose(result: @escaping FlutterResult) {
        let hp = handProcessor
        let fp = faceProcessor
        let pool = frameProcessor?.pixelBufferPool

        cameraManager?.release()
        cameraManager = nil
        frameProcessor = nil
        resultAggregator = nil
        handProcessor = nil
        faceProcessor = nil

        analysisQueue.async {
            hp?.close()
            fp?.close()
            pool?.release()
        }
        result(nil)
    }

    // MARK: - Helpers

    // Resolves a file from the plugin's resource bundle (not the main app bundle)
    private func assetPath(for filename: String) -> String {
        let key = registrar.lookupKey(forAsset: "packages/vision_ai/ios/Assets/\(filename)")
        guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
            // Fallback: check the plugin's own resource bundle
            let pluginBundle = Bundle(for: type(of: self))
            if let bundlePath = pluginBundle.path(forResource: "vision_ai_assets", ofType: "bundle"),
               let assetBundle = Bundle(path: bundlePath),
               let assetPath = assetBundle.path(forResource: filename, ofType: nil) {
                return assetPath
            }
            // Last resort: try main bundle directly
            return Bundle.main.path(forResource: filename.components(separatedBy: ".").first,
                                    ofType: filename.components(separatedBy: ".").last) ?? filename
        }
        return path
    }

    // Parse custom gestures from Dart-side List<Map<String, Any>>
    static func parseCustomGestures(_ raw: Any?) -> [CustomGestureConfig] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.compactMap { map in
            guard let name = map["name"] as? String,
                  let states = map["fingerStates"] as? [Int],
                  states.count == 5 else { return nil }
            return CustomGestureConfig(name: name, fingerStates: states)
        }
    }

    // Parse gesture filter config; empty collections treated as nil (no filter)
    static func parseGestureFilters(_ args: [String: Any]) -> GestureFilterConfig {
        var allowed: Set<String>? = nil
        if let list = args["allowedGestures"] as? [String], !list.isEmpty {
            allowed = Set(list)
        }
        var denied: Set<String>? = nil
        if let list = args["deniedGestures"] as? [String], !list.isEmpty {
            denied = Set(list)
        }
        var thresholds: [String: Float]? = nil
        if let map = args["gestureThresholds"] as? [String: Any], !map.isEmpty {
            thresholds = map.mapValues { Float(($0 as? Double) ?? 0) }
        }
        return GestureFilterConfig(allowed: allowed, denied: denied, thresholds: thresholds)
    }
}

// MARK: - FlutterStreamHandler

extension VisionAiPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}

// MARK: - Supporting types

struct CustomGestureConfig {
    let name: String
    let fingerStates: [Int] // 5 elements: 1=extended, 0=closed, -1=wildcard
}

struct GestureFilterConfig {
    let allowed: Set<String>?
    let denied: Set<String>?
    let thresholds: [String: Float]?
}

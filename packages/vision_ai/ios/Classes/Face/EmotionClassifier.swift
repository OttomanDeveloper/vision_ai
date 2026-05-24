import Foundation
import CoreGraphics
import TensorFlowLite

// TFLite emotion classifier — loads emotion_classifier.tflite, resizes face crop,
// runs inference, maps output to FER2013 label order.
// Mirrors Android EmotionClassifier.kt — same labels, same preprocessing, same debug logging.
class EmotionClassifier {

    private var interpreter: Interpreter?
    private var inputWidth = 48
    private var inputHeight = 48
    private var inputChannels = 1 // 1=grayscale, 3=RGB; read from model tensor shape
    private var numClasses = 7

    // FER2013 label order — matches Dart Emotion enum order exactly
    private let labelMap = ["angry", "disgusted", "fearful", "happy", "sad", "surprised", "neutral"]
    // Identity mapping — FER2013 order matches Dart order, no remapping needed
    private let toDartIndex = [0, 1, 2, 3, 4, 5, 6]

    private var debugFrameCount: Int64 = 0

    func initialize(modelPath: String) throws {
        var options = Interpreter.Options()
        options.threadCount = 2 // balances throughput vs battery

        interpreter = try Interpreter(modelPath: modelPath, options: options)
        try interpreter?.allocateTensors()

        // Read actual tensor shapes so we handle non-FER2013 model variants
        if let inputTensor = try? interpreter?.input(at: 0) {
            let shape = inputTensor.shape.dimensions
            if shape.count == 4 {
                inputHeight = shape[1]
                inputWidth = shape[2]
                inputChannels = shape[3]
            }
        }
        if let outputTensor = try? interpreter?.output(at: 0) {
            numClasses = outputTensor.shape.dimensions.last ?? 7
        }

        print("EmotionClassifier: Emotion model loaded: input=\(inputWidth)x\(inputHeight)x\(inputChannels), classes=\(numClasses)")
    }

    // faceBitmap is the cropped+padded face region as CGImage
    func classify(faceImage: CGImage) -> EmotionResult {
        guard let interp = interpreter else { return EmotionResult.none() }

        // Resize to model input dimensions
        guard let resized = resize(image: faceImage, to: CGSize(width: inputWidth, height: inputHeight)) else {
            return EmotionResult.none()
        }

        // Convert to float32 buffer
        let inputData = preprocessFace(image: resized)

        do {
            try interp.copy(inputData, toInputAt: 0)
            try interp.invoke()

            let outputTensor = try interp.output(at: 0)
            let outputData = outputTensor.data
            let probabilities = outputData.withUnsafeBytes { ptr -> [Float] in
                Array(ptr.bindMemory(to: Float.self))
            }

            // Argmax
            var maxIdx = 0
            var maxVal = probabilities[0]
            for i in 1..<min(numClasses, probabilities.count) {
                if probabilities[i] > maxVal {
                    maxVal = probabilities[i]
                    maxIdx = i
                }
            }

            let primaryEmotion = maxIdx < labelMap.count ? labelMap[maxIdx] : "neutral"

            // Debug log every 60 frames
            debugFrameCount += 1
            if debugFrameCount % 60 == 0 {
                let scores = probabilities.prefix(numClasses).enumerated().map { (i, v) in
                    "\(i < labelMap.count ? labelMap[i] : "?")=\(String(format: "%.2f", v))"
                }.joined(separator: ", ")
                print("EmotionClassifier: Emotion scores: [\(scores)] → \(primaryEmotion)")
            }

            // Map to Dart order
            var dartScores = [Double](repeating: 0, count: 7)
            for i in 0..<min(probabilities.count, toDartIndex.count) {
                if toDartIndex[i] < 7 {
                    dartScores[toDartIndex[i]] = Double(probabilities[i])
                }
            }

            return EmotionResult(
                primaryEmotion: primaryEmotion,
                confidence: Double(maxVal),
                scores: dartScores
            )
        } catch {
            print("EmotionClassifier: TFLite inference failed: \(error.localizedDescription)")
            return EmotionResult.none()
        }
    }

    func close() {
        interpreter = nil
    }

    // MARK: - Preprocessing

    // Converts CGImage to float32 Data for TFLite input
    private func preprocessFace(image: CGImage) -> Data {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue // RGBA layout
        ) else {
            return Data(count: width * height * inputChannels * 4)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var floatData = Data(capacity: width * height * inputChannels * 4)

        for i in 0..<(width * height) {
            let offset = i * bytesPerPixel
            let r = Float(pixelData[offset]) / 255.0
            let g = Float(pixelData[offset + 1]) / 255.0
            let b = Float(pixelData[offset + 2]) / 255.0

            if inputChannels == 1 {
                // BT.601 luma weights — matches Android exactly
                let gray = 0.299 * r + 0.587 * g + 0.114 * b
                var value = gray
                floatData.append(Data(bytes: &value, count: 4))
            } else {
                var rv = r; var gv = g; var bv = b
                floatData.append(Data(bytes: &rv, count: 4))
                floatData.append(Data(bytes: &gv, count: 4))
                floatData.append(Data(bytes: &bv, count: 4))
            }
        }

        return floatData
    }

    // Resize CGImage using Core Graphics
    private func resize(image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

// MARK: - Result type

struct EmotionResult {
    let primaryEmotion: String
    let confidence: Double   // [0.0, 1.0]
    let scores: [Double]     // 7 values in Dart label order

    static func none() -> EmotionResult {
        return EmotionResult(primaryEmotion: "none", confidence: 0.0, scores: [Double](repeating: 0, count: 7))
    }
}

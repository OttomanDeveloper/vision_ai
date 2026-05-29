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
    func classify(faceImage: CGImage, pool: PixelBufferPool? = nil) -> EmotionResult {
        guard let interp = interpreter else { return EmotionResult.none() }

        // Resize to model input dimensions
        guard let resized = resize(image: faceImage, to: CGSize(width: inputWidth, height: inputHeight)) else {
            return EmotionResult.none()
        }

        // Convert to float32 buffer (reuses a pooled buffer; must be returned to the pool after use)
        let inputData = preprocessFace(image: resized, pool: pool)
        defer { pool?.returnTfliteInputData(inputData) }

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

    // Converts CGImage to float32 Data for TFLite input.
    // The RGBA scratch buffer and the float output buffer are both borrowed from the pool (fixed
    // model-input size → reused every frame, no per-frame allocation) and filled in place. The float
    // buffer is returned to the caller, which hands it back to the pool after inference.
    private func preprocessFace(image: CGImage, pool: PixelBufferPool? = nil) -> Data {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let pixelCount = width * height
        let rgbaSize = pixelCount * bytesPerPixel
        let floatSize = pixelCount * inputChannels * 4

        // Reusable RGBA scratch buffer for CGContext to render into.
        var pixelData = pool?.borrowPixelArray(size: rgbaSize) ?? [UInt8](repeating: 0, count: rgbaSize)
        defer { pool?.returnPixelArray(pixelData) }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var drewImage = false
        pixelData.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue // RGBA layout
                  ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            drewImage = true
        }
        guard drewImage else { return Data(count: floatSize) }

        // Reusable float32 output buffer, filled in place (replaces per-frame Data.append reallocations).
        var floatData = pool?.borrowTfliteInputData(size: floatSize) ?? Data(count: floatSize)
        floatData.withUnsafeMutableBytes { (rawOut: UnsafeMutableRawBufferPointer) in
            let out = rawOut.bindMemory(to: Float.self)
            pixelData.withUnsafeBytes { (rawIn: UnsafeRawBufferPointer) in
                let px = rawIn.bindMemory(to: UInt8.self)
                for i in 0..<pixelCount {
                    let offset = i * bytesPerPixel
                    let r = Float(px[offset]) / 255.0
                    let g = Float(px[offset + 1]) / 255.0
                    let b = Float(px[offset + 2]) / 255.0
                    if inputChannels == 1 {
                        // BT.601 luma weights — matches Android exactly
                        out[i] = 0.299 * r + 0.587 * g + 0.114 * b
                    } else {
                        out[i * 3] = r
                        out[i * 3 + 1] = g
                        out[i * 3 + 2] = b
                    }
                }
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

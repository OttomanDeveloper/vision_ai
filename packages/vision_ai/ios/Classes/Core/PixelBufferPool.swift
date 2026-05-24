import CoreVideo
import CoreGraphics

// Reusable buffer allocations to reduce per-frame GC pressure.
// iOS equivalent of Android's BitmapPool — same pooling strategy:
// reuse if dimensions match, reallocate if changed.
class PixelBufferPool {

    // Face crop intermediate
    private var faceCropBuffer: CVPixelBuffer?
    private var faceCropWidth = 0
    private var faceCropHeight = 0

    // TFLite input data buffer — reused across inferences
    private var tfliteInputData: Data?
    private var tfliteInputSize = 0

    // Pixel extraction array — reused for CGContext rendering
    private var pixelArray: [UInt8]?
    private var pixelArraySize = 0

    // CIContext is expensive to create — reuse across frames
    let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Face crop buffer

    func getFaceCropBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        if width == faceCropWidth && height == faceCropHeight, let existing = faceCropBuffer {
            return existing
        }

        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let newBuffer = buffer else { return nil }

        faceCropBuffer = newBuffer
        faceCropWidth = width
        faceCropHeight = height
        return newBuffer
    }

    // MARK: - TFLite input data

    func getTfliteInputData(size: Int) -> Data {
        if size == tfliteInputSize, var existing = tfliteInputData {
            // Zero-fill for reuse
            existing.resetBytes(in: 0..<size)
            tfliteInputData = existing
            return existing
        }
        let data = Data(count: size)
        tfliteInputData = data
        tfliteInputSize = size
        return data
    }

    // MARK: - Pixel extraction array

    func getPixelArray(size: Int) -> [UInt8] {
        if size == pixelArraySize, let existing = pixelArray {
            return existing
        }
        let array = [UInt8](repeating: 0, count: size)
        pixelArray = array
        pixelArraySize = size
        return array
    }

    // MARK: - Cleanup

    func release() {
        faceCropBuffer = nil
        faceCropWidth = 0
        faceCropHeight = 0
        tfliteInputData = nil
        tfliteInputSize = 0
        pixelArray = nil
        pixelArraySize = 0
    }
}

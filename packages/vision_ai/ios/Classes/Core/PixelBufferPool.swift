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

    // TFLite input data buffer — reused across inferences (lent via borrow/return)
    private var tfliteInputData: Data?

    // Pixel extraction array — reused for CGContext rendering (lent via borrow/return)
    private var pixelArray: [UInt8]?

    // CIContext is expensive to create — reuse across frames
    let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Face crop buffer (reserved — intentionally unwired)
    // The emotion pipeline crops via CGImage and the face box is a different size every frame, so a
    // fixed CVPixelBuffer pool would rarely hit. Kept per the iOS design for a future fixed-size
    // CVPixelBuffer crop path; the expensive CIContext it would use is already reused above.

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

    // MARK: - TFLite input data (borrow/return)

    // Borrowing drops the pool's own reference so the caller mutates a uniquely-owned buffer —
    // otherwise Swift copy-on-write would copy on every frame and defeat the pooling entirely.
    // The caller fully overwrites the bytes and MUST call returnTfliteInputData() when done (use defer).
    func borrowTfliteInputData(size: Int) -> Data {
        if let existing = tfliteInputData, existing.count == size {
            tfliteInputData = nil // relinquish our reference → no COW when the caller fills it
            return existing
        }
        return Data(count: size)
    }

    func returnTfliteInputData(_ data: Data) {
        tfliteInputData = data
    }

    // MARK: - Pixel extraction array (borrow/return)

    func borrowPixelArray(size: Int) -> [UInt8] {
        if let existing = pixelArray, existing.count == size {
            pixelArray = nil // relinquish our reference → CGContext can draw into it without a COW copy
            return existing
        }
        return [UInt8](repeating: 0, count: size)
    }

    func returnPixelArray(_ array: [UInt8]) {
        pixelArray = array
    }

    // MARK: - Cleanup

    func release() {
        faceCropBuffer = nil
        faceCropWidth = 0
        faceCropHeight = 0
        tfliteInputData = nil
        pixelArray = nil
    }
}

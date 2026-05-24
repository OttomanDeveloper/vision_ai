import Flutter
import Foundation

// Throttles result emission and posts to the Flutter EventSink on the main thread.
// Mirrors Android's ResultAggregator — drop decision happens on the analysis queue
// BEFORE dispatching to main, to avoid unnecessary main thread work.
class ResultAggregator {

    private let sinkProvider: () -> FlutterEventSink?
    private let minIntervalMs: Int64 // 0 = no throttle
    private var lastEmitTime: Int64 = 0 // ms, analysis-thread-only so no sync needed

    init(sinkProvider: @escaping () -> FlutterEventSink?, maxResultsPerSecond: Int) {
        self.sinkProvider = sinkProvider
        self.minIntervalMs = maxResultsPerSecond > 0 ? 1000 / Int64(maxResultsPerSecond) : 0
    }

    func emit(
        hands: [[String: Any?]],
        faces: [[String: Any?]],
        imageWidth: Int,
        imageHeight: Int,
        inferenceTimeMs: Int
    ) {
        let now = Int64(ProcessInfo.processInfo.systemUptime * 1000)

        // Throttle: skip if too soon since last emission
        if minIntervalMs > 0 && (now - lastEmitTime) < minIntervalMs {
            return
        }
        lastEmitTime = now

        let resultMap: [String: Any] = [
            "timestamp": now,
            "inferenceTime": inferenceTimeMs,
            "imageWidth": imageWidth,
            "imageHeight": imageHeight,
            "hands": hands,
            "faces": faces,
        ]

        // EventSink must be called on the main thread
        DispatchQueue.main.async { [weak self] in
            self?.sinkProvider()?(resultMap)
        }
    }
}

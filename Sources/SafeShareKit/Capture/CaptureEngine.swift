import Foundation
import ScreenCaptureKit
import CoreMedia

public protocol CaptureEngineDelegate: AnyObject, Sendable {
    func captureEngine(_ engine: CaptureEngining, didOutput frame: CMSampleBuffer)
    func captureEngine(_ engine: CaptureEngining, didFailWithError error: Error)
    func captureEngineNeedsPrivacyBlanking(_ engine: CaptureEngining)
}

@MainActor
public protocol CaptureEngining: AnyObject {
    var isCapturing: Bool { get }
    func startCapture(display: SCDisplay, filter: SCContentFilter, config: CaptureConfiguration) async throws
    func updateFilter(_ filter: SCContentFilter) async throws
    func updateConfiguration(_ config: CaptureConfiguration) async throws
    func stopCapture() async throws
}

@MainActor
public final class CaptureEngine: NSObject, CaptureEngining, SCStreamOutput, SCStreamDelegate {
    nonisolated(unsafe) public weak var delegate: CaptureEngineDelegate?

    public private(set) var isCapturing: Bool = false

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "com.safeshare.capture.sampleQueue", qos: .userInteractive)

    public override init() {
        super.init()
    }

    public func startCapture(display: SCDisplay, filter: SCContentFilter, config: CaptureConfiguration) async throws {
        if let existing = stream {
            try? await existing.stopCapture()
            self.stream = nil
        }

        let scConfig = config.makeSCStreamConfiguration()
        let newStream = SCStream(filter: filter, configuration: scConfig, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)

        try await newStream.startCapture()
        self.stream = newStream
        self.isCapturing = true
    }

    public func updateFilter(_ filter: SCContentFilter) async throws {
        guard let stream = stream, isCapturing else { return }
        try await stream.updateContentFilter(filter)
    }

    public func updateConfiguration(_ config: CaptureConfiguration) async throws {
        guard let stream = stream, isCapturing else { return }
        let scConfig = config.makeSCStreamConfiguration()
        try await stream.updateConfiguration(scConfig)
    }

    public func stopCapture() async throws {
        guard let stream = stream else { return }
        self.stream = nil
        self.isCapturing = false
        try await stream.stopCapture()
    }

    // MARK: - SCStreamOutput
    public nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        delegate?.captureEngine(self, didOutput: sampleBuffer)
    }

    // MARK: - SCStreamDelegate
    public nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isCapturing = false
            self.stream = nil
            self.delegate?.captureEngine(self, didFailWithError: error)
        }
    }
}

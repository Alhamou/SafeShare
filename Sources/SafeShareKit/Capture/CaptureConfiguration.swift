import Foundation
import CoreMedia
import ScreenCaptureKit

public struct CaptureConfiguration: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var targetFPS: Int
    public var showsCursor: Bool
    public var pixelFormat: OSType
    public var queueDepth: Int

    public init(
        width: Int,
        height: Int,
        targetFPS: Int = 30,
        showsCursor: Bool = true,
        pixelFormat: OSType = kCVPixelFormatType_32BGRA,
        queueDepth: Int = 3
    ) {
        self.width = width
        self.height = height
        self.targetFPS = targetFPS
        self.showsCursor = showsCursor
        self.pixelFormat = pixelFormat
        self.queueDepth = queueDepth
    }

    public func makeSCStreamConfiguration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        config.pixelFormat = pixelFormat
        config.showsCursor = showsCursor
        config.queueDepth = queueDepth
        config.capturesAudio = false
        if #available(macOS 14.0, *) {
            config.captureResolution = .best
        }
        return config
    }
}

import AVFoundation
import AppKit
import SwiftUI

// MARK: - Hardware AVCaptureVideoPreviewLayer Representable

/// An efficient, hardware-accelerated NSViewRepresentable that attaches
/// an `AVCaptureVideoPreviewLayer` directly to an NSView's backing layer.
/// This provides zero-copy preview directly from the capture session.
public struct CameraPreviewView: NSViewRepresentable {

    public let session: AVCaptureSession
    public var gravity: AVLayerVideoGravity

    public init(
        session: AVCaptureSession,
        gravity: AVLayerVideoGravity = .resizeAspectFill
    ) {
        self.session = session
        self.gravity = gravity
    }

    public func makeNSView(context: Context) -> CameraPreviewNSView {
        CameraPreviewNSView(session: session, gravity: gravity)
    }

    public func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.updateGravity(gravity)
    }
}

/// Custom NSView hosting an `AVCaptureVideoPreviewLayer`.
public final class CameraPreviewNSView: NSView {

    private let previewLayer: AVCaptureVideoPreviewLayer

    public init(session: AVCaptureSession, gravity: AVLayerVideoGravity = .resizeAspectFill) {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)

        self.wantsLayer = true
        self.previewLayer.videoGravity = gravity
        self.previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        self.layer = previewLayer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }

    public func updateGravity(_ gravity: AVLayerVideoGravity) {
        if previewLayer.videoGravity != gravity {
            previewLayer.videoGravity = gravity
        }
    }
}

// MARK: - CMSampleBuffer Display Layer Representable

/// An NSViewRepresentable backed by `AVSampleBufferDisplayLayer` that receives
/// streamed `CMSampleBuffer` frames directly from `CameraManager`.
/// Ideal when frames are intercepted, processed (e.g. computer vision, face detection),
/// or filtered before display.
public struct SampleBufferPreviewView: NSViewRepresentable {

    @ObservedObject public var cameraManager: CameraManager
    public var gravity: AVLayerVideoGravity

    public init(
        cameraManager: CameraManager,
        gravity: AVLayerVideoGravity = .resizeAspectFill
    ) {
        self.cameraManager = cameraManager
        self.gravity = gravity
    }

    public func makeNSView(context: Context) -> SampleBufferNSView {
        let view = SampleBufferNSView(gravity: gravity)

        // Stream CMSampleBuffers directly to the display layer on the main thread
        cameraManager.onFrameReceived = { [weak view] sampleBuffer in
            DispatchQueue.main.async {
                view?.enqueue(sampleBuffer)
            }
        }

        return view
    }

    public func updateNSView(_ nsView: SampleBufferNSView, context: Context) {
        nsView.updateGravity(gravity)
    }
}

/// Custom NSView hosting an `AVSampleBufferDisplayLayer` for direct CMSampleBuffer playback.
public final class SampleBufferNSView: NSView, @unchecked Sendable {

    private let displayLayer = AVSampleBufferDisplayLayer()

    public init(gravity: AVLayerVideoGravity = .resizeAspectFill) {
        super.init(frame: .zero)

        self.wantsLayer = true
        self.displayLayer.videoGravity = gravity
        self.displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        self.layer = displayLayer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        displayLayer.frame = bounds
    }

    /// Enqueues a CMSampleBuffer onto the display layer.
    public func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }

    public func updateGravity(_ gravity: AVLayerVideoGravity) {
        if displayLayer.videoGravity != gravity {
            displayLayer.videoGravity = gravity
        }
    }
}

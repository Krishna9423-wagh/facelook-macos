@preconcurrency import AVFoundation
import AppKit
import Combine
import Foundation

// MARK: - Preview Rendering Mode

/// Preview rendering mode selector for demonstration.
public enum PreviewRenderMode: String, CaseIterable, Identifiable, Sendable {
    case hardwarePreviewLayer = "AVCaptureVideoPreviewLayer (Hardware)"
    case sampleBufferLayer = "AVSampleBufferDisplayLayer (CMSampleBuffer)"

    public var id: String { rawValue }
}

// MARK: - CameraManager (MainActor Service for SwiftUI)

/// A clean, modern AVFoundation service class designed for macOS and SwiftUI.
/// Handles webcam permissions (NSCameraUsageDescription), manages the AVCaptureSession,
/// and streams live CMSampleBuffers efficiently to preview layers and Vision pipelines.
@MainActor
public final class CameraManager: ObservableObject {

    // MARK: - Published Properties (Observable by SwiftUI)

    /// Current webcam authorization status.
    @Published public private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined

    /// Indicates whether the capture session is currently running.
    @Published public private(set) var isSessionRunning: Bool = false

    /// Indicates whether hardware configuration or camera switching is currently in progress.
    @Published public private(set) var isConfiguring: Bool = false

    /// List of available video capture devices on the Mac.
    @Published public private(set) var availableCameras: [AVCaptureDevice] = []

    /// Currently selected camera device.
    @Published public private(set) var selectedCamera: AVCaptureDevice?

    /// Human-readable error message if an error occurs.
    @Published public private(set) var errorMessage: String?

    /// Resolution of the video frames being captured.
    @Published public private(set) var frameResolution: CGSize = .zero

    /// Live frame rate (FPS) calculated from incoming sample buffers.
    @Published public private(set) var liveFPS: Double = 0.0

    /// Current preview rendering mode (Hardware preview layer vs CMSampleBuffer display layer).
    @Published public var renderMode: PreviewRenderMode = .hardwarePreviewLayer

    /// Controls whether the live camera stream is actively enabled by the user.
    @Published public var isFeedEnabled: Bool = true

    // MARK: - Internal Session Controller

    /// Thread-safe capture pipeline controller that isolates session operations from MainActor.
    private let captureController = CameraCaptureController()

    // MARK: - Public Accessors

    /// Underlying AVCaptureSession for direct use with `AVCaptureVideoPreviewLayer`.
    public var captureSession: AVCaptureSession {
        captureController.session
    }

    /// Closure callback invoked on every live CMSampleBuffer (received on high-priority video queue).
    public var onFrameReceived: (@Sendable (CMSampleBuffer) -> Void)? {
        get { captureController.onFrameReceived }
        set { captureController.onFrameReceived = newValue }
    }

    // MARK: - Initialization & Teardown

    public init() {
        self.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        refreshAvailableCameras()
        bindControllerCallbacks()
        observeDeviceNotifications()
    }

    deinit {
        captureController.stopSession()
    }

    // MARK: - Permission Handling (NSCameraUsageDescription)

    /// Checks the current authorization status and updates published state.
    @discardableResult
    public func checkAuthorizationStatus() -> AVAuthorizationStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        self.authorizationStatus = status
        return status
    }

    /// Asynchronously requests camera access from macOS.
    ///
    /// Requires `NSCameraUsageDescription` in Info.plist.
    /// If App Sandbox is active, requires `com.apple.security.device.camera` entitlement.
    public func requestCameraPermission() async -> Bool {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if currentStatus == .authorized {
            self.authorizationStatus = .authorized
            startCaptureSession()
            return true
        }

        let granted = await AVCaptureDevice.requestAccess(for: .video)
        self.authorizationStatus = granted ? .authorized : .denied

        if granted {
            startCaptureSession()
        }
        return granted
    }

    /// Opens macOS System Settings directly to Privacy & Security > Camera.
    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Session Controls

    /// Configures the session with default camera (if needed) and starts running on background queue.
    public func startCaptureSession() {
        guard authorizationStatus == .authorized else {
            self.errorMessage = CameraError.permissionDenied.localizedDescription
            return
        }

        self.isConfiguring = true
        self.errorMessage = nil

        let targetDeviceID = (selectedCamera ?? AVCaptureDevice.default(for: .video))?.uniqueID

        captureController.startSession(withDeviceID: targetDeviceID) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConfiguring = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.isSessionRunning = false
                } else {
                    if let targetDeviceID {
                        self.selectedCamera = self.availableCameras.first(where: { $0.uniqueID == targetDeviceID })
                            ?? AVCaptureDevice.default(for: .video)
                    } else {
                        self.selectedCamera = AVCaptureDevice.default(for: .video)
                    }
                    self.isSessionRunning = true
                }
            }
        }
    }

    /// Stops the capture session cleanly on the background queue.
    public func stopCaptureSession() {
        captureController.stopSession { [weak self] in
            Task { @MainActor [weak self] in
                self?.isSessionRunning = false
            }
        }
    }

    /// Switches capture input to a different camera device (e.g. external USB webcam or Continuity Camera).
    public func switchCamera(to device: AVCaptureDevice) {
        self.isConfiguring = true
        let deviceID = device.uniqueID
        captureController.switchCamera(toDeviceID: deviceID) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConfiguring = false
                if let error {
                    self.errorMessage = error.localizedDescription
                } else {
                    self.selectedCamera = device
                }
            }
        }
    }

    // MARK: - Frame Streaming

    /// Creates an `AsyncStream<CMSampleBuffer>` for modern Swift async/await consumers.
    /// Frames are delivered as they arrive; slow consumers will drop old frames (bufferingNewest: 2).
    public func makeFrameStream() -> AsyncStream<CMSampleBuffer> {
        captureController.makeFrameStream()
    }

    // MARK: - Private Setup Helpers

    private func bindControllerCallbacks() {
        captureController.onMetricsUpdated = { [weak self] resolution, fps in
            Task { @MainActor [weak self] in
                self?.frameResolution = resolution
                self?.liveFPS = fps
            }
        }

        captureController.onSessionInterruption = { [weak self] isInterrupted, reason in
            Task { @MainActor [weak self] in
                if isInterrupted {
                    self?.errorMessage = reason
                    self?.isSessionRunning = false
                }
            }
        }
    }

    public func refreshAvailableCameras() {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) {
            deviceTypes.append(.external)
        } else {
            deviceTypes.append(.externalUnknown)
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        self.availableCameras = discovery.devices
        if self.selectedCamera == nil {
            self.selectedCamera = discovery.devices.first
        }
    }

    private func observeDeviceNotifications() {
        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAvailableCameras()
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAvailableCameras()
            }
        }
    }
}

// MARK: - Sendable Conformance for CMSampleBuffer

extension CMSampleBuffer: @unchecked @retroactive Sendable {}


/// Manages the low-level AVCaptureSession, hardware input, video data output,
/// and CMSampleBuffer streaming on dedicated serial queues, fully compliant with Swift 6 concurrency.
final class CameraCaptureController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    /// The underlying capture session.
    let session = AVCaptureSession()

    /// Dedicated serial queue for session configuration, startRunning, and stopRunning.
    private let sessionQueue = DispatchQueue(label: "com.macid.camera.sessionQueue", qos: .userInitiated)

    /// Dedicated serial queue with userInteractive QoS for receiving video sample buffers.
    private let videoOutputQueue = DispatchQueue(label: "com.macid.camera.videoOutputQueue", qos: .userInteractive)

    /// Video data output providing raw CMSampleBuffers.
    private let videoDataOutput = AVCaptureVideoDataOutput()

    /// Active camera input.
    private var currentInput: AVCaptureDeviceInput?

    /// Lock protecting thread-safe closures and stream continuations.
    private let stateLock = NSLock()

    /// Direct frame callback handler.
    var onFrameReceived: (@Sendable (CMSampleBuffer) -> Void)?

    /// UI metrics callback (Resolution, FPS).
    var onMetricsUpdated: (@Sendable (CGSize, Double) -> Void)?

    /// Session interruption callback.
    var onSessionInterruption: (@Sendable (Bool, String?) -> Void)?

    /// Active async stream continuations.
    private var streamContinuations: [UUID: AsyncStream<CMSampleBuffer>.Continuation] = [:]

    // Metrics tracking
    private var frameCount: Int = 0
    private var lastFPSCalculationTime: CFAbsoluteTime = 0

    override init() {
        super.init()
    }

    // MARK: - Session Control (Executed on sessionQueue)

    func startSession(withDeviceID deviceID: String?, completion: @escaping @Sendable (Error?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            let device = deviceID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .video)
            guard let device else {
                completion(CameraError.noCameraAvailable)
                return
            }

            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            // Configure optimal preset
            if self.session.canSetSessionPreset(.hd1280x720) {
                self.session.sessionPreset = .hd1280x720
            } else if self.session.canSetSessionPreset(.high) {
                self.session.sessionPreset = .high
            }

            // Setup input
            do {
                if let existing = self.currentInput {
                    self.session.removeInput(existing)
                }
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else {
                    completion(CameraError.cannotAddInput)
                    return
                }
                self.session.addInput(input)
                self.currentInput = input
            } catch {
                completion(error)
                return
            }

            // Setup output
            if !self.session.outputs.contains(self.videoDataOutput) {
                self.videoDataOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]
                self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
                self.videoDataOutput.setSampleBufferDelegate(self, queue: self.videoOutputQueue)

                guard self.session.canAddOutput(self.videoDataOutput) else {
                    completion(CameraError.cannotAddOutput)
                    return
                }
                self.session.addOutput(self.videoDataOutput)
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            completion(nil)
        }
    }

    func stopSession(completion: (@Sendable () -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            completion?()
        }
    }

    func switchCamera(toDeviceID deviceID: String, completion: @escaping @Sendable (Error?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            guard let device = AVCaptureDevice(uniqueID: deviceID) else {
                completion(CameraError.noCameraAvailable)
                return
            }

            if let existing = self.currentInput {
                self.session.removeInput(existing)
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(newInput) else {
                    completion(CameraError.cannotAddInput)
                    return
                }
                self.session.addInput(newInput)
                self.currentInput = newInput
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    // MARK: - AsyncStream Support

    func makeFrameStream() -> AsyncStream<CMSampleBuffer> {
        let id = UUID()
        return AsyncStream<CMSampleBuffer>(bufferingPolicy: .bufferingNewest(2)) { continuation in
            stateLock.lock()
            streamContinuations[id] = continuation
            stateLock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.stateLock.lock()
                self.streamContinuations.removeValue(forKey: id)
                self.stateLock.unlock()
            }
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 1. Forward to direct closure handler
        onFrameReceived?(sampleBuffer)

        // 2. Broadcast to active AsyncStream consumers
        stateLock.lock()
        for continuation in streamContinuations.values {
            continuation.yield(sampleBuffer)
        }
        stateLock.unlock()

        // 3. Compute frame statistics without stalling the queue
        calculateMetrics(sampleBuffer: sampleBuffer)
    }

    private func calculateMetrics(sampleBuffer: CMSampleBuffer) {
        guard let onMetricsUpdated else { return }

        frameCount += 1
        let now = CFAbsoluteTimeGetCurrent()

        if lastFPSCalculationTime == 0 {
            lastFPSCalculationTime = now
            return
        }

        let elapsed = now - lastFPSCalculationTime
        if elapsed >= 0.5 { // Update metrics every 500ms
            let fps = Double(frameCount) / elapsed
            frameCount = 0
            lastFPSCalculationTime = now

            if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let width = CVPixelBufferGetWidth(imageBuffer)
                let height = CVPixelBufferGetHeight(imageBuffer)
                let size = CGSize(width: width, height: height)
                onMetricsUpdated(size, fps)
            }
        }
    }
}

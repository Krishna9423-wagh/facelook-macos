import AVFoundation
import CoreImage
import Foundation
@preconcurrency import Vision

// MARK: - FaceDetectionManager (MainActor ObservableObject)

/// High-level service managing asynchronous face detection, facial landmarks tracking,
/// and blink-based anti-spoofing liveness verification using Apple's Vision framework.
@MainActor
public final class FaceDetectionManager: ObservableObject {

    // MARK: - Published State

    /// Currently detected faces from the latest frame.
    @Published public private(set) var detectedFaces: [DetectedFace] = []

    /// Total count of detected faces in the latest frame.
    @Published public private(set) var faceCount: Int = 0

    /// Execution time for the last Vision inference pass in milliseconds.
    @Published public private(set) var inferenceTimeMs: Double = 0.0

    /// Master toggle for face detection.
    @Published public var isDetectionEnabled: Bool = true

    /// Toggle for extracting and rendering full 2D facial landmarks mesh.
    @Published public var detectLandmarks: Bool = true

    /// Whether horizontal mirroring is applied (matching front-facing webcam preview).
    @Published public var isMirrored: Bool = true

    /// Count of natural eye blinks detected (used for anti-spoofing liveness verification).
    @Published public private(set) var blinkCount: Int = 0

    /// True if at least one natural blink has been confirmed, proving a live human presence.
    @Published public private(set) var isLivenessVerified: Bool = false

    /// Real-time average Eye Aspect Ratio (EAR).
    @Published public private(set) var currentEAR: Float = 0.0

    // MARK: - Engine & Lifecycle

    /// Thread-safe background inference engine.
    private let engine = VisionDetectionEngine()

    /// Background task consuming the frame stream.
    private var streamTask: Task<Void, Never>?

    // Blink detection state tracking
    private var isEyeClosedState: Bool = false
    private let blinkThresholdClosed: Float = 0.20
    private let blinkThresholdOpen: Float = 0.25

    public init() {
        bindEngineCallbacks()
    }

    deinit {
        streamTask?.cancel()
    }

    // MARK: - Public Controls

    /// Connects to CameraManager's frame stream and initiates asynchronous face detection.
    public func startDetection(cameraManager: CameraManager) {
        stopDetection()

        let stream = cameraManager.makeFrameStream()
        let engine = self.engine

        streamTask = Task.detached(priority: .userInitiated) { [weak self] in
            for await sampleBuffer in stream {
                if Task.isCancelled { break }
                let useLandmarks = await self?.detectLandmarks ?? true
                engine.processFrame(sampleBuffer, useLandmarks: useLandmarks)
            }
        }
    }

    /// Stops the detection stream and clears currently displayed bounding boxes.
    public func stopDetection() {
        streamTask?.cancel()
        streamTask = nil
        self.detectedFaces = []
        self.faceCount = 0
    }

    /// Resets the blink counter and liveness verification status.
    public func resetLiveness() {
        self.blinkCount = 0
        self.isLivenessVerified = false
        self.isEyeClosedState = false
    }

    private func bindEngineCallbacks() {
        engine.onFacesDetected = { [weak self] faces, latency in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isDetectionEnabled else {
                    if !self.detectedFaces.isEmpty {
                        self.detectedFaces = []
                        self.faceCount = 0
                    }
                    return
                }
                self.detectedFaces = faces
                self.faceCount = faces.count
                self.inferenceTimeMs = latency

                // Track blinks for liveness verification
                if let primaryFace = faces.first, let ear = primaryFace.eyeAspectRatio {
                    self.currentEAR = ear
                    self.evaluateBlink(ear: ear)
                }
            }
        }
    }

    private func evaluateBlink(ear: Float) {
        if ear < blinkThresholdClosed {
            isEyeClosedState = true
        } else if ear > blinkThresholdOpen && isEyeClosedState {
            isEyeClosedState = false
            blinkCount += 1
            isLivenessVerified = true
        }
    }
}

// MARK: - VisionDetectionEngine (Background Queue Worker)

/// Dedicated thread-safe worker executing Vision requests on a background queue.
final class VisionDetectionEngine: @unchecked Sendable {

    private let visionQueue = DispatchQueue(label: "com.macid.vision.processingQueue", qos: .userInitiated)
    private let busyLock = NSLock()
    private var isBusyProcessing = false

    private let rectanglesRequest = VNDetectFaceRectanglesRequest()
    private let landmarksRequest = VNDetectFaceLandmarksRequest()

    var onFacesDetected: (@Sendable ([DetectedFace], Double) -> Void)?

    func processFrame(_ sampleBuffer: CMSampleBuffer, useLandmarks: Bool) {
        busyLock.lock()
        if isBusyProcessing {
            busyLock.unlock()
            return
        }
        isBusyProcessing = true
        busyLock.unlock()

        visionQueue.async { [weak self] in
            guard let self else { return }
            defer {
                self.busyLock.lock()
                self.isBusyProcessing = false
                self.busyLock.unlock()
            }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }

            let startTime = CFAbsoluteTimeGetCurrent()

            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .up,
                options: [:]
            )

            do {
                if useLandmarks {
                    try handler.perform([self.landmarksRequest])
                    let observations = self.landmarksRequest.results ?? []
                    let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                    let faces = observations.map { Self.createDetectedFace(from: $0) }
                    self.onFacesDetected?(faces, latency)
                } else {
                    try handler.perform([self.rectanglesRequest])
                    let observations = self.rectanglesRequest.results ?? []
                    let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                    let faces = observations.map { obs in
                        DetectedFace(
                            boundingBox: obs.boundingBox,
                            confidence: obs.confidence,
                            roll: obs.roll?.doubleValue,
                            yaw: obs.yaw?.doubleValue
                        )
                    }
                    self.onFacesDetected?(faces, latency)
                }
            } catch {
                self.onFacesDetected?([], 0.0)
            }
        }
    }

    private static func createDetectedFace(from obs: VNFaceObservation) -> DetectedFace {
        var landmarksData: FaceLandmarksData? = nil
        var ear: Float? = nil

        if let landmarks2D = obs.landmarks {
            let leftEye = landmarks2D.leftEye?.normalizedPoints ?? []
            let rightEye = landmarks2D.rightEye?.normalizedPoints ?? []
            let leftEyebrow = landmarks2D.leftEyebrow?.normalizedPoints ?? []
            let rightEyebrow = landmarks2D.rightEyebrow?.normalizedPoints ?? []
            let nose = (landmarks2D.nose?.normalizedPoints ?? []) + (landmarks2D.noseCrest?.normalizedPoints ?? [])
            let outerLips = landmarks2D.outerLips?.normalizedPoints ?? []
            let faceContour = landmarks2D.faceContour?.normalizedPoints ?? []

            landmarksData = FaceLandmarksData(
                leftEye: leftEye,
                rightEye: rightEye,
                leftEyebrow: leftEyebrow,
                rightEyebrow: rightEyebrow,
                nose: nose,
                outerLips: outerLips,
                faceContour: faceContour
            )

            // Calculate Eye Aspect Ratio for blink detection
            let earLeft = calculateEAR(eyePoints: leftEye)
            let earRight = calculateEAR(eyePoints: rightEye)
            if earLeft > 0 && earRight > 0 {
                ear = (earLeft + earRight) / 2.0
            } else if earLeft > 0 {
                ear = earLeft
            } else if earRight > 0 {
                ear = earRight
            }
        }

        return DetectedFace(
            boundingBox: obs.boundingBox,
            confidence: obs.confidence,
            roll: obs.roll?.doubleValue,
            yaw: obs.yaw?.doubleValue,
            landmarks: landmarksData,
            eyeAspectRatio: ear
        )
    }

    /// Computes the Eye Aspect Ratio (EAR) from 6 landmark points around an eye.
    private static func calculateEAR(eyePoints: [CGPoint]) -> Float {
        guard eyePoints.count >= 6 else { return 0.0 }
        let p0 = eyePoints[0] // outer corner
        let p1 = eyePoints[1] // upper lid 1
        let p2 = eyePoints[2] // upper lid 2
        let p3 = eyePoints[3] // inner corner
        let p4 = eyePoints[4] // lower lid 2
        let p5 = eyePoints[5] // lower lid 1

        func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = a.x - b.x
            let dy = a.y - b.y
            return sqrt(dx * dx + dy * dy)
        }

        let v1 = dist(p1, p5)
        let v2 = dist(p2, p4)
        let h = dist(p0, p3)
        guard h > 0 else { return 0.0 }

        return Float((v1 + v2) / (2.0 * h))
    }
}

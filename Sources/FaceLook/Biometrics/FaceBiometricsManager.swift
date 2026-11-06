import Accelerate
import AVFoundation
import CoreImage
import Foundation
@preconcurrency import Vision

// MARK: - Verification Status

/// Represents the real-time biometric verification state.
public enum BiometricVerificationStatus: Equatable, Sendable {
    case notEnrolled
    case searching
    case noFaceDetected
    case verified(similarity: Float)
    case notRecognized(similarity: Float)
    case enrolling(progress: Double)

    public var isVerified: Bool {
        if case .verified = self { return true }
        return false
    }

    public var title: String {
        switch self {
        case .notEnrolled:
            return "No Face Enrolled"
        case .searching:
            return "Scanning..."
        case .noFaceDetected:
            return "Face Not Detected"
        case .verified(let sim):
            return String(format: "Verified (%.1f%% Match)", sim * 100)
        case .notRecognized(let sim):
            return String(format: "Not Recognized (%.1f%% Match)", sim * 100)
        case .enrolling(let progress):
            return String(format: "Enrolling (%.0f%%)", progress * 100)
        }
    }
}

// MARK: - FaceBiometricsManager (MainActor Observable)

/// Coordinates face biometric enrollment, feature print generation via Vision,
/// secure Keychain storage, and real-time cosine similarity verification.
@MainActor
public final class FaceBiometricsManager: ObservableObject {

    // MARK: - Published Properties

    /// Current verification state.
    @Published public private(set) var verificationStatus: BiometricVerificationStatus = .notEnrolled

    /// Cosine similarity score between the live face and enrolled reference (0.0 ... 1.0).
    @Published public private(set) var currentSimilarity: Float = 0.0

    /// True if an enrolled face reference vector is present in Keychain.
    @Published public private(set) var isFaceEnrolled: Bool = false

    /// Similarity threshold above which a face is considered a verified match.
    @Published public var matchThreshold: Float = 0.65

    /// Status message or error description.
    @Published public private(set) var statusMessage: String = ""

    // MARK: - Internal Dependencies

    private let storage: KeychainBiometricsStorage
    private let engine = BiometricsInferenceEngine()

    /// In-memory cache of the enrolled reference vector for low-latency live comparison.
    private var enrolledEmbedding: [Float]?

    // Multi-frame enrollment collection
    private var enrollmentSamples: [[Float]] = []
    private let targetEnrollmentSamples = 3
    private var isEnrollingActive = false

    /// Background task consuming frame stream for biometrics.
    private var streamTask: Task<Void, Never>?

    public init(storage: KeychainBiometricsStorage = .shared) {
        self.storage = storage
        self.loadStoredEmbedding()
        self.bindEngineCallbacks()
    }

    deinit {
        streamTask?.cancel()
    }

    // MARK: - Stream Processing

    /// Subscribes to CameraManager's frame stream and pairs frames with Vision face detections.
    public func startProcessing(cameraManager: CameraManager, faceDetector: FaceDetectionManager) {
        stopProcessing()
        let stream = cameraManager.makeFrameStream()

        streamTask = Task.detached(priority: .userInitiated) { [weak self] in
            for await sampleBuffer in stream {
                guard let self else { break }
                if Task.isCancelled { break }

                let primaryBox = await faceDetector.detectedFaces.first?.boundingBox
                await self.processFrame(sampleBuffer, primaryFaceBox: primaryBox)
            }
        }
    }

    /// Stops stream processing.
    public func stopProcessing() {
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: - Enrollment Workflow

    /// Starts a multi-frame enrollment session.
    public func startEnrollment() {
        self.enrollmentSamples.removeAll()
        self.isEnrollingActive = true
        self.verificationStatus = .enrolling(progress: 0.0)
        self.statusMessage = "Position your face in the camera to enroll..."
    }

    /// Cancels active enrollment.
    public func cancelEnrollment() {
        self.isEnrollingActive = false
        self.enrollmentSamples.removeAll()
        self.updateStatusAfterEnrollmentChange()
    }

    /// Clears any enrolled face from Keychain and resets verification state.
    public func clearEnrolledFace() {
        storage.deleteEmbedding()
        self.enrolledEmbedding = nil
        self.isFaceEnrolled = false
        self.currentSimilarity = 0.0
        self.verificationStatus = .notEnrolled
        self.statusMessage = "Enrolled face removed."
    }

    // MARK: - Live Frame Processing

    /// Evaluates a live video frame against the enrolled biometric profile.
    public func processFrame(
        _ sampleBuffer: CMSampleBuffer,
        primaryFaceBox: CGRect?
    ) {
        let reference = self.enrolledEmbedding
        let isEnrolling = self.isEnrollingActive

        engine.processFrame(
            sampleBuffer,
            faceBox: primaryFaceBox,
            referenceEmbedding: reference,
            isEnrolling: isEnrolling
        )
    }

    // MARK: - Engine Callbacks

    private func bindEngineCallbacks() {
        engine.onFeatureVectorExtracted = { [weak self] vector in
            Task { @MainActor [weak self] in
                self?.handleEnrollmentSample(vector)
            }
        }

        engine.onVerificationResult = { [weak self] similarity in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentSimilarity = similarity

                if similarity >= self.matchThreshold {
                    self.verificationStatus = .verified(similarity: similarity)
                    self.statusMessage = "Authenticated: Face identity confirmed."
                } else {
                    self.verificationStatus = .notRecognized(similarity: similarity)
                    self.statusMessage = "Access Denied: Unrecognized face."
                }
            }
        }

        engine.onNoFaceDetected = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isFaceEnrolled && !self.isEnrollingActive {
                    self.verificationStatus = .noFaceDetected
                }
            }
        }
    }

    private func handleEnrollmentSample(_ vector: [Float]) {
        guard isEnrollingActive else { return }

        enrollmentSamples.append(vector)
        let progress = Double(enrollmentSamples.count) / Double(targetEnrollmentSamples)
        self.verificationStatus = .enrolling(progress: progress)

        if enrollmentSamples.count >= targetEnrollmentSamples {
            // Average accumulated samples for a robust reference vector
            let averaged = BiometricsInferenceEngine.averageAndNormalizeVectors(enrollmentSamples)
            if storage.saveEmbedding(averaged) {
                self.enrolledEmbedding = averaged
                self.isFaceEnrolled = true
                self.isEnrollingActive = false
                self.enrollmentSamples.removeAll()
                self.verificationStatus = .verified(similarity: 1.0)
                self.statusMessage = "Face enrolled successfully and stored in Keychain."
            } else {
                self.statusMessage = "Failed to store face embedding in Keychain."
                self.isEnrollingActive = false
            }
        }
    }

    private func loadStoredEmbedding() {
        if let embedding = storage.loadEmbedding() {
            self.enrolledEmbedding = embedding
            self.isFaceEnrolled = true
            self.verificationStatus = .searching
            self.statusMessage = "Enrolled face loaded from Keychain."
        } else {
            self.enrolledEmbedding = nil
            self.isFaceEnrolled = false
            self.verificationStatus = .notEnrolled
            self.statusMessage = "No enrolled face in Keychain."
        }
    }

    private func updateStatusAfterEnrollmentChange() {
        if isFaceEnrolled {
            self.verificationStatus = .searching
        } else {
            self.verificationStatus = .notEnrolled
        }
    }
}

// MARK: - BiometricsInferenceEngine (Background Queue Worker)

/// Dedicated thread-safe worker for extracting feature prints and computing cosine similarity.
final class BiometricsInferenceEngine: @unchecked Sendable {

    private let biometricsQueue = DispatchQueue(label: "com.macid.biometricsQueue", qos: .userInitiated)
    private let inferenceLock = NSLock()
    private var isBusyEvaluating = false

    var onFeatureVectorExtracted: (@Sendable ([Float]) -> Void)?
    var onVerificationResult: (@Sendable (Float) -> Void)?
    var onNoFaceDetected: (@Sendable () -> Void)?

    func processFrame(
        _ sampleBuffer: CMSampleBuffer,
        faceBox: CGRect?,
        referenceEmbedding: [Float]?,
        isEnrolling: Bool
    ) {
        inferenceLock.lock()
        if isBusyEvaluating {
            inferenceLock.unlock()
            return
        }
        isBusyEvaluating = true
        inferenceLock.unlock()

        biometricsQueue.async { [weak self] in
            guard let self else { return }
            defer {
                self.inferenceLock.lock()
                self.isBusyEvaluating = false
                self.inferenceLock.unlock()
            }

            guard let faceBox else {
                self.onNoFaceDetected?()
                return
            }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }

            guard let liveVector = Self.extractFeaturePrintVector(from: pixelBuffer, faceBox: faceBox) else {
                return
            }

            if isEnrolling {
                self.onFeatureVectorExtracted?(liveVector)
                return
            }

            guard let reference = referenceEmbedding else {
                return
            }

            let similarity = Self.calculateCosineSimilarity(liveVector, reference)
            self.onVerificationResult?(similarity)
        }
    }

    // MARK: - Feature Vector Extraction (Vision)

    /// Extracts a normalized facial feature vector using `VNGenerateImageFeaturePrintRequest`.
    public static func extractFeaturePrintVector(
        from pixelBuffer: CVPixelBuffer,
        faceBox: CGRect?
    ) -> [Float]? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let targetImage: CIImage

        if let faceBox {
            // Convert Vision normalized coordinates (bottom-left) to pixel coordinates
            let pixelBox = CGRect(
                x: faceBox.origin.x * width,
                y: faceBox.origin.y * height,
                width: faceBox.size.width * width,
                height: faceBox.size.height * height
            )

            // Add 15% padding around the face bounding box
            let padded = pixelBox.insetBy(dx: -pixelBox.width * 0.15, dy: -pixelBox.height * 0.15)
            let clamped = padded.intersection(CGRect(x: 0, y: 0, width: width, height: height))
            targetImage = ciImage.cropped(to: clamped)
        } else {
            targetImage = ciImage
        }

        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(ciImage: targetImage, options: [:])

        do {
            try handler.perform([request])
            guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                return nil
            }

            let count = observation.elementCount
            guard count > 0 else { return nil }

            var floats = [Float](repeating: 0, count: count)
            _ = floats.withUnsafeMutableBytes { ptr in
                observation.data.copyBytes(to: ptr)
            }

            // Normalize vector to unit length
            return normalizeVector(floats)
        } catch {
            return nil
        }
    }

    // MARK: - Vector Mathematics (Accelerate / vDSP)

    /// Calculates the cosine similarity between two float vectors using Accelerate vDSP.
    /// Returns a value between 0.0 and 1.0.
    public static func calculateCosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        let count = vDSP_Length(a.count)

        var dotProduct: Float = 0.0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, count)

        var normA: Float = 0.0
        vDSP_svesq(a, 1, &normA, count)

        var normB: Float = 0.0
        vDSP_svesq(b, 1, &normB, count)

        let denominator = sqrt(normA * normB)
        guard denominator > 0 else { return 0.0 }

        let similarity = dotProduct / denominator
        return max(0.0, min(1.0, similarity))
    }

    /// Normalizes a vector to unit length (L2 norm = 1.0).
    public static func normalizeVector(_ vector: [Float]) -> [Float] {
        guard !vector.isEmpty else { return vector }
        let count = vDSP_Length(vector.count)

        var sumSquares: Float = 0.0
        vDSP_svesq(vector, 1, &sumSquares, count)

        let magnitude = sqrt(sumSquares)
        guard magnitude > 0 else { return vector }

        var scale = 1.0 / magnitude
        var result = [Float](repeating: 0, count: vector.count)
        vDSP_vsmul(vector, 1, &scale, &result, 1, count)
        return result
    }

    /// Averages an array of vectors element-wise and normalizes the result.
    public static func averageAndNormalizeVectors(_ vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first, !first.isEmpty else { return [] }
        let vectorLength = first.count
        var accumulator = [Float](repeating: 0.0, count: vectorLength)

        for vector in vectors {
            guard vector.count == vectorLength else { continue }
            vDSP_vadd(accumulator, 1, vector, 1, &accumulator, 1, vDSP_Length(vectorLength))
        }

        var scale = 1.0 / Float(vectors.count)
        vDSP_vsmul(accumulator, 1, &scale, &accumulator, 1, vDSP_Length(vectorLength))
        return normalizeVector(accumulator)
    }
}

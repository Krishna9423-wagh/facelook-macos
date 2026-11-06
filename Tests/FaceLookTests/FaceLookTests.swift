#if canImport(XCTest)
import XCTest
import AVFoundation
@testable import FaceLook

final class FaceLookTests: XCTestCase {

    // MARK: - CameraManager Tests

    @MainActor
    func testCameraManagerInitialization() {
        let manager = CameraManager()

        XCTAssertFalse(manager.isSessionRunning, "Session should not be running immediately upon initialization.")
        XCTAssertFalse(manager.isConfiguring, "Manager should not be configuring immediately upon initialization.")
        XCTAssertEqual(manager.frameResolution, .zero, "Frame resolution should be zero initially.")
        XCTAssertEqual(manager.liveFPS, 0.0, "Live FPS should be 0.0 initially.")
        XCTAssertNotNil(manager.captureSession, "Capture session must be non-nil.")
        XCTAssertEqual(manager.renderMode, .hardwarePreviewLayer, "Default render mode should be hardware preview layer.")
    }

    @MainActor
    func testCameraErrorDescriptions() {
        let errors: [CameraError] = [
            .permissionDenied,
            .permissionRestricted,
            .noCameraAvailable,
            .cannotAddInput,
            .cannotAddOutput,
            .configurationFailed("Test configuration error")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error description should not be nil for \(error).")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty.")
        }
    }

    @MainActor
    func testFrameStreamCreationAndTermination() async {
        let manager = CameraManager()
        let stream = manager.makeFrameStream()

        let consumerTask = Task {
            for await _ in stream {
                break
            }
        }

        consumerTask.cancel()
        _ = await consumerTask.result
    }

    // MARK: - Vision Model Tests

    @MainActor
    func testFaceDetectionManagerInitialization() {
        let detector = FaceDetectionManager()
        XCTAssertTrue(detector.detectedFaces.isEmpty, "Detected faces should be empty initially.")
        XCTAssertEqual(detector.faceCount, 0, "Face count should be 0 initially.")
        XCTAssertTrue(detector.isDetectionEnabled, "Detection should be enabled by default.")
        XCTAssertTrue(detector.isMirrored, "Mirroring should be enabled by default for webcam.")
    }

    func testDetectedFaceModel() {
        let box = CGRect(x: 0.25, y: 0.35, width: 0.5, height: 0.5)
        let face = DetectedFace(boundingBox: box, confidence: 0.95, roll: 0.05, yaw: -0.1)

        XCTAssertEqual(face.boundingBox, box)
        XCTAssertEqual(face.confidence, 0.95)
        XCTAssertEqual(face.roll, 0.05)
        XCTAssertEqual(face.yaw, -0.1)
    }

    // MARK: - Biometrics & Cosine Similarity Tests

    func testCosineSimilarityIdenticalVectors() {
        let v1: [Float] = [1.0, 2.0, 3.0, 4.0]
        let v2: [Float] = [1.0, 2.0, 3.0, 4.0]

        let sim = BiometricsInferenceEngine.calculateCosineSimilarity(v1, v2)
        XCTAssertEqual(sim, 1.0, accuracy: 0.0001, "Cosine similarity of identical vectors must be 1.0")
    }

    func testCosineSimilarityOrthogonalVectors() {
        let v1: [Float] = [1.0, 0.0, 0.0]
        let v2: [Float] = [0.0, 1.0, 0.0]

        let sim = BiometricsInferenceEngine.calculateCosineSimilarity(v1, v2)
        XCTAssertEqual(sim, 0.0, accuracy: 0.0001, "Cosine similarity of orthogonal vectors must be 0.0")
    }

    func testVectorNormalization() {
        let v: [Float] = [3.0, 4.0]
        let normalized = BiometricsInferenceEngine.normalizeVector(v)

        XCTAssertEqual(normalized[0], 0.6, accuracy: 0.0001)
        XCTAssertEqual(normalized[1], 0.8, accuracy: 0.0001)

        // Compute L2 norm of output
        let norm = sqrt(normalized[0] * normalized[0] + normalized[1] * normalized[1])
        XCTAssertEqual(norm, 1.0, accuracy: 0.0001, "Normalized vector length must be 1.0")
    }

    func testKeychainStorageOperations() {
        let storage = KeychainBiometricsStorage(service: "com.macid.facelook.testService")
        let testAccount = "test_user_face"
        let testVector: [Float] = [0.123, 0.456, 0.789, 0.987]

        // 1. Delete prior test state
        storage.deleteEmbedding(for: testAccount)

        // 2. Save
        let saved = storage.saveEmbedding(testVector, for: testAccount)
        XCTAssertTrue(saved, "Failed to save embedding to Keychain.")
        XCTAssertTrue(storage.isEnrolled(for: testAccount), "isEnrolled should be true after saving.")

        // 3. Load
        let loaded = storage.loadEmbedding(for: testAccount)
        XCTAssertNotNil(loaded, "Failed to load saved embedding from Keychain.")
        XCTAssertEqual(loaded?.count, testVector.count)
        if let loaded {
            for i in 0..<testVector.count {
                XCTAssertEqual(loaded[i], testVector[i], accuracy: 0.0001)
            }
        }

        // 4. Delete
        let deleted = storage.deleteEmbedding(for: testAccount)
        XCTAssertTrue(deleted, "Failed to delete embedding from Keychain.")
        XCTAssertFalse(storage.isEnrolled(for: testAccount), "isEnrolled should be false after deletion.")
    }

    @MainActor
    func testFaceBiometricsManagerInitialization() {
        let storage = KeychainBiometricsStorage(service: "com.macid.facelook.testService")
        storage.deleteEmbedding()

        let manager = FaceBiometricsManager(storage: storage)
        XCTAssertFalse(manager.isFaceEnrolled)
        XCTAssertEqual(manager.verificationStatus, .notEnrolled)
        XCTAssertEqual(manager.matchThreshold, 0.65)
    }

    // MARK: - ScreenWakeUnlockManager Tests

    @MainActor
    func testScreenWakeUnlockManagerInitialization() {
        let camera = CameraManager()
        let vision = FaceDetectionManager()
        let biometrics = FaceBiometricsManager()

        let wakeManager = ScreenWakeUnlockManager(
            cameraManager: camera,
            faceDetector: vision,
            biometricsManager: biometrics
        )

        XCTAssertTrue(wakeManager.isEnabled, "Wake manager should be enabled by default.")
        XCTAssertFalse(wakeManager.isWakeSessionActive, "Wake session should not be active initially.")
        XCTAssertNil(wakeManager.lastUnlockEvent, "Last unlock event should be nil initially.")
    }

    func testLocalAuthorizationScriptExecution() {
        let output = ScreenWakeUnlockManager.executeLocalAuthorizationAction(
            similarity: 0.965,
            customScriptPath: "unlock_action.sh"
        )

        XCTAssertFalse(output.isEmpty, "Authorization action output should not be empty.")
        XCTAssertTrue(
            output.contains("Authorization") || output.contains("Simulated Enter key") || output.contains("exited with code 0"),
            "Expected authorization output signature, got: \(output)"
        )
    }
}
#endif

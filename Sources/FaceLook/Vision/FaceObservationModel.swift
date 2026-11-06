import CoreGraphics
import Foundation
@preconcurrency import Vision

/// A lightweight, Sendable model representation of a Vision VNFaceObservation.
public struct FaceObservationModel: Identifiable, Sendable {
    public let id: UUID

    /// Normalized Vision coordinates: (0,0) bottom-left, (1,1) top-right.
    public let boundingBox: CGRect

    /// Head roll angle in radians.
    public let roll: Double?

    /// Head yaw angle in radians.
    public let yaw: Double?

    /// Detection confidence score (0.0 ... 1.0).
    public let confidence: Float

    /// Quality assessment score (0.0 ... 1.0).
    public let captureQuality: Float?

    /// Facial landmarks (eyes, nose, mouth, contour).
    public let landmarks: FaceLandmarksData?

    public init(id: UUID = UUID(), observation: VNFaceObservation) {
        self.id = id
        self.boundingBox = observation.boundingBox
        self.roll = observation.roll?.doubleValue
        self.yaw = observation.yaw?.doubleValue
        self.confidence = observation.confidence
        self.captureQuality = observation.faceCaptureQuality

        if let landmarks2D = observation.landmarks {
            let leftEye = landmarks2D.leftEye?.normalizedPoints ?? []
            let rightEye = landmarks2D.rightEye?.normalizedPoints ?? []
            let nose = (landmarks2D.nose?.normalizedPoints ?? []) + (landmarks2D.noseCrest?.normalizedPoints ?? [])
            let outerLips = landmarks2D.outerLips?.normalizedPoints ?? []
            let faceContour = landmarks2D.faceContour?.normalizedPoints ?? []

            self.landmarks = FaceLandmarksData(
                leftEye: leftEye,
                rightEye: rightEye,
                nose: nose,
                outerLips: outerLips,
                faceContour: faceContour
            )
        } else {
            self.landmarks = nil
        }
    }
}

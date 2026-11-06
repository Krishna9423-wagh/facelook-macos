import CoreGraphics
import Foundation

/// Holds collection of normalized landmark points relative to the face bounding box (0.0 ... 1.0).
public struct FaceLandmarksData: Sendable {
    public let leftEye: [CGPoint]
    public let rightEye: [CGPoint]
    public let leftEyebrow: [CGPoint]
    public let rightEyebrow: [CGPoint]
    public let nose: [CGPoint]
    public let outerLips: [CGPoint]
    public let faceContour: [CGPoint]

    public init(
        leftEye: [CGPoint] = [],
        rightEye: [CGPoint] = [],
        leftEyebrow: [CGPoint] = [],
        rightEyebrow: [CGPoint] = [],
        nose: [CGPoint] = [],
        outerLips: [CGPoint] = [],
        faceContour: [CGPoint] = []
    ) {
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.leftEyebrow = leftEyebrow
        self.rightEyebrow = rightEyebrow
        self.nose = nose
        self.outerLips = outerLips
        self.faceContour = faceContour
    }
}

/// Represents a face detected by Apple's Vision framework, including bounding box,
/// orientation angles, facial landmarks, and eye aspect ratio.
public struct DetectedFace: Identifiable, Sendable {
    public let id: UUID

    /// Normalized bounding box with Vision coordinates: (0,0) bottom-left, (1,1) top-right.
    public let boundingBox: CGRect

    /// Detection confidence score (0.0 ... 1.0).
    public let confidence: Float

    /// Head roll angle in radians (if available).
    public let roll: Double?

    /// Head yaw angle in radians (if available).
    public let yaw: Double?

    /// Facial landmarks (eyes, eyebrows, nose, lips, contour).
    public let landmarks: FaceLandmarksData?

    /// Eye Aspect Ratio (EAR) for liveness & blink detection.
    public let eyeAspectRatio: Float?

    public init(
        id: UUID = UUID(),
        boundingBox: CGRect,
        confidence: Float,
        roll: Double? = nil,
        yaw: Double? = nil,
        landmarks: FaceLandmarksData? = nil,
        eyeAspectRatio: Float? = nil
    ) {
        self.id = id
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.roll = roll
        self.yaw = yaw
        self.landmarks = landmarks
        self.eyeAspectRatio = eyeAspectRatio
    }
}

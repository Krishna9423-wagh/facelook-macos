import Foundation

/// Specific errors that can occur during camera session initialization and capture.
public enum CameraError: LocalizedError, Sendable {
    case permissionDenied
    case permissionRestricted
    case noCameraAvailable
    case cannotAddInput
    case cannotAddOutput
    case configurationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera permission was denied. Please enable camera access in macOS System Settings > Privacy & Security > Camera."
        case .permissionRestricted:
            return "Camera access is restricted on this device (e.g. parental controls or enterprise policy)."
        case .noCameraAvailable:
            return "No compatible camera device was found on this Mac."
        case .cannotAddInput:
            return "Failed to attach the camera device input to the capture session."
        case .cannotAddOutput:
            return "Failed to attach the video data output to the capture session."
        case .configurationFailed(let reason):
            return "Camera configuration failed: \(reason)"
        }
    }
}


import SwiftUI

/// An overlay view drawn directly above the camera preview layer.
/// Accurately projects normalized Vision coordinates onto view points
/// considering aspect-fill scaling, video resolution, and horizontal mirroring.
public struct FaceBoundingBoxOverlayView: View {

    public let detectedFaces: [DetectedFace]
    public let videoResolution: CGSize
    public let isMirrored: Bool
    public var verificationStatus: BiometricVerificationStatus

    public init(
        detectedFaces: [DetectedFace],
        videoResolution: CGSize,
        isMirrored: Bool = true,
        verificationStatus: BiometricVerificationStatus = .notEnrolled
    ) {
        self.detectedFaces = detectedFaces
        self.videoResolution = videoResolution
        self.isMirrored = isMirrored
        self.verificationStatus = verificationStatus
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(detectedFaces) { face in
                    let rect = convertVisionRect(
                        face.boundingBox,
                        videoSize: videoResolution,
                        viewSize: geometry.size,
                        isMirrored: isMirrored
                    )

                    FaceReticleView(
                        face: face,
                        rect: rect,
                        verificationStatus: verificationStatus
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Coordinate Conversion (Aspect Fill)

    private func convertVisionRect(
        _ visionBox: CGRect,
        videoSize: CGSize,
        viewSize: CGSize,
        isMirrored: Bool
    ) -> CGRect {
        let vSize = (videoSize.width > 0 && videoSize.height > 0)
            ? videoSize
            : CGSize(width: 1280, height: 720)

        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }

        let scale = max(viewSize.width / vSize.width, viewSize.height / vSize.height)
        let renderedWidth = vSize.width * scale
        let renderedHeight = vSize.height * scale

        let offsetX = (viewSize.width - renderedWidth) / 2.0
        let offsetY = (viewSize.height - renderedHeight) / 2.0

        let normY = 1.0 - (visionBox.origin.y + visionBox.size.height)
        let normX = isMirrored
            ? (1.0 - (visionBox.origin.x + visionBox.size.width))
            : visionBox.origin.x

        return CGRect(
            x: offsetX + (normX * renderedWidth),
            y: offsetY + (normY * renderedHeight),
            width: visionBox.size.width * renderedWidth,
            height: visionBox.size.height * renderedHeight
        )
    }
}

// MARK: - FaceReticleView (Futuristic Bounding Box)

private struct FaceReticleView: View {
    let face: DetectedFace
    let rect: CGRect
    let verificationStatus: BiometricVerificationStatus

    private var reticleColor: Color {
        switch verificationStatus {
        case .verified:
            return .green
        case .notRecognized:
            return .red
        case .enrolling:
            return .orange
        default:
            return .cyan
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Subtle translucent background box
            RoundedRectangle(cornerRadius: 8)
                .stroke(reticleColor.opacity(0.4), lineWidth: 1)
                .background(reticleColor.opacity(0.05))

            // 4 Futuristic Corner Brackets
            CornerBracketsShape(cornerLength: 16)
                .stroke(reticleColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            // Top Badge with Biometric Verification or Detection Confidence
            HStack(spacing: 4) {
                badgeIcon
                badgeText

                if let roll = face.roll {
                    Text(String(format: "%.0f°", roll * 180 / .pi))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(reticleColor.opacity(0.8))
                }
            }
            .foregroundColor(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(reticleColor)
            .clipShape(Capsule())
            .offset(x: 4, y: -24)
        }
        .frame(width: max(rect.width, 20), height: max(rect.height, 20))
        .position(x: rect.midX, y: rect.midY)
    }

    @ViewBuilder
    private var badgeIcon: some View {
        switch verificationStatus {
        case .verified:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .bold))
        case .notRecognized:
            Image(systemName: "xmark.seal.fill")
                .font(.system(size: 10, weight: .bold))
        case .enrolling:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10, weight: .bold))
        default:
            Image(systemName: "faceid")
                .font(.system(size: 10, weight: .bold))
        }
    }

    private var badgeText: some View {
        Group {
            switch verificationStatus {
            case .verified(let sim):
                Text(String(format: "Verified (%.0f%%)", sim * 100))
            case .notRecognized(let sim):
                Text(String(format: "Unknown (%.0f%%)", sim * 100))
            case .enrolling:
                Text("Enrolling...")
            default:
                Text(String(format: "Face (%.0f%%)", face.confidence * 100))
            }
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
    }
}

// MARK: - Corner Brackets Shape

private struct CornerBracketsShape: Shape {
    var cornerLength: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let len = min(cornerLength, min(rect.width, rect.height) / 2)

        // Top-Left Corner
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))

        // Top-Right Corner
        path.move(to: CGPoint(x: rect.maxX - len, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))

        // Bottom-Right Corner
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - len))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - len, y: rect.maxY))

        // Bottom-Left Corner
        path.move(to: CGPoint(x: rect.minX + len, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - len))

        return path
    }
}

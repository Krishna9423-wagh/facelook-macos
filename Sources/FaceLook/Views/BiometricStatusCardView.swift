import SwiftUI

/// A sleek, futuristic FaceID-styled biometric verification card.
/// Displays live authentication status, cosine similarity match score,
/// and provides controls to enroll or clear face profiles.
public struct BiometricStatusCardView: View {

    @ObservedObject public var biometricsManager: FaceBiometricsManager
    public let onEnroll: () -> Void
    public let onClear: () -> Void

    public init(
        biometricsManager: FaceBiometricsManager,
        onEnroll: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) {
        self.biometricsManager = biometricsManager
        self.onEnroll = onEnroll
        self.onClear = onClear
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Biometric Icon Status
            statusIcon
                .frame(width: 32, height: 32)

            // Status Title and Subtitle
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(statusTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(statusColor)

                    if biometricsManager.isFaceEnrolled {
                        Text(String(format: "(%.1f%% Match)", biometricsManager.currentSimilarity * 100))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Text(statusSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Action Buttons
            HStack(spacing: 8) {
                if biometricsManager.isFaceEnrolled {
                    Button(action: onEnroll) {
                        Label("Re-enroll", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: onClear) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Delete enrolled face from Keychain")
                } else {
                    Button(action: onEnroll) {
                        HStack(spacing: 4) {
                            Image(systemName: "faceid")
                            Text("Enroll My Face")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(statusColor.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Status Visuals

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.15))

            switch biometricsManager.verificationStatus {
            case .verified:
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(statusColor)
            case .notRecognized:
                Image(systemName: "lock.slash.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(statusColor)
            case .enrolling:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(statusColor)
                    .rotationEffect(.degrees(biometricsManager.verificationStatus.isVerified ? 0 : 360))
            case .notEnrolled:
                Image(systemName: "faceid")
                    .font(.system(size: 16))
                    .foregroundColor(statusColor)
            case .searching, .noFaceDetected:
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 14))
                    .foregroundColor(statusColor)
            }
        }
    }

    private var statusTitle: String {
        switch biometricsManager.verificationStatus {
        case .verified:
            return "VERIFIED IDENTITY"
        case .notRecognized:
            return "ACCESS DENIED"
        case .enrolling:
            return "ENROLLING BIOMETRICS"
        case .notEnrolled:
            return "NO FACE ENROLLED"
        case .searching:
            return "SCANNING..."
        case .noFaceDetected:
            return "NO FACE IN VIEW"
        }
    }

    private var statusSubtitle: String {
        if !biometricsManager.statusMessage.isEmpty {
            return biometricsManager.statusMessage
        }
        switch biometricsManager.verificationStatus {
        case .verified:
            return "Identity confirmed via Keychain reference embedding"
        case .notRecognized:
            return "Face does not match the stored biometric vector"
        case .enrolling:
            return "Hold still while reference frames are captured..."
        case .notEnrolled:
            return "Enroll your face to enable local biometric verification"
        case .searching:
            return "Comparing live camera feed against Keychain..."
        case .noFaceDetected:
            return "Center your face in front of the camera"
        }
    }

    private var statusColor: Color {
        switch biometricsManager.verificationStatus {
        case .verified:
            return .green
        case .notRecognized:
            return .red
        case .enrolling:
            return .orange
        case .notEnrolled:
            return .blue
        case .searching, .noFaceDetected:
            return .secondary
        }
    }
}


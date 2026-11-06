import AVFoundation
import SwiftUI

/// The main content view presented inside the macOS menu bar NSPopover.
/// Provides live camera preview with toggling, real-time Vision face tracking,
/// FaceID-style biometric recognition status, Keychain enrollment controls,
/// and automated screen wake authorization settings.
public struct PopoverContentView: View {

    @ObservedObject public var cameraManager: CameraManager
    @ObservedObject public var faceDetector: FaceDetectionManager
    @ObservedObject public var biometricsManager: FaceBiometricsManager
    @ObservedObject public var wakeUnlockManager: ScreenWakeUnlockManager

    public init(
        cameraManager: CameraManager,
        faceDetector: FaceDetectionManager,
        biometricsManager: FaceBiometricsManager,
        wakeUnlockManager: ScreenWakeUnlockManager
    ) {
        self.cameraManager = cameraManager
        self.faceDetector = faceDetector
        self.biometricsManager = biometricsManager
        self.wakeUnlockManager = wakeUnlockManager
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Header Bar
            headerBar

            Divider()

            // 1. Live Camera Feed Section with Toggle
            cameraFeedSection

            // 2. Status Indicators: Recognized vs Unrecognized
            biometricStatusSection

            // 3. Face Enrollment Section
            enrollmentSection

            Divider()

            // 4. Screen Wake Automation & Unlock Trigger
            screenWakeAutomationSection

            Divider()

            // Footer Toolbar
            footerToolbar
        }
        .padding(14)
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if cameraManager.isFeedEnabled && cameraManager.authorizationStatus == .authorized {
                cameraManager.startCaptureSession()
                faceDetector.startDetection(cameraManager: cameraManager)
                biometricsManager.startProcessing(cameraManager: cameraManager, faceDetector: faceDetector)
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.18))
                        .frame(width: 26, height: 26)
                    Image(systemName: statusIconName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(statusColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("MacID Vision")
                        .font(.system(size: 13, weight: .bold))
                    Text(biometricsManager.isFaceEnrolled ? "Biometric Protection Active" : "Unconfigured")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Live / Paused Pill
            HStack(spacing: 5) {
                Circle()
                    .fill(cameraManager.isSessionRunning ? Color.red : Color.gray)
                    .frame(width: 7, height: 7)
                Text(cameraManager.isSessionRunning ? "LIVE" : "PAUSED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(Capsule())
        }
    }

    // MARK: - 1. Live Camera Feed Section

    private var cameraFeedSection: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Live Camera Feed", systemImage: "video.fill")
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Toggle("", isOn: Binding(
                    get: { cameraManager.isFeedEnabled },
                    set: { enabled in
                        cameraManager.isFeedEnabled = enabled
                        if enabled {
                            cameraManager.startCaptureSession()
                            faceDetector.startDetection(cameraManager: cameraManager)
                            biometricsManager.startProcessing(cameraManager: cameraManager, faceDetector: faceDetector)
                        } else {
                            cameraManager.stopCaptureSession()
                            faceDetector.stopDetection()
                            biometricsManager.stopProcessing()
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }

            // Preview View or Paused Placeholder
            ZStack {
                if cameraManager.isFeedEnabled && cameraManager.isSessionRunning {
                    ZStack(alignment: .topTrailing) {
                        // Live Preview Layer
                        Group {
                            if cameraManager.renderMode == .hardwarePreviewLayer {
                                CameraPreviewView(session: cameraManager.captureSession)
                            } else {
                                SampleBufferPreviewView(cameraManager: cameraManager)
                            }
                        }

                        // Vision Bounding Box Overlay
                        if faceDetector.isDetectionEnabled {
                            FaceBoundingBoxOverlayView(
                                detectedFaces: faceDetector.detectedFaces,
                                videoResolution: cameraManager.frameResolution,
                                isMirrored: faceDetector.isMirrored,
                                verificationStatus: biometricsManager.verificationStatus
                            )
                            .animation(.linear(duration: 0.06), value: faceDetector.detectedFaces.map(\.boundingBox))
                        }

                        // Telemetry Badge (FPS & Resolution)
                        HStack(spacing: 6) {
                            Text(String(format: "%.0f FPS", cameraManager.liveFPS))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                            if cameraManager.frameResolution.width > 0 {
                                Text("\(Int(cameraManager.frameResolution.width))p")
                                    .font(.system(size: 9, design: .monospaced))
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(6)
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                } else {
                    // Paused State Card
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 26))
                            .foregroundColor(.secondary)
                        Text(cameraManager.isFeedEnabled ? "Starting camera..." : "Camera paused to save battery & CPU")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        if !cameraManager.isFeedEnabled {
                            Button("Resume Feed") {
                                cameraManager.isFeedEnabled = true
                                cameraManager.startCaptureSession()
                                faceDetector.startDetection(cameraManager: cameraManager)
                                biometricsManager.startProcessing(cameraManager: cameraManager, faceDetector: faceDetector)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    // MARK: - 2. Biometric Status Indicators

    private var biometricStatusSection: some View {
        VStack(spacing: 8) {
            // Main Status Banner Card
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: statusIconName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(statusHeadline)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(statusColor)

                        if biometricsManager.isFaceEnrolled && cameraManager.isFeedEnabled {
                            Text(String(format: "%.1f%%", biometricsManager.currentSimilarity * 100))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    Text(statusDetailText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Visual Indicator Dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: statusColor.opacity(0.6), radius: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(statusColor.opacity(0.3), lineWidth: 1)
            )

            // Similarity Gauge Bar (When Enrolled)
            if biometricsManager.isFaceEnrolled && cameraManager.isFeedEnabled {
                VStack(spacing: 3) {
                    HStack {
                        Text("Similarity Match:")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Threshold: \(Int(biometricsManager.matchThreshold * 100))%")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(nsColor: .separatorColor))

                            Capsule()
                                .fill(statusColor)
                                .frame(width: geo.size.width * CGFloat(min(1.0, max(0.0, biometricsManager.currentSimilarity))))
                        }
                    }
                    .frame(height: 5)
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - 3. Face Enrollment Section

    private var enrollmentSection: some View {
        VStack(spacing: 8) {
            if case .enrolling(let progress) = biometricsManager.verificationStatus {
                // Active Enrollment Progress
                VStack(spacing: 6) {
                    HStack {
                        Text("Capturing reference frames...")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }

                    ProgressView(value: progress, total: 1.0)
                        .tint(.orange)

                    Button("Cancel") {
                        biometricsManager.cancelEnrollment()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if biometricsManager.isFaceEnrolled {
                // Enrolled State Controls
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        Text("Keychain Baseline Saved")
                            .font(.system(size: 11, weight: .medium))
                    }

                    Spacer()

                    Button(action: {
                        biometricsManager.startEnrollment()
                    }) {
                        Label("Re-enroll", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: {
                        biometricsManager.clearEnrolledFace()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Delete biometric embedding from Keychain")
                }
                .padding(.horizontal, 4)
            } else {
                // Unenrolled State CTA
                Button(action: {
                    if !cameraManager.isFeedEnabled {
                        cameraManager.isFeedEnabled = true
                    }
                    biometricsManager.startEnrollment()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "faceid")
                            .font(.system(size: 13, weight: .bold))
                        Text("Enroll Face")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.regular)
            }
        }
    }

    // MARK: - 4. Screen Wake Automation Section

    private var screenWakeAutomationSection: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Wake Unlock Trigger", systemImage: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Toggle("", isOn: $wakeUnlockManager.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(wakeUnlockManager.isWakeSessionActive ? Color.orange : Color.green)
                            .frame(width: 7, height: 7)

                        Text(wakeUnlockManager.isWakeSessionActive ? "Wake Verification Active..." : "Listening (screensDidWake)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Test Script") {
                        wakeUnlockManager.testUnlockAction()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                // Telemetry status text
                Text(wakeUnlockManager.statusLog)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                // Last unlock event badge
                if let event = wakeUnlockManager.lastUnlockEvent {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                        Text("Last unlocked at \(event.timestamp, formatter: Self.timeFormatter) (\(String(format: "%.1f%%", event.similarity * 100)))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Footer Toolbar

    private var footerToolbar: some View {
        HStack {
            // Camera Device Menu
            if !cameraManager.availableCameras.isEmpty {
                Menu {
                    ForEach(cameraManager.availableCameras, id: \.uniqueID) { device in
                        Button(action: {
                            cameraManager.switchCamera(to: device)
                        }) {
                            HStack {
                                Text(device.localizedName)
                                if cameraManager.selectedCamera?.uniqueID == device.uniqueID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("Select camera device")
            }

            // Mirror Toggle
            Button(action: {
                faceDetector.isMirrored.toggle()
            }) {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .font(.system(size: 11))
                    .foregroundColor(faceDetector.isMirrored ? .blue : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Toggle camera mirror alignment")

            Spacer()

            // Quit Button
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Text("Quit")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Formatters & Helpers

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .medium
        return df
    }()

    private var statusIconName: String {
        switch biometricsManager.verificationStatus {
        case .verified:
            return "lock.open.fill"
        case .notRecognized:
            return "lock.slash.fill"
        case .enrolling:
            return "arrow.triangle.2.circlepath"
        case .notEnrolled:
            return "person.crop.circle.badge.plus"
        case .searching, .noFaceDetected:
            return "faceid"
        }
    }

    private var statusHeadline: String {
        switch biometricsManager.verificationStatus {
        case .verified:
            return "FACE RECOGNIZED"
        case .notRecognized:
            return "FACE NOT RECOGNIZED"
        case .enrolling:
            return "ENROLLING BIOMETRICS"
        case .notEnrolled:
            return "NO FACE ENROLLED"
        case .searching:
            return "SCANNING FOR FACE..."
        case .noFaceDetected:
            return "NO FACE IN VIEW"
        }
    }

    private var statusDetailText: String {
        switch biometricsManager.verificationStatus {
        case .verified:
            return "Identity confirmed against Keychain baseline"
        case .notRecognized:
            return "Face does not match the enrolled baseline"
        case .enrolling:
            return "Hold still while capturing baseline frames"
        case .notEnrolled:
            return "Click 'Enroll Face' to register your baseline"
        case .searching:
            return "Comparing live camera feed against Keychain"
        case .noFaceDetected:
            return "Position your face in front of the camera"
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

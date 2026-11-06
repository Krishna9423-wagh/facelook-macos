import AVFoundation
import SwiftUI

/// Main application view that coordinates live camera streaming,
/// Vision face detection, Keychain biometric enrollment, and real-time verification.
public struct ContentView: View {

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var faceDetector = FaceDetectionManager()
    @StateObject private var biometricsManager = FaceBiometricsManager()

    public init() {}

    public var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            switch cameraManager.authorizationStatus {
            case .authorized:
                authorizedCameraView
            case .notDetermined:
                permissionPromptView
            case .denied, .restricted:
                permissionDeniedView
            @unknown default:
                permissionPromptView
            }
        }
        .frame(minWidth: 840, minHeight: 580)
        .onAppear {
            if cameraManager.authorizationStatus == .authorized {
                startPipelines()
            }
        }
    }

    // MARK: - Pipeline Lifecycle

    private func startPipelines() {
        cameraManager.startCaptureSession()
        faceDetector.startDetection(cameraManager: cameraManager)
        biometricsManager.startProcessing(cameraManager: cameraManager, faceDetector: faceDetector)
    }

    private func stopPipelines() {
        cameraManager.stopCaptureSession()
        faceDetector.stopDetection()
        biometricsManager.stopProcessing()
    }

    // MARK: - Authorized Live Camera View

    private var authorizedCameraView: some View {
        VStack(spacing: 12) {
            // Live Preview Container with Overlays
            ZStack(alignment: .top) {
                // 1. Live Video Preview Layer
                Group {
                    if cameraManager.renderMode == .hardwarePreviewLayer {
                        CameraPreviewView(session: cameraManager.captureSession)
                    } else {
                        SampleBufferPreviewView(cameraManager: cameraManager)
                    }
                }
                .background(Color.black)

                // 2. Real-time Vision Face Detection & Biometric Bounding Box Overlay
                if faceDetector.isDetectionEnabled {
                    FaceBoundingBoxOverlayView(
                        detectedFaces: faceDetector.detectedFaces,
                        videoResolution: cameraManager.frameResolution,
                        isMirrored: faceDetector.isMirrored,
                        verificationStatus: biometricsManager.verificationStatus
                    )
                    .animation(.linear(duration: 0.06), value: faceDetector.detectedFaces.map(\.boundingBox))
                }

                // 3. Top Floating Telemetry Overlay (HUD)
                topTelemetryOverlay
                    .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding([.top, .horizontal], 14)

            // Biometric FaceID Verification Card
            BiometricStatusCardView(
                biometricsManager: biometricsManager,
                onEnroll: {
                    biometricsManager.startEnrollment()
                },
                onClear: {
                    biometricsManager.clearEnrolledFace()
                }
            )
            .padding(.horizontal, 14)

            // Bottom Control Toolbar
            bottomControlToolbar
                .padding([.bottom, .horizontal], 14)
        }
    }

    // MARK: - Top Telemetry HUD

    private var topTelemetryOverlay: some View {
        HStack(spacing: 8) {
            // Live Status Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(cameraManager.isSessionRunning ? Color.red : Color.gray)
                    .frame(width: 8, height: 8)
                Text(cameraManager.isSessionRunning ? "LIVE" : "PAUSED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            // FPS Counter
            HStack(spacing: 4) {
                Image(systemName: "speedometer")
                    .font(.system(size: 10))
                Text(String(format: "%.1f FPS", cameraManager.liveFPS))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            // Resolution Badge
            if cameraManager.frameResolution.width > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "aspectratio")
                        .font(.system(size: 10))
                    Text("\(Int(cameraManager.frameResolution.width)) × \(Int(cameraManager.frameResolution.height))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }

            // Vision Face Count Badge
            if faceDetector.isDetectionEnabled {
                HStack(spacing: 6) {
                    Image(systemName: faceDetector.faceCount > 0 ? "faceid" : "person.crop.square")
                        .font(.system(size: 11))
                        .foregroundColor(faceDetector.faceCount > 0 ? .cyan : .white)
                    Text(faceDetector.faceCount == 1 ? "1 Face" : "\(faceDetector.faceCount) Faces")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))

                    if faceDetector.inferenceTimeMs > 0 {
                        Text(String(format: "(%.1f ms)", faceDetector.inferenceTimeMs))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }

            Spacer()

            // Active Camera Badge
            if let camera = cameraManager.selectedCamera {
                HStack(spacing: 6) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10))
                    Text(camera.localizedName)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Bottom Control Toolbar

    private var bottomControlToolbar: some View {
        HStack(spacing: 14) {
            // Camera Device Selector
            if !cameraManager.availableCameras.isEmpty {
                HStack(spacing: 6) {
                    Text("Camera:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    Picker("Camera", selection: Binding(
                        get: { cameraManager.selectedCamera ?? cameraManager.availableCameras.first },
                        set: { if let dev = $0 { cameraManager.switchCamera(to: dev) } }
                    )) {
                        ForEach(cameraManager.availableCameras, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(Optional(device))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            }

            // Preview Layer Mode Selector
            HStack(spacing: 6) {
                Text("Layer:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                Picker("Mode", selection: $cameraManager.renderMode) {
                    ForEach(PreviewRenderMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }

            Divider()
                .frame(height: 18)

            // Face Detection Toggle
            Toggle(isOn: $faceDetector.isDetectionEnabled) {
                HStack(spacing: 4) {
                    Image(systemName: "faceid")
                    Text("Face Tracking")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .toggleStyle(.checkbox)

            // Mirroring Toggle
            Toggle(isOn: $faceDetector.isMirrored) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    Text("Mirror Overlay")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .toggleStyle(.checkbox)

            Spacer()

            // Start / Pause Session Toggle
            Button(action: {
                if cameraManager.isSessionRunning {
                    stopPipelines()
                } else {
                    startPipelines()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: cameraManager.isSessionRunning ? "pause.fill" : "play.fill")
                    Text(cameraManager.isSessionRunning ? "Pause" : "Resume")
                }
                .frame(minWidth: 84)
            }
            .buttonStyle(.borderedProminent)
            .tint(cameraManager.isSessionRunning ? .orange : .blue)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Permission Prompt View (notDetermined)

    private var permissionPromptView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "camera.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.blue)
            }

            VStack(spacing: 8) {
                Text("Camera Permission Required")
                    .font(.system(size: 20, weight: .semibold))

                Text("FaceLook requires webcam access to stream video frames,\nrun Vision face tracking, and perform local biometric verification.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                Task {
                    let granted = await cameraManager.requestCameraPermission()
                    if granted {
                        startPipelines()
                    }
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Grant Camera Permission")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
    }

    // MARK: - Permission Denied View

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "camera.badge.ellipsis")
                    .font(.system(size: 36))
                    .foregroundColor(.red)
            }

            VStack(spacing: 8) {
                Text("Camera Access Denied")
                    .font(.system(size: 20, weight: .semibold))

                Text("Camera access was previously denied in macOS System Settings.\nPlease enable camera access to use FaceLook.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button(action: {
                    cameraManager.openSystemSettings()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                        Text("Open System Settings")
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Check Again") {
                    cameraManager.checkAuthorizationStatus()
                    if cameraManager.authorizationStatus == .authorized {
                        startPipelines()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(40)
    }
}

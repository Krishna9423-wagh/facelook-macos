import AppKit
import SwiftUI

/// Main macOS application entry point configured as a persistent menu bar agent.
@main
struct FaceLookApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // App runs entirely from the macOS menu bar (NSStatusItem)
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

/// Application delegate managing the menu bar lifecycle and background services.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private(set) var cameraManager = CameraManager()
    private(set) var faceDetector = FaceDetectionManager()
    private(set) var biometricsManager = FaceBiometricsManager()
    private(set) var wakeUnlockManager: ScreenWakeUnlockManager?

    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize wake unlock automation manager
        let wakeManager = ScreenWakeUnlockManager(
            cameraManager: cameraManager,
            faceDetector: faceDetector,
            biometricsManager: biometricsManager
        )
        self.wakeUnlockManager = wakeManager

        // Initialize persistent menu bar controller
        menuBarController = MenuBarController(
            cameraManager: cameraManager,
            faceDetector: faceDetector,
            biometricsManager: biometricsManager,
            wakeUnlockManager: wakeManager
        )

        // Automatically start the camera and recognition pipeline if authorized
        if cameraManager.authorizationStatus == .authorized {
            cameraManager.startCaptureSession()
            faceDetector.startDetection(cameraManager: cameraManager)
            biometricsManager.startProcessing(cameraManager: cameraManager, faceDetector: faceDetector)
        }

        // Show the popover window on initial launch so user sees the settings interface immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.menuBarController?.showPopover()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cameraManager.stopCaptureSession()
        faceDetector.stopDetection()
        biometricsManager.stopProcessing()
    }
}

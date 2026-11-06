import AppKit
import Combine
import SwiftUI

/// Manages the persistent macOS menu bar status item (NSStatusItem)
/// and coordinates the NSPopover containing the SwiftUI settings interface.
@MainActor
public final class MenuBarController: NSObject {

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var eventMonitor: Any?

    private let cameraManager: CameraManager
    private let faceDetector: FaceDetectionManager
    private let biometricsManager: FaceBiometricsManager
    private let wakeUnlockManager: ScreenWakeUnlockManager
    private var cancellables = Set<AnyCancellable>()

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
        super.init()

        setupStatusItem()
        setupPopover()
        observeBiometricState()
    }

    isolated deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        // Initial menu bar icon
        updateMenuBarIcon(for: biometricsManager.verificationStatus)

        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    // MARK: - Popover Setup

    private func setupPopover() {
        popover.contentSize = NSSize(width: 380, height: 490)
        popover.behavior = .transient
        popover.animates = true

        let rootView = PopoverContentView(
            cameraManager: cameraManager,
            faceDetector: faceDetector,
            biometricsManager: biometricsManager,
            wakeUnlockManager: wakeUnlockManager
        )

        popover.contentViewController = NSHostingController(rootView: rootView)

        // Monitor clicks outside the popover to dismiss cleanly
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            if self.popover.isShown {
                self.closePopover()
            }
        }
    }

    // MARK: - Biometric State Observation

    private func observeBiometricState() {
        biometricsManager.$verificationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.updateMenuBarIcon(for: status)
            }
            .store(in: &cancellables)

        cameraManager.$isSessionRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] isRunning in
                guard let self else { return }
                if !isRunning {
                    self.updateMenuBarIcon(for: self.biometricsManager.verificationStatus)
                }
            }
            .store(in: &cancellables)
    }

    private func updateMenuBarIcon(for status: BiometricVerificationStatus) {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        let tintColor: NSColor?

        if !cameraManager.isSessionRunning {
            symbolName = "video.slash"
            tintColor = .secondaryLabelColor
        } else {
            switch status {
            case .verified:
                symbolName = "lock.open.fill"
                tintColor = .systemGreen
            case .notRecognized:
                symbolName = "lock.slash.fill"
                tintColor = .systemRed
            case .enrolling:
                symbolName = "arrow.triangle.2.circlepath"
                tintColor = .systemOrange
            case .notEnrolled:
                symbolName = "faceid"
                tintColor = nil
            case .searching, .noFaceDetected:
                symbolName = "faceid"
                tintColor = nil
            }
        }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "FaceLook")?.withSymbolConfiguration(config) {
            image.isTemplate = (tintColor == nil)
            button.image = image
            button.contentTintColor = tintColor
        }
    }

    // MARK: - Popover Actions

    @objc private func handleStatusItemClick() {
        guard let currentEvent = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if currentEvent.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    public func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    public func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    public func closePopover() {
        popover.performClose(nil)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Settings", action: #selector(showPopoverFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit MacID Vision", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // Restore button click behavior
    }

    @objc private func showPopoverFromMenu() {
        showPopover()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

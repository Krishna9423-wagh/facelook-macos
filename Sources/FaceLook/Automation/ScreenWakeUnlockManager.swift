import AppKit
import Combine
import Foundation

// MARK: - Unlock Event Record

/// Represents a successful biometric authorization event upon screen wake.
public struct UnlockEventRecord: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let similarity: Float
    public let scriptOutput: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        similarity: Float,
        scriptOutput: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.similarity = similarity
        self.scriptOutput = scriptOutput
    }
}

// MARK: - ScreenWakeUnlockManager (MainActor Service)

/// Listens for macOS screen wake and lock events via NSWorkspace notifications,
/// initiates the biometric recognition loop upon wake, and executes a local authorization
/// script or helper utility when face verification succeeds above the threshold.
@MainActor
public final class ScreenWakeUnlockManager: ObservableObject {

    // MARK: - Published Properties

    /// Master toggle for wake-triggered biometric unlock.
    @Published public var isEnabled: Bool = true

    /// Optional custom path to an executable script (e.g. ~/.macid/unlock.sh).
    @Published public var customScriptPath: String = ""

    /// Indicates whether a wake-induced verification window is currently active.
    @Published public private(set) var isWakeSessionActive: Bool = false

    /// Record of the most recent successful unlock event.
    @Published public private(set) var lastUnlockEvent: UnlockEventRecord?

    /// Human-readable telemetry log status.
    @Published public private(set) var statusLog: String = "Listening for screen wake events"

    // MARK: - Dependencies & State

    private let cameraManager: CameraManager
    private let faceDetector: FaceDetectionManager
    private let biometricsManager: FaceBiometricsManager

    private var cancellables = Set<AnyCancellable>()
    private var wakeSessionTimer: Task<Void, Never>?

    /// Debounce tracker preventing duplicate unlock script executions within a short window.
    private var lastUnlockTime: Date = .distantPast
    private let unlockDebounceInterval: TimeInterval = 6.0

    /// Maximum duration (in seconds) the wake recognition loop stays active waiting for a face.
    private let wakeTimeoutDuration: TimeInterval = 15.0

    public init(
        cameraManager: CameraManager,
        faceDetector: FaceDetectionManager,
        biometricsManager: FaceBiometricsManager
    ) {
        self.cameraManager = cameraManager
        self.faceDetector = faceDetector
        self.biometricsManager = biometricsManager

        setupWorkspaceNotificationListeners()
        observeBiometricVerification()
    }

    deinit {
        wakeSessionTimer?.cancel()
    }

    // MARK: - NSWorkspace Notification Listeners

    private func setupWorkspaceNotificationListeners() {
        let center = NSWorkspace.shared.notificationCenter

        // 1. Screen Wake Notification
        center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenWakeEvent()
            }
        }

        // 2. Screen Sleep Notification
        center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenSleepEvent()
            }
        }

        // 3. Screen Lock Notifications (Distributed Center)
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.statusLog = "Screen locked. Ready to verify on wake."
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isWakeSessionActive = false
                self?.wakeSessionTimer?.cancel()
            }
        }
    }

    // MARK: - Screen Wake Handling

    /// Invoked when NSWorkspace fires screensDidWakeNotification.
    public func handleScreenWakeEvent() {
        guard isEnabled else { return }
        guard biometricsManager.isFaceEnrolled else {
            statusLog = "Screen woke, but no face is enrolled in Keychain."
            return
        }

        statusLog = "⚡️ Screen wake detected! Activating biometric verification loop..."
        isWakeSessionActive = true

        // Ensure camera and Vision pipelines are actively streaming
        if !cameraManager.isSessionRunning {
            cameraManager.isFeedEnabled = true
            cameraManager.startCaptureSession()
        }
        faceDetector.startDetection(cameraManager: cameraManager)
        biometricsManager.startProcessing(cameraManager: cameraManager, faceDetector: faceDetector)

        // Reset wake session timeout timer
        wakeSessionTimer?.cancel()
        wakeSessionTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(15.0 * 1_000_000_000))
            guard let self else { return }
            if self.isWakeSessionActive {
                self.isWakeSessionActive = false
                self.statusLog = "Wake verification window timed out (no matching face in view)."
            }
        }
    }

    private func handleScreenSleepEvent() {
        isWakeSessionActive = false
        wakeSessionTimer?.cancel()
        statusLog = "Screen asleep. Camera in standby."
    }

    // MARK: - Biometric Match Monitoring

    private func observeBiometricVerification() {
        biometricsManager.$verificationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                guard self.isEnabled else { return }

                if case .verified(let similarity) = status {
                    self.handleVerifiedMatch(similarity: similarity)
                }
            }
            .store(in: &cancellables)
    }

    private func handleVerifiedMatch(similarity: Float) {
        let now = Date()
        guard now.timeIntervalSince(lastUnlockTime) > unlockDebounceInterval else {
            return
        }
        lastUnlockTime = now

        statusLog = String(format: "✅ Face verified! (Match: %.1f%%). Executing authorization action...", similarity * 100)

        // Play native system audio confirmation
        NSSound(named: "Glass")?.play()

        // Terminate wake session
        isWakeSessionActive = false
        wakeSessionTimer?.cancel()

        // Execute local script / authorization helper
        let customPath = self.customScriptPath
        Task.detached(priority: .userInitiated) { [weak self] in
            let output = Self.executeLocalAuthorizationAction(similarity: similarity, customScriptPath: customPath)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastUnlockEvent = UnlockEventRecord(
                    timestamp: Date(),
                    similarity: similarity,
                    scriptOutput: output
                )
                self.statusLog = String(format: "🔓 Authorization passed (%.1f%%). Lock state dismissed.", similarity * 100)
            }
        }
    }

    // MARK: - Local Script & Helper Execution

    /// Executes the local script or AppleScript helper to dismiss the lock state or pass authorization.
    public nonisolated static func executeLocalAuthorizationAction(
        similarity: Float,
        customScriptPath: String
    ) -> String {
        let similarityString = String(format: "%.1f%%", similarity * 100)
        let username = NSUserName()

        // 1. Locate executable script
        let scriptURL = resolveScriptURL(customScriptPath: customScriptPath)

        var outputLog = ""

        if let scriptURL, FileManager.default.isExecutableFile(atPath: scriptURL.path) {
            outputLog += "Executing script at \(scriptURL.path)...\n"
            let process = Process()
            let pipe = Pipe()

            process.executableURL = scriptURL
            process.arguments = [similarityString, username]
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8) {
                    outputLog += str
                }
                outputLog += "Script exited with code \(process.terminationStatus)\n"
            } catch {
                outputLog += "Failed to run script: \(error.localizedDescription)\n"
            }
        } else {
            // 2. Built-in AppleScript helper to dismiss lock screen / screensaver prompt
            outputLog += "No custom script found. Running built-in AppleScript unlock helper...\n"
            dismissLockScreenViaAppleScript()
            outputLog += "Simulated Enter key code sent to System Events.\n"
        }

        return outputLog
    }

    /// Simulates pressing the Return key to dismiss screensaver or wake prompt.
    private nonisolated static func dismissLockScreenViaAppleScript() {
        let scriptSource = """
        tell application "System Events"
            key code 36
        end tell
        """
        if let script = NSAppleScript(source: scriptSource) {
            var errorInfo: NSDictionary?
            script.executeAndReturnError(&errorInfo)
        }
    }

    /// Resolves the URL of the unlock script to run.
    private nonisolated static func resolveScriptURL(customScriptPath: String) -> URL? {
        // Priority 1: User custom script path if specified
        if !customScriptPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (customScriptPath as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        // Priority 2: unlock_action.sh in current working directory
        let localURL = URL(fileURLWithPath: "unlock_action.sh")
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        // Priority 3: Script in main bundle resources
        if let bundleScript = Bundle.main.url(forResource: "unlock_action", withExtension: "sh") {
            return bundleScript
        }

        return nil
    }

    // MARK: - Manual Test Trigger

    /// Manually tests the unlock action pipeline.
    public func testUnlockAction() {
        statusLog = "Testing unlock action manually..."
        let sim = biometricsManager.currentSimilarity > 0 ? biometricsManager.currentSimilarity : 0.95
        handleVerifiedMatch(similarity: sim)
    }
}

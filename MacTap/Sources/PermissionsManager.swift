import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import IOKit
import IOKit.hid

// MARK: - Permission State

enum PermissionState: String {
    case granted
    case denied
    case notDetermined
    case unknown

    var displayName: String {
        switch self {
        case .granted:       return "Granted"
        case .denied:        return "Denied"
        case .notDetermined: return "Not Determined"
        case .unknown:       return "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .granted:       return "checkmark.circle.fill"
        case .denied:        return "xmark.circle.fill"
        case .notDetermined: return "exclamationmark.circle.fill"
        case .unknown:       return "questionmark.circle.fill"
        }
    }
}

extension Notification.Name {
    static let macTapNeedsAccessibility = Notification.Name("macTapNeedsAccessibility")
}

/// Manages macOS permissions for MacTap.
///
/// Required:
///   - Accessibility (CGEvent posting — keyboard shortcuts, media keys, lock screen)
/// Optional:
///   - Input Monitoring (arrow-key simulation / ignore-while-typing)
///   - AppleEvents (AppleScript actions)
final class PermissionsManager: ObservableObject {

    static let shared = PermissionsManager()

    @Published var accessibility: PermissionState = .unknown
    @Published var postEvent: PermissionState = .unknown
    @Published var inputMonitoring: PermissionState = .unknown
    @Published var appleEvents: PermissionState = .unknown
    @Published var currentStep: Int = 0

    private var pollTimer: DispatchSourceTimer?
    private var didCheckOnLaunch = false
    private var lastBlockedPromptAt: TimeInterval = 0

    private init() {}

    func checkAll() {
        checkAccessibility()
        checkPostEvent()
        checkInputMonitoring()
        checkAppleEvents()
    }

    func checkOnLaunch() {
        guard !didCheckOnLaunch else { return }
        didCheckOnLaunch = true
        checkAll()
        startPolling(interval: 1.5)
        NSLog("MacTap: permissions launch ax=%@ postEvent=%@ input=%@ appleEvents=%@",
              accessibility.rawValue, postEvent.rawValue, inputMonitoring.rawValue, appleEvents.rawValue)
    }

    // MARK: - Accessibility (REQUIRED)

    func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        let previous = canPostEvents
        accessibility = trusted ? .granted : .notDetermined
        if canPostEvents && !previous {
            currentStep = 0
            IntroWindowController.shared.bringToFront()
        }
    }

    func checkPostEvent() {
        postEvent = CGPreflightPostEventAccess() ? .granted : .notDetermined
    }

    func requestAccessibility() {
        NSLog("MacTap: requesting Accessibility + Post Event...")
        currentStep = 1
        // Post Event is a separate TCC service. Tahoe drops Command-chords
        // unless this grant is actually present, even if Accessibility looks on.
        _ = CGRequestPostEventAccess()
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        accessibility = trusted ? .granted : .notDetermined
        checkPostEvent()
        if canPostEvents {
            NSLog("MacTap: event posting already granted")
            return
        }
        openAccessibilitySettings()
        startPolling(interval: 0.6)
    }

    /// Called when a knock tried to send a shortcut without Accessibility.
    func handleBlockedAction() {
        let now = Date().timeIntervalSince1970
        guard now - lastBlockedPromptAt > 4 else { return }
        lastBlockedPromptAt = now
        NotificationCenter.default.post(name: .macTapNeedsAccessibility, object: nil)
        requestAccessibility()
    }

    // MARK: - Input Monitoring (OPTIONAL)

    func checkInputMonitoring() {
        let result = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if result == kIOHIDAccessTypeGranted {
            inputMonitoring = .granted
        } else if result == kIOHIDAccessTypeDenied {
            inputMonitoring = .denied
        } else {
            inputMonitoring = .notDetermined
        }
    }

    func requestInputMonitoring() {
        NSLog("MacTap: requesting Input Monitoring permission...")
        currentStep = 2
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        openInputMonitoringSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkInputMonitoring()
        }
    }

    // MARK: - AppleEvents (OPTIONAL)

    func checkAppleEvents() {
        if appleEvents == .unknown {
            appleEvents = .notDetermined
        }
    }

    func requestAppleEvents() {
        NSLog("MacTap: requesting AppleEvents permission...")
        currentStep = 3
        openAutomationSettings()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var errorInfo: NSDictionary?
            let script = NSAppleScript(source: "tell application \"System Events\" to return")
            script?.executeAndReturnError(&errorInfo)
            DispatchQueue.main.async {
                if let errorInfo = errorInfo as? [String: Any],
                   let number = errorInfo[NSAppleScript.errorNumber] as? Int {
                    if number == -1743 || number == -1708 {
                        self?.appleEvents = .denied
                        NSLog("MacTap: AppleEvents not authorized (%d)", number)
                    } else {
                        self?.appleEvents = .granted
                    }
                } else {
                    self?.appleEvents = .granted
                    NSLog("MacTap: AppleEvents granted")
                }
            }
        }
    }

    func grantNext() {
        if accessibility != .granted {
            requestAccessibility()
        } else if inputMonitoring != .granted {
            requestInputMonitoring()
        } else if appleEvents != .granted {
            requestAppleEvents()
        } else {
            currentStep = 0
        }
    }

    // MARK: - Polling

    func startPolling(interval: TimeInterval = 1.5) {
        pollTimer?.cancel()
        pollTimer = nil
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.checkAll()
        }
        timer.resume()
        pollTimer = timer
    }

    func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    var canPostEvents: Bool {
        postEvent == .granted || accessibility == .granted || CGPreflightPostEventAccess() || AXIsProcessTrusted()
    }

    var allGranted: Bool {
        canPostEvents
    }

    var allOptionalGranted: Bool {
        accessibility == .granted && inputMonitoring == .granted && appleEvents == .granted
    }

    var grantedCount: Int {
        var count = 0
        if accessibility == .granted { count += 1 }
        if inputMonitoring == .granted { count += 1 }
        if appleEvents == .granted { count += 1 }
        return count
    }

    var totalCount: Int { 3 }

    var nextStepDescription: String? {
        if accessibility != .granted {
            return "Allow Accessibility — needed to send keyboard shortcuts"
        }
        return nil
    }

    // MARK: - Open System Settings

    func openSystemSettings(section: String) {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(section)",
            "x-apple.systempreferences:com.apple.preference.security?\(section)",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ]
        for spec in candidates {
            if let url = URL(string: spec), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    func openAccessibilitySettings() {
        openSystemSettings(section: "Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openSystemSettings(section: "Privacy_ListenEvent")
    }

    func openAutomationSettings() {
        openSystemSettings(section: "Privacy_Automation")
    }
}

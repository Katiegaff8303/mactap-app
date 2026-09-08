import Foundation
import AppKit
import Carbon.HIToolbox
import ApplicationServices
import CoreGraphics

final class ActionExecutor {

    static let shared = ActionExecutor()

    func execute(_ slot: GestureSlot, targeting app: NSRunningApplication? = nil) {
        let work = {
            self.perform(slot, targeting: app)
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private var targetPID: pid_t = 0

    private func perform(_ slot: GestureSlot, targeting app: NSRunningApplication?) {
        NSLog("MacTap: execute %@ for %@ × %d", slot.actionType.displayName, slot.side.rawValue, slot.tapCount)

        targetPID = pid_t(app?.processIdentifier ?? 0)
        if slot.actionType.needsAccessibility {
            activate(app)
        }

        switch slot.actionType {
        case .none:
            break
        case .copy:
            sendKeyboardShortcut("cmd+c")
        case .paste:
            sendKeyboardShortcut("cmd+v")
        case .cut:
            sendKeyboardShortcut("cmd+x")
        case .undo:
            sendKeyboardShortcut("cmd+z")
        case .redo:
            sendKeyboardShortcut("cmd+shift+z")
        case .save:
            sendKeyboardShortcut("cmd+s")
        case .selectAll:
            sendKeyboardShortcut("cmd+a")
        case .aiAccept:
            sendKey(keyCode: UInt16(kVK_Return), modifiers: [])
        case .aiReject:
            sendKey(keyCode: UInt16(kVK_Escape), modifiers: [])
        case .newTab:
            sendKeyboardShortcut("cmd+t")
        case .closeTab:
            sendKeyboardShortcut("cmd+w")
        case .shellCommand:
            runShell(slot.parameter)
        case .appleScript:
            runAppleScript(slot.parameter)
        case .openURL:
            openURL(slot.parameter)
        case .openApp:
            openApp(slot.parameter)
        case .runShortcut:
            runShortcut(slot.parameter)
        case .keyboardShortcut:
            sendKeyboardShortcut(slot.parameter)
        case .mediaPlayPause:
            postSystemKey(NX_KEYTYPE_PLAY)
        case .mediaNext:
            postSystemKey(NX_KEYTYPE_NEXT)
        case .mediaPrevious:
            postSystemKey(NX_KEYTYPE_PREVIOUS)
        case .mute:
            postSystemKey(NX_KEYTYPE_MUTE)
        case .volumeUp:
            postSystemKey(NX_KEYTYPE_SOUND_UP)
        case .volumeDown:
            postSystemKey(NX_KEYTYPE_SOUND_DOWN)
        case .screenshot:
            sendKeyboardShortcut("cmd+shift+3")
        case .screenshotSelection:
            sendKeyboardShortcut("cmd+shift+4")
        case .lockScreen:
            lockScreen()
        case .sleepDisplay:
            sleepDisplay()
        case .startScreensaver:
            startScreensaver()
        case .missionControl:
            openMissionControl()
        case .spotlight:
            sendKeyboardShortcut("cmd+space")
        case .showDesktop:
            showDesktop()
        case .notificationCenter:
            openNotificationCenter()
        case .hideFrontApp:
            sendKeyboardShortcut("cmd+h")
        case .hideOthers:
            sendKeyboardShortcut("cmd+opt+h")
        case .switchDesktopLeft:
            sendKeyboardShortcut("ctrl+left")
        case .switchDesktopRight:
            sendKeyboardShortcut("ctrl+right")
        case .tileLeft:
            sendKeyboardShortcut("fn+ctrl+left")
        case .tileRight:
            sendKeyboardShortcut("fn+ctrl+right")
        case .toggleDarkMode:
            toggleDarkMode()
        case .dictation:
            startDictation()
        case .soundFX:
            SoundManager.shared.playTapSound(side: slot.side, tapCount: slot.tapCount)
        }
    }

    // MARK: - Shell / AppleScript / URL / App

    private func runShell(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-lc", trimmed]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            NSLog("MacTap: shell failed: %@", error.localizedDescription)
        }
    }

    private func runAppleScript(_ source: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var errorInfo: NSDictionary?
            NSAppleScript(source: trimmed)?.executeAndReturnError(&errorInfo)
            if let errorInfo {
                NSLog("MacTap: AppleScript error: %@", String(describing: errorInfo))
            }
        }
    }

    private func openURL(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cleaned = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: cleaned) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openApp(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        if trimmed.contains("."),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
            NSWorkspace.shared.openApplication(at: url, configuration: config)
            return
        }

        if let url = applicationURL(named: trimmed) {
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error {
                    NSLog("MacTap: openApplication failed: %@", error.localizedDescription)
                    self.runShell("open -a \(Self.shellQuote(trimmed))")
                }
            }
            return
        }

        runShell("open -a \(Self.shellQuote(trimmed))")
    }

    private func activate(_ app: NSRunningApplication?) {
        guard let app, !app.isTerminated else { return }
        if app == NSRunningApplication.current { return }
        app.activate()
        usleep(35_000)
    }

    private func runShortcut(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = ["run", trimmed]
        task.standardOutput = FileHandle.nullDevice
        let err = Pipe()
        task.standardError = err
        do {
            try task.run()
        } catch {
            NSLog("MacTap: shortcuts run failed: %@", error.localizedDescription)
        }
    }

    private func startDictation() {
        sendKey(keyCode: UInt16(kVK_Function), modifiers: [])
        usleep(90_000)
        sendKey(keyCode: UInt16(kVK_Function), modifiers: [])
    }

    private func applicationURL(named name: String) -> URL? {
        let appName = name.hasSuffix(".app") ? name : "\(name).app"
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            home.appendingPathComponent("Applications"),
        ]
        for root in roots {
            let candidate = root.appendingPathComponent(appName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - System actions

    private func lockScreen() {
        sendKeyboardShortcut("ctrl+cmd+q")
        runAppleScript("tell application \"System Events\" to keystroke \"q\" using {control down, command down}")
    }

    private func sleepDisplay() {
        runShell("pmset displaysleepnow")
    }

    private func startScreensaver() {
        let engine = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        if FileManager.default.fileExists(atPath: engine.path) {
            NSWorkspace.shared.openApplication(at: engine, configuration: NSWorkspace.OpenConfiguration())
        } else {
            runAppleScript("tell application \"System Events\" to start current screen saver")
        }
    }

    private func openMissionControl() {
        let paths = [
            "/System/Applications/Mission Control.app",
            "/System/Library/CoreServices/Mission Control.app",
        ]
        for path in paths where FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }
        sendKeyboardShortcut("ctrl+up")
    }

    private func showDesktop() {
        sendKey(keyCode: UInt16(kVK_F11), modifiers: [])
        runAppleScript("tell application \"System Events\" to key code 103")
    }

    private func openNotificationCenter() {
        runAppleScript("""
        tell application "System Events"
            try
                tell application process "ControlCenter"
                    set candidates to menu bar items of menu bar 1
                    repeat with itemRef in candidates
                        set desc to description of itemRef
                        if desc contains "Notification" or desc contains "Date" or desc contains "Clock" or desc contains "Control Center" then
                            click itemRef
                            return
                        end if
                    end repeat
                    if (count of candidates) > 0 then click last item of candidates
                end tell
            end try
            try
                tell application process "Control Center"
                    click last menu bar item of menu bar 1
                end tell
            end try
        end tell
        """)
    }

    private func toggleDarkMode() {
        runAppleScript("""
        tell application "System Events"
            tell appearance preferences
                set dark mode to not dark mode
            end tell
        end tell
        """)
    }

    // MARK: - Keyboard

    private func sendKeyboardShortcut(_ shortcut: String) {
        guard let (keyCode, modifiers) = parseShortcut(shortcut) else {
            NSLog("MacTap: could not parse shortcut: %@", shortcut)
            return
        }
        sendKey(keyCode: keyCode, modifiers: modifiers)
    }

    private func parseShortcut(_ s: String) -> (UInt16, NSEvent.ModifierFlags)? {
        var text = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let replacements: [(String, String)] = [
            ("command", "cmd"), ("control", "ctrl"), ("option", "opt"),
            ("alternate", "opt"), ("alt", "opt"), ("shift", "shift"),
            ("⌘", "cmd+"), ("⇧", "shift+"), ("⌃", "ctrl+"), ("⌥", "opt+"),
            (" ", ""), ("-", "+"),
        ]
        for (from, to) in replacements {
            text = text.replacingOccurrences(of: from, with: to)
        }
        while text.contains("++") {
            text = text.replacingOccurrences(of: "++", with: "+")
        }
        if text.hasPrefix("+") { text.removeFirst() }
        if text.hasSuffix("+") { text.removeLast() }

        let parts = text.split(separator: "+").map(String.init)
        var modifiers: NSEvent.ModifierFlags = []
        var keyToken: String?

        for part in parts where !part.isEmpty {
            switch part {
            case "cmd", "command": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "ctrl", "control": modifiers.insert(.control)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "fn", "globe": modifiers.insert(.function)
            default:
                keyToken = part
            }
        }
        guard let token = keyToken, let keyCode = keyCodeFor(token) else { return nil }
        return (keyCode, modifiers)
    }

    private func keyCodeFor(_ token: String) -> UInt16? {
        if token.count == 1, let char = token.first {
            let mapping: [Character: Int] = [
                "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C,
                "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
                "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I,
                "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
                "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
                "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
                "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U,
                "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
                "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
                "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2,
                "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
                "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
                "9": kVK_ANSI_9,
                " ": kVK_Space,
                "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal,
                "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
                "\\": kVK_ANSI_Backslash, ";": kVK_ANSI_Semicolon,
                "'": kVK_ANSI_Quote, "`": kVK_ANSI_Grave,
                ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
                "/": kVK_ANSI_Slash,
            ]
            if let code = mapping[char] { return UInt16(code) }
        }

        let named: [String: Int] = [
            "space": kVK_Space,
            "return": kVK_Return, "enter": kVK_Return,
            "tab": kVK_Tab,
            "esc": kVK_Escape, "escape": kVK_Escape,
            "delete": kVK_Delete, "backspace": kVK_Delete,
            "forwarddelete": kVK_ForwardDelete,
            "left": kVK_LeftArrow, "right": kVK_RightArrow,
            "up": kVK_UpArrow, "down": kVK_DownArrow,
            "home": kVK_Home, "end": kVK_End,
            "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
            "plus": kVK_ANSI_Equal, "minus": kVK_ANSI_Minus,
            "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4,
            "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
            "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
        ]
        if let code = named[token] { return UInt16(code) }
        return nil
    }

    /// On macOS 26, CGEvent Command-chords from ad-hoc binaries are often
    /// dropped even when Accessibility looks granted. System Events is the
    /// path that still reaches Spotlight, copy, paste, and app shortcuts.
    private func sendKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        if sendViaSystemEvents(keyCode: keyCode, modifiers: modifiers) {
            return
        }
        sendViaCGEvent(keyCode: keyCode, modifiers: modifiers)
        if !CGPreflightPostEventAccess() && !AXIsProcessTrusted() {
            PermissionsManager.shared.handleBlockedAction()
        }
    }

    @discardableResult
    private func sendViaSystemEvents(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("command down") }
        if modifiers.contains(.shift) { parts.append("shift down") }
        if modifiers.contains(.option) { parts.append("option down") }
        if modifiers.contains(.control) { parts.append("control down") }
        let using = parts.isEmpty ? "" : " using {\(parts.joined(separator: ", "))}"
        let source = "tell application \"System Events\" to key code \(Int(keyCode))\(using)"
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo, let number = errorInfo[NSAppleScript.errorNumber] as? Int, number != 0 {
            NSLog("MacTap: System Events key code %d failed (%d)", Int(keyCode), number)
            if number == -1743 || number == -1708 {
                DispatchQueue.main.async {
                    PermissionsManager.shared.requestAppleEvents()
                }
            }
            return false
        }
        NSLog("MacTap: System Events key code %d", Int(keyCode))
        return true
    }

    private func sendViaCGEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        if !CGPreflightPostEventAccess() {
            _ = CGRequestPostEventAccess()
        }
        guard let source = CGEventSource(stateID: .hidSystemState)
                ?? CGEventSource(stateID: .combinedSessionState) else { return }
        source.localEventsSuppressionInterval = 0
        let flags = cgFlags(from: modifiers)
        let pid = targetPID

        func post(down: Bool) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
            event.flags = flags
            event.post(tap: .cghidEventTap)
            event.post(tap: .cgSessionEventTap)
            if pid > 0 {
                event.postToPid(pid)
            }
        }

        post(down: true)
        usleep(16_000)
        post(down: false)
    }

    private func cgFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.function) { result.insert(.maskSecondaryFn) }
        return result
    }

    // NX_KEYTYPE_* from IOKit / HIToolbox
    private let NX_KEYTYPE_SOUND_UP: Int = 0
    private let NX_KEYTYPE_SOUND_DOWN: Int = 1
    private let NX_KEYTYPE_MUTE: Int = 7
    private let NX_KEYTYPE_PLAY: Int = 16
    private let NX_KEYTYPE_NEXT: Int = 17
    private let NX_KEYTYPE_PREVIOUS: Int = 18

    private func postSystemKey(_ key: Int) {
        pulseSystemKey(key, down: true)
        usleep(40_000)
        pulseSystemKey(key, down: false)
    }

    private func pulseSystemKey(_ key: Int, down: Bool) {
        let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
        let data1 = Int((key << 16) | (down ? 0xA00 : 0xB00))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}

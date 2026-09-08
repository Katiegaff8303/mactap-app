import Foundation
import Combine
import AppKit

final class GestureEngine: ObservableObject {

    @Published var isRunning = false
    @Published var lastGesture: DetectedGesture?
    @Published var lastExecutedSlot: GestureSlot?
    @Published var flashToken: Int = 0
    @Published var hudGesture: DetectedGesture?

    let sensor = SensorManager()
    private(set) lazy var detector = TapDetector(sensor: sensor)

    private var cancellables = Set<AnyCancellable>()
    private var lastActionAt: Double = 0

    init() {
        detector.onGesture = { [weak self] gesture in
            self?.handle(gesture)
        }

        ConfigStore.shared.$config
            .sink { [weak self] config in
                self?.apply(config)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .macTapAutoStart)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.isRunning else { return }
                guard ConfigStore.shared.config.enabled else { return }
                self.start()
            }
            .store(in: &cancellables)

        apply(ConfigStore.shared.config)
        SoundManager.shared.sync(from: ConfigStore.shared.config)
    }

    private func apply(_ config: AppConfig) {
        detector.sensitivity = config.sensitivity
        detector.groupingWindow = config.tapGroupingWindow
        detector.invertSides = config.invertSides
        detector.sideBias = config.sideBias
        detector.ignoreWhileTyping = config.ignoreWhileTyping
        detector.classifySides = config.layout == .sides
    }

    func start() {
        apply(ConfigStore.shared.config)
        sensor.start()
        isRunning = true
        NSLog("MacTap: engine started")
    }

    func stop() {
        sensor.stop()
        isRunning = false
        NSLog("MacTap: engine stopped")
    }

    func toggle() {
        if isRunning { stop() } else { start() }
    }

    private func handle(_ gesture: DetectedGesture) {
        let config = ConfigStore.shared.config
        lastGesture = gesture
        flashToken &+= 1
        hudGesture = gesture

        ConfigStore.shared.config.stats.record(tapCount: gesture.tapCount)
        ConfigStore.shared.save()

        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let slot = ConfigStore.shared.resolvedSlot(
            side: gesture.side,
            tapCount: gesture.tapCount,
            bundleID: frontID
        )
        if config.showHUD {
            HUDController.shared.flash(gesture, slot: slot)
        }

        if config.soundEnabled || SoundManager.shared.isEnabled {
            SoundManager.shared.playTapSound(side: gesture.side, tapCount: gesture.tapCount)
        }

        guard config.enabled else { return }

        let now = Date().timeIntervalSince1970
        if now - lastActionAt < config.actionCooldown { return }
        lastActionAt = now

        guard let slot, slot.actionType != .none else { return }

        lastExecutedSlot = slot
        let frontApp = NSWorkspace.shared.frontmostApplication
        DispatchQueue.main.async {
            ActionExecutor.shared.execute(slot, targeting: frontApp)
        }
    }
}

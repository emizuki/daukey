import DauKeyEngine

public struct TypingCore: Sendable {
    private var engine: Engine
    private var enabled: Bool
    private var toggle = ToggleDetector()
    private var memory: AppMemory
    private var tap: TapState = .starting
    private var currentNeedsInlineCompletionWorkaround = false
    private var targetIsSpotlight = false
    public init(enabled: Bool, options: Options, appMemory: [String: Bool]) {
        self.enabled = enabled
        engine = Engine(options: options)
        memory = AppMemory(memory: appMemory)
    }
    public var snapshot: Snapshot {
        Snapshot(enabled: enabled, options: engine.options, appMemory: memory.memory, tap: tap)
    }
    public mutating func keyDown(_ input: KeyInput) -> Decision {
        toggle.disturb()
        guard enabled else { return .pass }
        return OutputPlan.decision(for: engine.handle(KeyClassifier.classify(input)),
            inlineCompletionApp: currentNeedsInlineCompletionWorkaround, targetIsSpotlight: targetIsSpotlight)
    }
    public mutating func flagsChanged(_ modifiers: Modifiers) -> Bool {
        guard toggle.flagsChanged(modifiers) else { return false }
        enabled.toggle()
        memory.record(enabled)
        _ = engine.handle(.reset)
        return true
    }
    public mutating func mouseDown() { reset() }
    public mutating func keyTarget(isSpotlight: Bool) { targetIsSpotlight = isSpotlight }
    public mutating func appActivated(_ bundleID: String?, inlineCompletionApp: Bool) {
        reset()
        targetIsSpotlight = false
        if bundleID != "com.emizuki.daukey" {
            currentNeedsInlineCompletionWorkaround = bundleID != nil && inlineCompletionApp
        }
        memory.appActivated(bundleID, enabled: &enabled)
    }
    public mutating func setEnabled(_ value: Bool) {
        reset()
        enabled = value
        memory.record(value)
    }
    public mutating func setOptions(_ options: Options) {
        toggle.disturb()
        engine.options = options
    }
    public mutating func reset() {
        toggle.disturb()
        _ = engine.handle(.reset)
    }
    public mutating func setTap(_ value: TapState) { tap = value }
    public mutating func inputSourceChanged() { reset() }
}

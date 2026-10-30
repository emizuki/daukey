import Carbon
import DauKeyHook

/// The text shown for a shortcut. Keys that type a character are named by the current keyboard layout; other keys
/// have fixed names. A key the layout gives no visible character for shows its key code.
@MainActor enum ShortcutLabel {
    static func string(for config: ShortcutConfig) -> String {
        var parts: [String] = []
        if config.modifiers.contains(.control) { parts.append("⌃") }
        if config.modifiers.contains(.option) { parts.append("⌥") }
        if config.modifiers.contains(.shift) { parts.append("⇧") }
        if config.modifiers.contains(.command) { parts.append("⌘") }
        if let keyCode = config.keyCode { parts.append(name(of: keyCode)) }
        return parts.isEmpty ? "Chưa đặt" : parts.joined(separator: " + ")
    }

    private static func name(of keyCode: UInt16) -> String {
        if let name = fixedNames[keyCode] { return name }
        return layoutCharacter(keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    /// The character `keyCode` types without modifiers in the current keyboard layout, if it is visible.
    private static func layoutCharacter(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, characters.count, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: length)
        let visible = text.unicodeScalars.allSatisfy {
            !$0.properties.isWhitespace && $0.properties.generalCategory != .control
                && !(0xF700...0xF8FF).contains($0.value)
        }
        return visible ? text : nil
    }

    /// Keys that type no character; their key codes are the same in every layout.
    private static let fixedNames: [UInt16: String] = [
        0x31: "Space", 0x24: "Return", 0x4C: "Enter", 0x30: "Tab", 0x33: "Delete", 0x75: "Forward Delete",
        0x35: "Esc", 0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x73: "Home", 0x77: "End", 0x74: "Page Up",
        0x79: "Page Down", 0x72: "Help",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15", 0x6A: "F16",
        0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",
    ]
}

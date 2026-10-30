import DauKeyEngine

public enum KeyClassifier {
    /// Command and Control shortcuts, modified Backspace, navigation and forward delete have effects on the text the
    /// session cannot know, so they are `.reset`. Escape only ends the word.
    public static func classify(_ input: KeyInput) -> Event {
        if input.keyCode == 0x33 {
            return input.modifiers.intersection([.command, .option, .control]).isEmpty ? .backspace : .reset
        }
        if !input.modifiers.intersection([.command, .control]).isEmpty { return .reset }
        switch input.keyCode {
        case 0x35: return .endWord
        case 0x7B...0x7E, 0x73, 0x77, 0x74, 0x79, 0x75, 0x72: return .reset
        case 0x24, 0x4C: return .char("\n")
        case 0x30: return .char("\t")
        default: break
        }
        guard input.characters.count == 1, let character = input.characters.first,
              character.unicodeScalars.allSatisfy({
                  $0.properties.generalCategory != .control && !(0xF700...0xF8FF).contains($0.value)
              }) else { return .endWord }
        return .char(character)
    }
}

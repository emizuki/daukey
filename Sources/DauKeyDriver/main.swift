import DauKeyEngine
import DauKeyScript
import Foundation

/// Reads key scripts on stdin and prints `script<TAB>screen` per line.
/// Arguments: telex|vni old|modern off|check|restore (any order, defaults: telex old restore).
func parseOptions(_ arguments: [String]) -> Options? {
    var options = Options()
    for argument in arguments {
        switch argument {
        case "telex": options.inputMethod = .telex
        case "vni": options.inputMethod = .vni
        case "old": options.toneStyle = .old
        case "modern": options.toneStyle = .modern
        case "off": options.spelling = .off
        case "check": options.spelling = .check
        case "restore": options.spelling = .checkAndRestore
        default: return nil
        }
    }
    return options
}

guard let options = parseOptions(Array(CommandLine.arguments.dropFirst())) else {
    FileHandle.standardError.write("usage: daukey-driver [telex|vni] [old|modern] [off|check|restore]\n".data(using: .utf8)!)
    exit(2)
}

while let line = readLine(strippingNewline: true) {
    let screen = Typist.type(line, options: options)
        .replacingOccurrences(of: "\n", with: "\\N")
        .replacingOccurrences(of: "\t", with: "\\T")
    print("\(line)\t\(screen)")
}

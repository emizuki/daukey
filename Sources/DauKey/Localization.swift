import Foundation
import Observation

public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case vietnamese = "vi"
    case english = "en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vietnamese: return "Tiếng Việt"
        case .english: return "English"
        }
    }

    public var flag: String {
        switch self {
        case .vietnamese: return "🇻🇳"
        case .english: return "🇺🇸"
        }
    }
}

public enum L10nKey {
    case appLanguage
    case inputMethod
    case toggleShortcut
    case pressShortcutPlaceholder
    case soundFeedback
    case shorthand
    case openTable
    case toneStyleModern
    case toneStyleTooltip
    case spellCheck
    case spellCheckTooltip
    case autoRestore
    case autoRestoreTooltip
    case autoCapitalize
    case foreignConsonants
    case foreignConsonantsTooltip
    case perAppMemory
    case launchAtLogin
    case loginRequiresApproval
    case feedbackAndSupport
    case reset
    case resetHelp
    case resetConfirmTitle
    case resetConfirmMessage
    case resetConfirmAction
    case cancel
    case terminate
    case terminateHelp
    case permissionRequiredTitle
    case permissionRequiredDesc
    case openSystemSettings
    case permissionTip
    case checkAgain
    case shorthandWindowTitle
    case triggerColumn
    case replacementColumn
    case triggerPlaceholder
    case replacementPlaceholder
    case addRuleHelp
    case deleteRulesHelp
    case rulesCount(Int)
    case importRules
    case exportRules
    case invalidFileFormatTitle
    case invalidFileFormatMessage
    case cannotReadFileMessage
    case exclusions
    case exclusionsWindowTitle
    case exclusionColumn
    case exclusionPlaceholder
    case addExclusionHelp
    case deleteExclusionHelp
    case exclusionsCount(Int)
    case invalidExclusionFileMessage
    case contextMenuVietnamese
    case contextMenuReset
    case contextMenuQuit(String)
    case welcomeTitle
    case welcomeSubtitle
    case welcomeStep1
    case welcomeStep2
    case welcomeDone
    case welcomeOpenSettings
    case welcomePermissionGranted
    case menuBarTooltip(appName: String, enabled: Bool)
}

public enum L10n {
    public static func string(_ key: L10nKey, language: AppLanguage) -> String {
        switch language {
        case .vietnamese:
            return vietnameseString(key)
        case .english:
            return englishString(key)
        }
    }

    private static func vietnameseString(_ key: L10nKey) -> String {
        switch key {
        case .appLanguage: return "Ngôn ngữ"
        case .inputMethod: return "Kiểu gõ"
        case .toggleShortcut: return "Phím tắt chuyển đổi"
        case .pressShortcutPlaceholder: return "Nhập"
        case .soundFeedback: return "Âm thanh"
        case .shorthand: return "Gõ tắt"
        case .openTable: return "Mở bảng"
        case .toneStyleModern: return "Đặt dấu kiểu mới"
        case .toneStyleTooltip: return "Đặt dấu ở nguyên âm thứ hai (oà, uý) thay vì kiểu cũ (òa, úy)"
        case .spellCheck: return "Kiểm tra chính tả"
        case .spellCheckTooltip: return "Tự động phát hiện và kiểm tra các từ gõ theo quy tắc chính tả tiếng Việt"
        case .autoRestore: return "Tự động khôi phục"
        case .autoRestoreTooltip: return "Tự động hoàn trả từ gõ gốc nếu phát hiện sai chính tả khi bạn bấm phím cách"
        case .autoCapitalize: return "Viết hoa chữ cái đầu"
        case .foreignConsonants: return "Cho phép z, w, j, f"
        case .foreignConsonantsTooltip: return "Cho phép dùng các ký tự z, w, j, f làm phụ âm để thuận tiện gõ từ mượn và thuật ngữ quốc tế"
        case .perAppMemory: return "Ghi nhớ theo ứng dụng"
        case .launchAtLogin: return "Khởi động cùng máy"
        case .loginRequiresApproval: return "Cần duyệt trong Cài đặt › Mục đăng nhập"
        case .feedbackAndSupport: return "Phản hồi & hỗ trợ"
        case .reset: return "Đặt lại"
        case .resetHelp: return "Khôi phục toàn bộ cài đặt về mặc định"
        case .resetConfirmTitle: return "Đặt lại toàn bộ cài đặt?"
        case .resetConfirmMessage: return "Toàn bộ tùy chọn gõ, phím tắt và bộ nhớ ứng dụng sẽ trở về trạng thái ban đầu."
        case .resetConfirmAction: return "Đặt lại về mặc định"
        case .cancel: return "Hủy"
        case .terminate: return "Kết thúc"
        case .terminateHelp: return "Thoát hoàn toàn ứng dụng DauKey"
        case .permissionRequiredTitle: return "Cần cấp quyền Trợ năng"
        case .permissionRequiredDesc: return "DauKey cần quyền Trợ năng (Accessibility) để nhận diện phím và gõ tiếng Việt.\n\nBấm vào đây để mở Cài đặt và cấp quyền."
        case .openSystemSettings: return "Mở Cài đặt hệ thống"
        case .permissionTip: return "💡 Nếu đã bật trong Cài đặt mà vẫn chưa nhận: hãy xoá (-) DauKey khỏi danh sách Trợ năng rồi thêm (+) lại."
        case .checkAgain: return "Kiểm tra lại"
        case .shorthandWindowTitle: return "Thiết lập quy tắc gõ tắt"
        case .triggerColumn: return "Đầu vào"
        case .replacementColumn: return "Đầu ra"
        case .triggerPlaceholder: return "Từ gõ tắt"
        case .replacementPlaceholder: return "Cụm từ thay thế"
        case .addRuleHelp: return "Thêm dòng gõ tắt mới (+)"
        case .deleteRulesHelp: return "Xóa các dòng đang chọn (-)"
        case .rulesCount(let count): return "\(count) quy tắc"
        case .importRules: return "Nhập..."
        case .exportRules: return "Xuất..."
        case .invalidFileFormatTitle: return "Định dạng tệp không hợp lệ"
        case .invalidFileFormatMessage: return "Tệp CSV phải có đúng 2 cột (từ gõ tắt, cụm từ thay thế) trên mỗi dòng và không để trống."
        case .cannotReadFileMessage: return "Không thể đọc nội dung tệp. Vui lòng kiểm tra lại quyền truy cập tệp."
        case .exclusions: return "Ngoại lệ"
        case .exclusionsWindowTitle: return "Thiết lập danh sách ngoại lệ"
        case .exclusionColumn: return "Ngoại lệ"
        case .exclusionPlaceholder: return "Từ ngoại lệ (chỉ 1 từ, không dấu cách)"
        case .addExclusionHelp: return "Thêm từ ngoại lệ mới (+)"
        case .deleteExclusionHelp: return "Xóa các từ đang chọn (-)"
        case .exclusionsCount(let count): return "\(count) ngoại lệ"
        case .invalidExclusionFileMessage: return "Tệp CSV phải chứa từ ngoại lệ đơn trên mỗi dòng (không chứa khoảng trắng) và không để trống."
        case .contextMenuVietnamese: return "Gõ tiếng Việt"
        case .contextMenuReset: return "Đặt lại tùy chỉnh"
        case .contextMenuQuit(let appName): return "Thoát \(appName)"
        case .welcomeTitle: return "Chào mừng đến với DauKey"
        case .welcomeSubtitle: return "Hai bước nữa là gõ được tiếng Việt."
        case .welcomeStep1: return "1. Cho phép Trợ năng"
        case .welcomeStep2: return "2. Chọn kiểu gõ"
        case .welcomeDone: return "Xong"
        case .welcomeOpenSettings: return "Mở Cài đặt"
        case .welcomePermissionGranted: return "Đã cho phép Trợ năng"
        case .menuBarTooltip(let appName, let enabled): return "\(appName): \(enabled ? "bật" : "tắt")"
        }
    }

    private static func englishString(_ key: L10nKey) -> String {
        switch key {
        case .appLanguage: return "Language"
        case .inputMethod: return "Input method"
        case .toggleShortcut: return "Toggle shortcut"
        case .pressShortcutPlaceholder: return "Record"
        case .soundFeedback: return "Sound feedback"
        case .shorthand: return "Shorthand"
        case .openTable: return "Open table"
        case .toneStyleModern: return "Modern tone placement"
        case .toneStyleTooltip: return "Place tone mark on the second vowel (oà, uý) instead of the first (òa, úy)"
        case .spellCheck: return "Spell check"
        case .spellCheckTooltip: return "Automatically check typed words against Vietnamese spelling rules"
        case .autoRestore: return "Auto restore"
        case .autoRestoreTooltip: return "Automatically restore original typed letters on Space if misspelled"
        case .autoCapitalize: return "Auto capitalize"
        case .foreignConsonants: return "Allow z, w, j, f"
        case .foreignConsonantsTooltip: return "Allow z, w, j, f as consonants for loanwords and technical terms"
        case .perAppMemory: return "Per-app memory"
        case .launchAtLogin: return "Launch at login"
        case .loginRequiresApproval: return "Approval required in Settings › Login Items"
        case .feedbackAndSupport: return "Feedback & support"
        case .reset: return "Reset"
        case .resetHelp: return "Restore all settings to defaults"
        case .resetConfirmTitle: return "Reset all settings?"
        case .resetConfirmMessage: return "All typing options, shortcuts, and app memory will be restored to defaults."
        case .resetConfirmAction: return "Reset to defaults"
        case .cancel: return "Cancel"
        case .terminate: return "Quit"
        case .terminateHelp: return "Quit DauKey application"
        case .permissionRequiredTitle: return "Accessibility permission required"
        case .permissionRequiredDesc: return "DauKey requires Accessibility permission to detect keystrokes and type Vietnamese.\n\nClick here to open Settings and grant permission."
        case .openSystemSettings: return "Open system settings"
        case .permissionTip: return "💡 If already enabled in Settings: remove (-) DauKey from Accessibility and add (+) it back."
        case .checkAgain: return "Check again"
        case .shorthandWindowTitle: return "Shorthand rules setup"
        case .triggerColumn: return "Trigger"
        case .replacementColumn: return "Replacement"
        case .triggerPlaceholder: return "Shortcut text"
        case .replacementPlaceholder: return "Replacement text"
        case .addRuleHelp: return "Add new shorthand rule (+)"
        case .deleteRulesHelp: return "Delete selected rules (-)"
        case .rulesCount(let count): return "\(count) \(count == 1 ? "rule" : "rules")"
        case .importRules: return "Import..."
        case .exportRules: return "Export..."
        case .invalidFileFormatTitle: return "Invalid file format"
        case .invalidFileFormatMessage: return "The CSV file must have exactly 2 non-empty columns (trigger, replacement) per row."
        case .cannotReadFileMessage: return "Unable to read file content. Please check file permissions."
        case .contextMenuVietnamese: return "Vietnamese typing"
        case .contextMenuReset: return "Reset preferences"
        case .contextMenuQuit(let appName): return "Quit \(appName)"
        case .welcomeTitle: return "Welcome to DauKey"
        case .welcomeSubtitle: return "Just two steps to start typing Vietnamese."
        case .welcomeStep1: return "1. Allow accessibility"
        case .welcomeStep2: return "2. Select input method"
        case .welcomeDone: return "Done"
        case .exclusions: return "Exceptions"
        case .exclusionsWindowTitle: return "Exceptions setup"
        case .exclusionColumn: return "Exception"
        case .exclusionPlaceholder: return "Exception word (single word, no spaces)"
        case .addExclusionHelp: return "Add new exception word (+)"
        case .deleteExclusionHelp: return "Delete selected words (-)"
        case .exclusionsCount(let count): return "\(count) \(count == 1 ? "exception" : "exceptions")"
        case .invalidExclusionFileMessage: return "The CSV file must contain a single exception word on each line (without spaces) and not be empty."
        case .welcomeOpenSettings: return "Open settings"
        case .welcomePermissionGranted: return "Accessibility allowed"
        case .menuBarTooltip(let appName, let enabled): return "\(appName): \(enabled ? "on" : "off")"
        }
    }
}

/// The interface language, shown by every window, the menu and the tooltip; changes are saved through the store.
@MainActor @Observable
final class LocalizationManager {
    @ObservationIgnored private let store: PreferencesStore

    var currentLanguage: AppLanguage {
        didSet { store.saveLanguage(currentLanguage) }
    }

    init(language: AppLanguage, store: PreferencesStore) {
        currentLanguage = language
        self.store = store
    }

    func tr(_ key: L10nKey) -> String {
        L10n.string(key, language: currentLanguage)
    }
}

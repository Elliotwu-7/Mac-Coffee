import Foundation

public enum SupportedLanguage: String, CaseIterable, Codable, Sendable {
    case system
    case russian = "ru"
    case english = "en"
    case german = "de"
    case french = "fr"
    case simplifiedChinese = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"

    public var displayName: String {
        switch self {
        case .system:
            "System"
        case .russian:
            "Русский"
        case .english:
            "English"
        case .german:
            "Deutsch"
        case .french:
            "Français"
        case .simplifiedChinese:
            "简体中文"
        case .japanese:
            "日本語"
        case .korean:
            "한국어"
        case .spanish:
            "Español"
        }
    }
}

import Foundation

public protocol SettingsStoring: AnyObject {
    var selectedLanguage: SupportedLanguage { get set }
    var selectedDuration: SessionDuration { get set }
    var batteryThreshold: Int { get set }
    var launchAtLoginRequested: Bool { get set }
    var notificationAuthorizationRequested: Bool { get set }
    var lastAnnouncedUpdateVersion: String? { get set }
}

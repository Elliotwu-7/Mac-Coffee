import Combine
import Foundation

@MainActor
public final class LocalizationController: ObservableObject {
    @Published public private(set) var selectedLanguage: SupportedLanguage
    @Published public private(set) var locale: Locale

    private let settings: SettingsStoring
    private let preferredLanguages: () -> [String]
    private let bundle: Bundle

    public init(
        settings: SettingsStoring,
        preferredLanguages: @escaping () -> [String] = {
            Locale.preferredLanguages.isEmpty
                ? [Locale.current.identifier]
                : Locale.preferredLanguages
        },
        bundle: Bundle = .main
    ) {
        self.settings = settings
        self.preferredLanguages = preferredLanguages
        self.bundle = bundle
        let language = settings.selectedLanguage
        selectedLanguage = language
        locale = Self.resolvedLocale(for: language, preferredLanguages: preferredLanguages())
    }

    public convenience init(
        settings: SettingsStoring,
        systemLocale: @escaping () -> Locale,
        bundle: Bundle = .main
    ) {
        self.init(
            settings: settings,
            preferredLanguages: { [systemLocale().identifier] },
            bundle: bundle
        )
    }

    public func select(_ language: SupportedLanguage) {
        selectedLanguage = language
        settings.selectedLanguage = language
        locale = Self.resolvedLocale(for: language, preferredLanguages: preferredLanguages())
    }

    public func refreshSystemLocale() {
        guard selectedLanguage == .system else { return }
        locale = Self.resolvedLocale(
            for: selectedLanguage,
            preferredLanguages: preferredLanguages()
        )
    }

    public func localized(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    public func format(_ key: String, arguments: CVarArg...) -> String {
        String(format: localized(key), locale: locale, arguments: arguments)
    }

    private static func resolvedLocale(
        for language: SupportedLanguage,
        preferredLanguages: [String]
    ) -> Locale {
        guard language == .system else { return Locale(identifier: language.rawValue) }

        let resolvedLanguage = preferredLanguages.lazy.compactMap(resolvedLanguage(for:)).first
        return Locale(identifier: (resolvedLanguage ?? .english).rawValue)
    }

    private static func resolvedLanguage(for preferredIdentifier: String) -> SupportedLanguage? {
        let identifier = preferredIdentifier.replacingOccurrences(of: "_", with: "-")
        let components = identifier.split(separator: "-").map(String.init)
        let baseLanguage = components.first?.lowercased()
        let languageSubtags = components.dropFirst().map { $0.lowercased() }
        let isTraditionalChinese = languageSubtags.contains("hant")
            || languageSubtags.contains(where: ["tw", "hk", "mo"].contains)

        if baseLanguage == "zh", !isTraditionalChinese {
            return .simplifiedChinese
        } else if let baseLanguage {
            return SupportedLanguage(rawValue: baseLanguage)
        }
        return nil
    }

    private var localizedBundle: Bundle {
        let candidates = [
            locale.identifier.replacingOccurrences(of: "_", with: "-"),
            locale.language.languageCode?.identifier
        ].compactMap { $0 }
        for identifier in candidates {
            if let localizationURL = bundle.url(
                forResource: identifier,
                withExtension: "lproj"
            ), let localizedBundle = Bundle(url: localizationURL) {
                return localizedBundle
            }
        }
        return bundle
    }
}

import SwiftUI

public struct AboutView: View {
    public static let privacyPolicyURL = URL(
        string: "https://github.com/rekurt/Mac-Coffee/blob/main/PRIVACY.md"
    )
    public static let supportURL = URL(
        string: "https://github.com/rekurt/Mac-Coffee/issues"
    )

    @ObservedObject private var localization: LocalizationController

    public init(localization: LocalizationController) {
        _localization = ObservedObject(wrappedValue: localization)
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("about.title")
                .font(.title2.bold())
            Text(versionText)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("maccoffee.about.version")
            Text("about.description")
                .multilineTextAlignment(.center)
            Text("about.privacy")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 14) {
                if let privacyPolicyURL = AboutView.privacyPolicyURL {
                    Link("about.privacyPolicy", destination: privacyPolicyURL)
                        .accessibilityIdentifier("maccoffee.about.privacyPolicy")
                }
                if let supportURL = AboutView.supportURL {
                    Link("about.support", destination: supportURL)
                        .accessibilityIdentifier("maccoffee.about.support")
                }
            }
            .font(.caption)
            Text("about.limitations")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 380)
        .accessibilityIdentifier("maccoffee.about.content")
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"
        return localization.format("about.versionFormat", arguments: version, build)
    }
}

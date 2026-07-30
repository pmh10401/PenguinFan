import Foundation

enum ProductBrand {
    static let displayName = "PenguinFan"
    static let settingsTitle = "\(displayName) 설정"
    static let diagnosticsTitle = "\(displayName) 진단"

    static var currentVersionText: String {
        versionText(
            version: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        )
    }

    static func versionText(version: String?) -> String {
        guard let version,
              !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return displayName
        }
        return "\(displayName) \(version)"
    }
}

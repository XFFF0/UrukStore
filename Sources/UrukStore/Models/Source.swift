import Foundation

/// A "repo" — a JSON feed listing apps available for install.
/// Schema is compatible with AltStore/SideStore source format so existing
/// community repos can be added directly without conversion.
struct Source: Codable, Identifiable, Hashable {
    var id: String { identifier }
    let name: String
    let identifier: String
    let subtitle: String?
    let description: String?
    let iconURL: URL?
    let website: URL?
    let apps: [StoreApp]

    enum CodingKeys: String, CodingKey {
        case name
        case identifier
        case subtitle
        case description
        case iconURL = "iconURL"
        case website
        case apps
    }
}

struct StoreApp: Codable, Identifiable, Hashable {
    var id: String { bundleIdentifier }
    let name: String
    let bundleIdentifier: String
    let developerName: String?
    let subtitle: String?
    let localizedDescription: String
    let iconURL: URL?
    let screenshotURLs: [URL]?
    let versions: [StoreAppVersion]

    /// Convenience: latest version entry, if present.
    var latestVersion: StoreAppVersion? { versions.first }
}

struct StoreAppVersion: Codable, Hashable {
    let version: String
    let date: String?
    let size: Int?
    let downloadURL: URL
    let minOSVersion: String?
    let localizedDescription: String?
}

/// Locally tracked record of an app UrukStore has installed/signed on-device.
/// This is app-local state, not part of the source schema above.
struct InstalledApp: Codable, Identifiable, Hashable {
    let id: UUID
    let bundleIdentifier: String
    let name: String
    let version: String
    let sourceIdentifier: String?
    let installedDate: Date
    let expirationDate: Date?
    let iconURL: URL?
}

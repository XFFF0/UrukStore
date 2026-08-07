import Foundation
import ZIPFoundation

enum IPAInspectorError: Error, LocalizedError {
    case notAZip
    case appBundleNotFound
    case infoPlistNotFound
    case missingBundleIdentifier

    var errorDescription: String? {
        switch self {
        case .notAZip: return "That file isn't a valid .ipa (zip)."
        case .appBundleNotFound: return "Couldn't find a .app bundle inside the IPA's Payload folder."
        case .infoPlistNotFound: return "Couldn't find Info.plist inside the .app bundle."
        case .missingBundleIdentifier: return "Info.plist has no CFBundleIdentifier."
        }
    }
}

/// Reads just enough out of a local .ipa to know what we're signing —
/// specifically its bundle identifier, which Apple's provisioning profile
/// has to be registered against. An .ipa is a zip with a fixed layout:
/// Payload/<AppName>.app/Info.plist.
struct IPAInspector {
    static func bundleIdentifier(ofIPAAt url: URL) throws -> String {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw IPAInspectorError.notAZip
        }

        guard let appEntry = archive.first(where: { entry in
            let path = entry.path
            return path.hasPrefix("Payload/") && path.hasSuffix(".app/Info.plist")
        }) else {
            throw IPAInspectorError.appBundleNotFound
        }

        let tempPlistURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".plist")
        defer { try? FileManager.default.removeItem(at: tempPlistURL) }

        _ = try archive.extract(appEntry, to: tempPlistURL)

        guard let data = try? Data(contentsOf: tempPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw IPAInspectorError.infoPlistNotFound
        }

        guard let bundleIdentifier = plist["CFBundleIdentifier"] as? String else {
            throw IPAInspectorError.missingBundleIdentifier
        }

        return bundleIdentifier
    }
}

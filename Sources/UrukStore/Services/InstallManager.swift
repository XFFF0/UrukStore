import Foundation

enum InstallError: Error, LocalizedError {
    case notImplemented

    var errorDescription: String? {
        "Wireless install is not implemented in this build yet — see README roadmap."
    }
}

@MainActor
final class InstallManager: ObservableObject {
    @Published private(set) var installedApps: [InstalledApp] = []

    private let signingService: SigningServicing
    private let storageKey = "urukstore.installed.apps"

    init(signingService: SigningServicing = SigningService()) {
        self.signingService = signingService
        load()
    }

    /// End-to-end install flow (phase 2, currently unimplemented):
    ///   1. Download the IPA from `StoreAppVersion.downloadURL`
    ///   2. Resign it via `signingService`
    ///   3. Push it to the device over the local network using the
    ///      lockdown/AFC install protocol (same one Xcode's wireless
    ///      debugging uses) — no cable or Mac required at install time
    ///   4. Record it in `installedApps` with its 7-day expiration so the
    ///      UI can warn before Apple's free-account signing expires
    func install(_ app: StoreApp, from source: Source) async throws {
        throw InstallError.notImplemented
    }

    func daysUntilExpiration(for app: InstalledApp) -> Int? {
        guard let expiration = app.expirationDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiration).day
        return days
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([InstalledApp].self, from: data) else {
            return
        }
        installedApps = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(installedApps) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

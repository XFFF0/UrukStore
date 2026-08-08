import Foundation

enum InstallError: Error, LocalizedError {
    case notSignedIn
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in with your Apple ID in Settings first."
        case .downloadFailed:
            return "Couldn't download the app's IPA."
        }
    }
}

@MainActor
final class InstallManager: ObservableObject {
    @Published private(set) var installedApps: [InstalledApp] = []
    @Published private(set) var signingIdentity: SigningIdentity?

    private var signingService: SigningServicing?
    private let storageKey = "urukstore.installed.apps"

    init() {
        load()
    }

    /// Call once, e.g. from Settings, before installing anything.
    /// `anisetteServerURL` — see AnisetteClient.swift for what this needs to point to.
    func signIn(appleID: String, password: String, anisetteServerURL: URL, twoFactorCodeProvider: @escaping () async -> String?) async throws {
        let service = SigningService(anisetteServerURL: anisetteServerURL, twoFactorCodeProvider: twoFactorCodeProvider)
        self.signingIdentity = try await service.authenticate(appleID: appleID, password: password)
        self.signingService = service
    }

    func signOut() {
        signingIdentity = nil
        signingService = nil
    }

    /// Signs a local .ipa and, if a pairing file has been imported (see
    /// DeviceConnection), installs it straight to the device over the
    /// local VPN tunnel — no cable, no companion Mac. Falls back to just
    /// returning the signed file (for sharing into LiveContainer etc.) if
    /// no pairing file is set up yet.
    func signLocalIPA(at sourceURL: URL) async throws -> URL {
        guard let signingService, let identity = signingIdentity else {
            throw InstallError.notSignedIn
        }

        let bundleIdentifier = try IPAInspector.bundleIdentifier(ofIPAAt: sourceURL)

        let workingURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        try FileManager.default.copyItem(at: sourceURL, to: workingURL)

        let signedURL = try await signingService.resign(ipaURL: workingURL, identity: identity, bundleIdentifier: bundleIdentifier)

        if DeviceConnection.shared.hasPairingFile {
            let signedData = try Data(contentsOf: signedURL)
            try await DeviceConnection.shared.install(ipaData: signedData, bundleIdentifier: bundleIdentifier)
        }

        let signedDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Signed", isDirectory: true)
        try FileManager.default.createDirectory(at: signedDirectory, withIntermediateDirectories: true)

        let destinationURL = signedDirectory.appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + "-signed.ipa")
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: signedURL, to: destinationURL)

        return destinationURL
    }

    /// Full flow: download -> sign -> push to device over the local VPN
    /// tunnel via minimuxer (same mechanism SideStore uses with StosVPN +
    /// an imported pairing file) -> install.
    func install(_ app: StoreApp, from source: Source) async throws {
        guard let signingService, let identity = signingIdentity else {
            throw InstallError.notSignedIn
        }
        guard let version = app.latestVersion else { throw InstallError.downloadFailed }

        let (downloadedURL, response) = try await URLSession.shared.download(from: version.downloadURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw InstallError.downloadFailed
        }

        let workingURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        try FileManager.default.moveItem(at: downloadedURL, to: workingURL)

        let signedURL = try await signingService.resign(ipaURL: workingURL, identity: identity, bundleIdentifier: app.bundleIdentifier)
        let signedData = try Data(contentsOf: signedURL)

        try await DeviceConnection.shared.install(ipaData: signedData, bundleIdentifier: app.bundleIdentifier)

        let installed = InstalledApp(
            id: UUID(),
            bundleIdentifier: app.bundleIdentifier,
            name: app.name,
            version: version.version,
            sourceIdentifier: source.identifier,
            installedDate: Date(),
            expirationDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
            iconURL: app.iconURL
        )
        installedApps.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
        installedApps.append(installed)
        save()
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

import Foundation

enum InstallError: Error, LocalizedError {
    case notSignedIn
    case wirelessInstallNotImplemented
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in with your Apple ID in Settings first."
        case .wirelessInstallNotImplemented:
            return "App was signed successfully, but getting it onto the device without a cable isn't implemented yet — see README roadmap."
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

    /// Signs a local .ipa (picked from Files) and saves the result into the
    /// app's own Documents/Signed folder, returning its URL so the caller
    /// can share it out (e.g. via ShareLink into LiveContainer, AirDrop, or
    /// the Files app) — this works today without needing the wireless
    /// install piece below, since importing a signed .ipa into a sideloading
    /// container doesn't go through Apple's install protocol at all.
    func signLocalIPA(at sourceURL: URL) async throws -> URL {
        guard let signingService, let identity = signingIdentity else {
            throw InstallError.notSignedIn
        }

        let bundleIdentifier = try IPAInspector.bundleIdentifier(ofIPAAt: sourceURL)

        let workingURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        try FileManager.default.copyItem(at: sourceURL, to: workingURL)

        let signedURL = try await signingService.resign(ipaURL: workingURL, identity: identity, bundleIdentifier: bundleIdentifier)

        let signedDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Signed", isDirectory: true)
        try FileManager.default.createDirectory(at: signedDirectory, withIntermediateDirectories: true)

        let destinationURL = signedDirectory.appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + "-signed.ipa")
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: signedURL, to: destinationURL)

        return destinationURL
    }

    /// Real flow as far as it currently goes:
    ///   1. Download the IPA from `StoreAppVersion.downloadURL`               ✅ implemented
    ///   2. Resign it via AltSign (real Apple Developer API calls)            ✅ implemented
    ///   3. Push it to the device without a cable                            ❌ not implemented
    ///   4. Track it here with its 7-day expiration                         (blocked on step 3)
    ///
    /// Step 3 is SideStore's "EM Proxy" — a VPN tunnel + on-device lockdown-
    /// muxer replica that tricks iOS into accepting the install locally.
    /// That's a project of its own; see README roadmap.
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

        _ = try await signingService.resign(ipaURL: workingURL, identity: identity, bundleIdentifier: app.bundleIdentifier)

        // Signing succeeded — the .ipa at workingURL is now signed and
        // valid, but actually getting it onto the device (untethered)
        // needs the EM Proxy-style tunnel described above.
        throw InstallError.wirelessInstallNotImplemented
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

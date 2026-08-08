import Foundation

enum InstallError: Error, LocalizedError {
    case notSignedIn
    case downloadFailed(URL, String)
    case stageFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in with your Apple ID in Settings first."
        case .downloadFailed(let url, let reason):
            return "Couldn't download from \(url.host ?? url.absoluteString): \(reason)"
        case .stageFailed(let stage, let reason):
            return "Failed during \(stage): \(reason)"
        }
    }
}

/// Runs a throwing step and, if it fails, rethrows with the stage name
/// attached — so an error onscreen says e.g. "Failed during device
/// install: ..." instead of a bare NSURLErrorDomain code with no context
/// about which of the several network calls in the pipeline caused it.
private func stage<T>(_ name: String, _ work: () async throws -> T) async throws -> T {
    do {
        return try await work()
    } catch let error as InstallError {
        throw error
    } catch {
        throw InstallError.stageFailed(name, error.localizedDescription)
    }
}

@MainActor
final class InstallManager: ObservableObject {
    @Published private(set) var installedApps: [InstalledApp] = []
    @Published private(set) var signingIdentity: SigningIdentity?
    @Published private(set) var isRestoringSession = false

    private var signingService: SigningServicing?
    private let storageKey = "urukstore.installed.apps"
    private let anisetteURLKey = "urukstore.anisette.serverURL"

    init() {
        load()
        Task { await restoreSessionIfPossible() }
    }

    /// Call once, e.g. from Settings, before installing anything.
    /// `anisetteServerURL` — see AnisetteClient.swift for what this needs to point to.
    func signIn(appleID: String, password: String, anisetteServerURL: URL, twoFactorCodeProvider: @escaping () async -> String?) async throws {
        UserDefaults.standard.set(anisetteServerURL.absoluteString, forKey: anisetteURLKey)
        let service = SigningService(anisetteServerURL: anisetteServerURL, twoFactorCodeProvider: twoFactorCodeProvider)
        self.signingIdentity = try await service.authenticate(appleID: appleID, password: password)
        self.signingService = service
    }

    /// Rebuilds the session from Keychain on launch, so signing back in
    /// after force-quitting the app isn't needed every time.
    private func restoreSessionIfPossible() async {
        guard SessionKeychain.load() != nil,
              let urlString = UserDefaults.standard.string(forKey: anisetteURLKey),
              let anisetteServerURL = URL(string: urlString) else { return }

        isRestoringSession = true
        let service = SigningService(anisetteServerURL: anisetteServerURL)
        if let identity = try? await service.restoreSession() {
            self.signingIdentity = identity
            self.signingService = service
        }
        isRestoringSession = false
    }

    func signOut() {
        signingIdentity = nil
        signingService = nil
        SessionKeychain.clear()
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

        let signedURL = try await stage("signing") {
            try await signingService.resign(ipaURL: workingURL, identity: identity, bundleIdentifier: bundleIdentifier)
        }

        if DeviceConnection.shared.hasPairingFile {
            let signedData = try Data(contentsOf: signedURL)
            try await stage("device install") {
                try await DeviceConnection.shared.install(ipaData: signedData, bundleIdentifier: bundleIdentifier)
            }
        }

        let signedDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Signed", isDirectory: true)
        try FileManager.default.createDirectory(at: signedDirectory, withIntermediateDirectories: true)

        let destinationURL = signedDirectory.appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + "-signed.ipa")
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: signedURL, to: destinationURL)

        return destinationURL
    }

    /// Some source CDNs (e.g. apps.altstore.io) sit behind bot-protection
    /// that rejects requests without a normal-looking User-Agent, and a
    /// plain background `URLSession.download(from:)` task is pickier about
    /// server responses than a one-shot fetch — switched to `data(from:)`
    /// for a simpler, more tolerant path with the actual failure surfaced
    /// instead of a bare NSURLErrorDomain code.
    private static func downloadIPA(from url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw InstallError.downloadFailed(url, error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw InstallError.downloadFailed(url, "no HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw InstallError.downloadFailed(url, "HTTP \(http.statusCode)")
        }

        let workingURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        try data.write(to: workingURL)
        return workingURL
    }

    /// Full flow: download -> sign -> push to device over the local VPN
    /// tunnel via minimuxer (same mechanism SideStore uses with StosVPN +
    /// an imported pairing file) -> install.
    func install(_ app: StoreApp, from source: Source) async throws {
        guard let signingService, let identity = signingIdentity else {
            throw InstallError.notSignedIn
        }
        guard let version = app.latestVersion else {
            throw InstallError.downloadFailed(source.website ?? URL(string: "about:blank")!, "no downloadable version listed")
        }

        let workingURL = try await Self.downloadIPA(from: version.downloadURL)

        let signedURL = try await stage("signing") {
            try await signingService.resign(ipaURL: workingURL, identity: identity, bundleIdentifier: app.bundleIdentifier)
        }
        let signedData = try Data(contentsOf: signedURL)

        try await stage("device install") {
            try await DeviceConnection.shared.install(ipaData: signedData, bundleIdentifier: app.bundleIdentifier)
        }

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

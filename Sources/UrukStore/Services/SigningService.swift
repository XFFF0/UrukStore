import Foundation
import AltSign

enum SigningError: Error, LocalizedError {
    case requiresTwoFactorAuthentication
    case noTeamsFound
    case certificateFailed
    case appIDFailed
    case provisioningProfileFailed
    case signingFailed(String)

    var errorDescription: String? {
        switch self {
        case .requiresTwoFactorAuthentication:
            return "This Apple ID needs a two-factor code."
        case .noTeamsFound:
            return "No development teams found for this Apple ID."
        case .certificateFailed:
            return "Couldn't obtain a signing certificate for this team."
        case .appIDFailed:
            return "Couldn't register or fetch the App ID."
        case .provisioningProfileFailed:
            return "Couldn't obtain a provisioning profile."
        case .signingFailed(let message):
            return "Signing failed: \(message)"
        }
    }
}

/// Everything needed to resign further apps without re-authenticating:
/// the account, the chosen team, and the API session (dsid + auth token +
/// the anisette data used to obtain it — Apple's session tokens are tied
/// to the anisette they were issued with).
struct SigningIdentity {
    let account: ALTAccount
    let team: ALTTeam
    let session: ALTAppleAPISession
}

protocol SigningServicing {
    func authenticate(appleID: String, password: String) async throws -> SigningIdentity
    func restoreSession() async throws -> SigningIdentity
    func resign(ipaURL: URL, identity: SigningIdentity, bundleIdentifier: String) async throws -> URL
    func fetchAppIDs(identity: SigningIdentity) async throws -> [ALTAppID]
    func revokeAppID(_ appID: ALTAppID, identity: SigningIdentity) async throws
}

/// Real implementation backed by AltSign (https://github.com/SideStore/AltSign),
/// the same library AltStore/SideStore use. Two things this needs from the
/// caller:
///   - `anisetteServerURL`: see AnisetteClient.swift
///   - a two-factor code, supplied through `twoFactorCodeProvider` when
///     Apple asks for one (SMS or trusted-device code)
final class SigningService: SigningServicing {
    var anisetteServerURL: URL
    var twoFactorCodeProvider: (() async -> String?)?

    init(anisetteServerURL: URL, twoFactorCodeProvider: (() async -> String?)? = nil) {
        self.anisetteServerURL = anisetteServerURL
        self.twoFactorCodeProvider = twoFactorCodeProvider
    }

    func authenticate(appleID: String, password: String) async throws -> SigningIdentity {
        let anisette = try await AnisetteClient(serverURL: anisetteServerURL).fetch()

        let (account, session) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(ALTAccount, ALTAppleAPISession), Error>) in
            ALTAppleAPI.shared.authenticate(
                appleID: appleID,
                password: password,
                anisetteData: anisette,
                verificationHandler: { [weak self] respond in
                    guard let self, let provider = self.twoFactorCodeProvider else {
                        respond(nil)
                        return
                    }
                    Task {
                        let code = await provider()
                        respond(code)
                    }
                },
                completionHandler: { account, session, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let account, let session {
                        continuation.resume(returning: (account, session))
                    } else {
                        continuation.resume(throwing: SigningError.requiresTwoFactorAuthentication)
                    }
                }
            )
        }

        let teams = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ALTTeam], Error>) in
            ALTAppleAPI.shared.fetchTeams(for: account, session: session) { teams, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: teams ?? []) }
            }
        }

        guard let team = teams.first else { throw SigningError.noTeamsFound }

        SessionKeychain.save(PersistedSession(
            appleID: account.appleID,
            accountIdentifier: account.identifier,
            firstName: account.firstName,
            lastName: account.lastName,
            teamName: team.name,
            teamIdentifier: team.identifier,
            teamType: team.type.rawValue,
            dsid: session.dsid,
            authToken: session.authToken
        ))

        return SigningIdentity(account: account, team: team, session: session)
    }

    /// Rebuilds a session from the dsid/authToken saved in Keychain — Apple's
    /// session tokens outlive any single anisette payload, so a fresh one is
    /// fetched here rather than trying to reuse whatever was used at login.
    func restoreSession() async throws -> SigningIdentity {
        guard let saved = SessionKeychain.load() else {
            throw SigningError.noTeamsFound
        }

        let account = ALTAccount()
        account.appleID = saved.appleID
        account.identifier = saved.accountIdentifier
        account.firstName = saved.firstName
        account.lastName = saved.lastName

        guard let teamType = ALTTeamType(rawValue: saved.teamType) else {
            throw SigningError.noTeamsFound
        }
        let team = ALTTeam(name: saved.teamName, identifier: saved.teamIdentifier, type: teamType, account: account)

        let anisette = try await AnisetteClient(serverURL: anisetteServerURL).fetch()
        let session = ALTAppleAPISession(dsid: saved.dsid, authToken: saved.authToken, anisetteData: anisette)

        return SigningIdentity(account: account, team: team, session: session)
    }

    func resign(ipaURL: URL, identity: SigningIdentity, bundleIdentifier: String) async throws -> URL {
        let team = identity.team
        let session = identity.session

        // 0. .ipa is just a zip of Payload/<Name>.app — ALTSigner signs an
        //    extracted .app bundle directory, not the .ipa file itself, so
        //    unzip first and re-zip at the end.
        let workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: ipaURL, to: workDirectory)

        let payloadDirectory = workDirectory.appendingPathComponent("Payload", isDirectory: true)
        guard let appName = try FileManager.default.contentsOfDirectory(atPath: payloadDirectory.path).first(where: { $0.hasSuffix(".app") }) else {
            throw SigningError.signingFailed("No .app bundle found inside Payload/")
        }
        let appBundleURL = payloadDirectory.appendingPathComponent(appName)

        // 1. Reuse an existing certificate for this machine if one exists,
        //    otherwise request a new one (this also generates the private
        //    key and attaches it to the returned ALTCertificate).
        let certificate = try await fetchOrCreateCertificate(team: team, session: session)

        // 2. Make sure an App ID is registered for this bundle identifier.
        let appID = try await fetchOrCreateAppID(bundleIdentifier: bundleIdentifier, team: team, session: session)

        // 3. Get a provisioning profile tying the App ID + certificate + team together.
        let profile = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ALTProvisioningProfile, Error>) in
            ALTAppleAPI.shared.fetchProvisioningProfile(for: appID, deviceType: .iphone, team: team, session: session) { profile, error in
                if let error { continuation.resume(throwing: error) }
                else if let profile { continuation.resume(returning: profile) }
                else { continuation.resume(throwing: SigningError.provisioningProfileFailed) }
            }
        }

        // 4. Sign the extracted .app bundle in place with ldid (bundled inside AltSign).
        let signer = ALTSigner(team: team, certificate: certificate)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            _ = signer.signApp(at: appBundleURL, provisioningProfiles: [profile]) { success, error in
                if success { continuation.resume() }
                else { continuation.resume(throwing: SigningError.signingFailed(error?.localizedDescription ?? "unknown")) }
            }
        }

        // 5. Re-zip Payload/ (now containing the signed .app) into a fresh .ipa.
        let signedIPAURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        try FileManager.default.zipItem(at: payloadDirectory, to: signedIPAURL, shouldKeepParent: true)

        return signedIPAURL
    }

    // MARK: - Private helpers

    private func fetchOrCreateCertificate(team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTCertificate {
        let existing = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ALTCertificate], Error>) in
            ALTAppleAPI.shared.fetchCertificates(for: team, session: session) { certificates, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: certificates ?? []) }
            }
        }

        // A free/individual Apple ID account only allows a couple of active
        // certificates at once — shared across every tool signing with this
        // Apple ID (SideStore, AltStore, UrukStore, Xcode itself, etc). If
        // we already have a cached private key for one of the existing
        // certificates (a previous UrukStore run on this device), reuse it.
        // Otherwise we can't sign with it (Apple only returns a cert's
        // private key once, at creation time), so revoke it to make room
        // and request a fresh one.
        if let cached = existing.first(where: { CertificateKeychain.privateKey(forSerialNumber: $0.serialNumber) != nil }) {
            cached.privateKey = CertificateKeychain.privateKey(forSerialNumber: cached.serialNumber)
            return cached
        }

        for certificate in existing {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                ALTAppleAPI.shared.revoke(certificate, for: team, session: session) { success, error in
                    if success { continuation.resume() }
                    else { continuation.resume(throwing: error ?? SigningError.certificateFailed) }
                }
            }
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ALTCertificate, Error>) in
            ALTAppleAPI.shared.addCertificate(machineName: "UrukStore", to: team, session: session) { certificate, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let certificate {
                    if let privateKey = certificate.privateKey {
                        CertificateKeychain.savePrivateKey(privateKey, forSerialNumber: certificate.serialNumber)
                    }
                    continuation.resume(returning: certificate)
                } else {
                    continuation.resume(throwing: SigningError.certificateFailed)
                }
            }
        }
    }

    private func fetchOrCreateAppID(bundleIdentifier: String, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTAppID {
        let existing = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ALTAppID], Error>) in
            ALTAppleAPI.shared.fetchAppIDs(for: team, session: session) { appIDs, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: appIDs ?? []) }
            }
        }

        if let match = existing.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return match
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ALTAppID, Error>) in
            ALTAppleAPI.shared.addAppID(withName: "UrukStore App", bundleIdentifier: bundleIdentifier, team: team, session: session) { appID, error in
                if let error { continuation.resume(throwing: error) }
                else if let appID { continuation.resume(returning: appID) }
                else { continuation.resume(throwing: SigningError.appIDFailed) }
            }
        }
    }

    /// Lists every App ID currently registered on this team — useful since
    /// free accounts only get 10 new App ID registrations per week, so
    /// being able to see and revoke old ones (e.g. from earlier signing
    /// attempts, or other tools like SideStore) matters in practice.
    func fetchAppIDs(identity: SigningIdentity) async throws -> [ALTAppID] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ALTAppID], Error>) in
            ALTAppleAPI.shared.fetchAppIDs(for: identity.team, session: identity.session) { appIDs, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: appIDs ?? []) }
            }
        }
    }

    func revokeAppID(_ appID: ALTAppID, identity: SigningIdentity) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ALTAppleAPI.shared.deleteAppID(appID, for: identity.team, session: identity.session) { success, error in
                if success { continuation.resume() }
                else { continuation.resume(throwing: error ?? SigningError.appIDFailed) }
            }
        }
    }
}

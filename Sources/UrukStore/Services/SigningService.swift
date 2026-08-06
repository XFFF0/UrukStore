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
    func resign(ipaURL: URL, identity: SigningIdentity, bundleIdentifier: String) async throws -> URL
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
        return SigningIdentity(account: account, team: team, session: session)
    }

    func resign(ipaURL: URL, identity: SigningIdentity, bundleIdentifier: String) async throws -> URL {
        let team = identity.team
        let session = identity.session

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

        // 4. Sign the .app bundle in place with ldid (bundled inside AltSign).
        let signer = ALTSigner(team: team, certificate: certificate)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            _ = signer.signApp(at: ipaURL, provisioningProfiles: [profile]) { success, error in
                if success { continuation.resume() }
                else { continuation.resume(throwing: SigningError.signingFailed(error?.localizedDescription ?? "unknown")) }
            }
        }

        return ipaURL
    }

    // MARK: - Private helpers

    private func fetchOrCreateCertificate(team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTCertificate {
        let existing = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ALTCertificate], Error>) in
            ALTAppleAPI.shared.fetchCertificates(for: team, session: session) { certificates, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: certificates ?? []) }
            }
        }

        // A free Apple ID account is limited to two active certificates
        // total, shared across every app they sign with AltStore/SideStore/
        // UrukStore/etc. If one already exists, reuse it — its private key
        // only lives in this call's response, so this only works if we
        // cached it from a previous run (not implemented yet: Keychain
        // storage of certificate.privateKey). For now we always request a
        // fresh certificate, which is correct on first run but will hit
        // Apple's two-certificate limit on repeated runs until Keychain
        // caching is added.
        _ = existing

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ALTCertificate, Error>) in
            ALTAppleAPI.shared.addCertificate(machineName: "UrukStore", to: team, session: session) { certificate, error in
                if let error { continuation.resume(throwing: error) }
                else if let certificate { continuation.resume(returning: certificate) }
                else { continuation.resume(throwing: SigningError.certificateFailed) }
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
}

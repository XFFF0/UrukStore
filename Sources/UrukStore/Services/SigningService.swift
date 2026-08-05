import Foundation

/// Represents the free/paid Apple Developer identity used to re-sign IPAs.
struct SigningIdentity: Codable {
    let appleID: String
    let teamID: String
    let isFreeAccount: Bool
}

enum SigningError: Error, LocalizedError {
    case notImplemented
    case notAuthenticated
    case brokerUnavailable

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Signing is not implemented in this build yet — see README roadmap."
        case .notAuthenticated:
            return "No signing identity configured. Sign in with an Apple ID first."
        case .brokerUnavailable:
            return "Could not reach the signing broker service."
        }
    }
}

/// Abstraction over "however we get a signed IPA back". On-device signing
/// isn't possible without a valid provisioning profile + private key, which
/// in turn requires talking to Apple's developerservices2 API the same way
/// Xcode/AltServer do. That negotiation is intentionally kept behind this
/// protocol so it can be swapped between:
///   1. A companion signing broker (small server you run, holds the Apple
///      Developer session, mirrors what AltServer/anisette-server do), or
///   2. A future on-device implementation if/when that becomes feasible.
///
/// Not implemented yet — this is the phase-2 milestone described in the
/// README. Calling any of these currently throws `.notImplemented`.
protocol SigningServicing {
    func authenticate(appleID: String, password: String) async throws -> SigningIdentity
    func resign(ipaURL: URL, identity: SigningIdentity, bundleIdentifier: String) async throws -> URL
}

final class SigningService: SigningServicing {
    func authenticate(appleID: String, password: String) async throws -> SigningIdentity {
        throw SigningError.notImplemented
    }

    func resign(ipaURL: URL, identity: SigningIdentity, bundleIdentifier: String) async throws -> URL {
        throw SigningError.notImplemented
    }
}

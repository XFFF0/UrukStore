import Foundation
import AltSign

enum AnisetteError: Error, LocalizedError {
    case unreachable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unreachable: return "Could not reach the anisette server."
        case .invalidResponse: return "Anisette server returned data UrukStore couldn't parse."
        }
    }
}

/// Apple's private Developer Services API rejects any client that can't
/// prove it's a real Apple device — "anisette" data is that proof (a
/// machine ID + one-time password + device identity bundle). Generating it
/// from scratch requires code Apple hasn't published, so — same as
/// AltStore/SideStore — UrukStore fetches it from a small external server
/// instead of computing it on-device.
///
/// Any server implementing the common anisette JSON response (the format
/// used by Dadoum's anisette-v3-server and compatible forks) works here.
/// Run your own (https://github.com/Dadoum/anisette-v3-server) or point at
/// a public one from https://servers.sidestore.io.
struct AnisetteClient {
    var serverURL: URL

    func fetch() async throws -> ALTAnisetteData {
        var request = URLRequest(url: serverURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AnisetteError.unreachable
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let anisette = ALTAnisetteData(json: json) else {
            throw AnisetteError.invalidResponse
        }

        return anisette
    }
}

import Foundation
import AltSign

enum AnisetteError: Error, LocalizedError {
    case unreachable
    case invalidResponse
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .unreachable: return "Could not reach the anisette server."
        case .invalidResponse: return "Anisette server returned data UrukStore couldn't parse."
        case .missingField(let field): return "Anisette server response was missing '\(field)'."
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
/// Servers like https://ani.sidestore.io respond to a plain `GET /` with
/// Apple's own header-style JSON keys (X-Apple-I-MD, X-Apple-I-MD-M, etc.
/// — literally what would go in the HTTP headers Apple expects), which is
/// a different shape from AltSign's own `ALTAnisetteData` JSON format. This
/// client fetches the server's format and maps it field-by-field onto
/// `ALTAnisetteData`'s real initializer instead of assuming the shapes match.
///
/// Run your own (https://github.com/Dadoum/anisette-v3-server) or point at
/// a public one from https://github.com/SideStore/anisette-servers — use
/// one specific server's `address` from that list (e.g. https://ani.sidestore.io),
/// not the servers.json list URL itself.
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

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw AnisetteError.invalidResponse
        }

        func field(_ key: String) throws -> String {
            guard let value = json[key] else { throw AnisetteError.missingField(key) }
            return value
        }

        let oneTimePassword = try field("X-Apple-I-MD")
        let machineID = try field("X-Apple-I-MD-M")
        let localUserID = try field("X-Apple-I-MD-LU")
        let routingInfoString = try field("X-Apple-I-MD-RINFO")
        let deviceSerialNumber = try field("X-Apple-I-SRL-NO")
        let deviceUniqueIdentifier = try field("X-Mme-Device-Id")
        let deviceDescription = json["X-MMe-Client-Info"] ?? "<UrukStore>"
        let timeZoneAbbreviation = try field("X-Apple-I-TimeZone")
        let localeIdentifier = try field("X-Apple-Locale")
        let clientTime = try field("X-Apple-I-Client-Time")

        guard let routingInfo = UInt64(routingInfoString) else {
            throw AnisetteError.invalidResponse
        }

        let isoFormatter = ISO8601DateFormatter()
        let date = isoFormatter.date(from: clientTime) ?? Date()

        let locale = Locale(identifier: localeIdentifier)
        let timeZone = TimeZone(abbreviation: timeZoneAbbreviation) ?? TimeZone.current

        return ALTAnisetteData(
            machineID: machineID,
            oneTimePassword: oneTimePassword,
            localUserID: localUserID,
            routingInfo: routingInfo,
            deviceUniqueIdentifier: deviceUniqueIdentifier,
            deviceSerialNumber: deviceSerialNumber,
            deviceDescription: deviceDescription,
            date: date,
            locale: locale,
            timeZone: timeZone
        )
    }
}

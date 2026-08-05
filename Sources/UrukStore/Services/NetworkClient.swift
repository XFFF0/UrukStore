import Foundation

enum NetworkError: Error, LocalizedError {
    case badStatus(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return "Server returned status \(code)"
        case .decoding(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

/// Thin async/await wrapper around URLSession used for fetching source
/// (repo) JSON feeds and, later, talking to the signing broker.
struct NetworkClient {
    static let shared = NetworkClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchJSON<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NetworkError.badStatus(http.statusCode)
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decoding(error)
        }
    }
}

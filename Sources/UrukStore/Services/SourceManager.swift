import Foundation

@MainActor
final class SourceManager: ObservableObject {
    @Published private(set) var sources: [Source] = []
    @Published private(set) var isRefreshing = false
    @Published var lastError: String?

    private let defaultsKey = "urukstore.source.urls"
    private let defaults = UserDefaults.standard

    /// A couple of well-known community repos are pre-added so the store
    /// isn't empty on first launch. Users can add/remove any source URL.
    private let bootstrapSourceURLs: [URL] = [
        URL(string: "https://apps.altstore.io")!
    ]

    init() {
        Task { await refreshAll() }
    }

    var sourceURLs: [URL] {
        guard let saved = defaults.stringArray(forKey: defaultsKey) else {
            return bootstrapSourceURLs
        }
        return saved.compactMap(URL.init(string:))
    }

    func addSource(url: URL) async {
        var urls = sourceURLs
        guard !urls.contains(url) else { return }
        urls.append(url)
        defaults.set(urls.map(\.absoluteString), forKey: defaultsKey)
        await refreshAll()
    }

    func removeSource(url: URL) {
        let urls = sourceURLs.filter { $0 != url }
        defaults.set(urls.map(\.absoluteString), forKey: defaultsKey)
        sources.removeAll { $0.identifier == url.absoluteString }
    }

    func refreshAll() async {
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        var fetched: [Source] = []
        for url in sourceURLs {
            do {
                let source = try await NetworkClient.shared.fetchJSON(Source.self, from: url)
                fetched.append(source)
            } catch {
                // Keep going even if one source fails; surface the last error.
                lastError = "\(url.host ?? url.absoluteString): \(error.localizedDescription)"
            }
        }
        sources = fetched
    }

    var allApps: [(source: Source, app: StoreApp)] {
        sources.flatMap { source in source.apps.map { (source, $0) } }
    }
}

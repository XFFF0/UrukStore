import SwiftUI

struct SourcesView: View {
    @EnvironmentObject private var sourceManager: SourceManager
    @State private var newSourceURLString = ""
    @State private var showingAddError = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("https://example.com/repo.json", text: $newSourceURLString)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                        Button("Add", action: addSource)
                            .disabled(newSourceURLString.isEmpty)
                    }
                }

                Section("Added Sources") {
                    ForEach(sourceManager.sourceURLs, id: \.self) { url in
                        VStack(alignment: .leading) {
                            Text(sourceManager.sources.first(where: { $0.identifier == url.absoluteString })?.name ?? url.host ?? url.absoluteString)
                                .font(.headline)
                            Text(url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteSources)
                }
            }
            .navigationTitle("Sources")
            .refreshable { await sourceManager.refreshAll() }
        }
    }

    private func addSource() {
        guard let url = URL(string: newSourceURLString) else {
            showingAddError = true
            return
        }
        Task {
            await sourceManager.addSource(url: url)
            newSourceURLString = ""
        }
    }

    private func deleteSources(at offsets: IndexSet) {
        let urls = sourceManager.sourceURLs
        for index in offsets {
            sourceManager.removeSource(url: urls[index])
        }
    }
}

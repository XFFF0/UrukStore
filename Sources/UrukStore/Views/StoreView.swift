import SwiftUI

struct StoreView: View {
    @EnvironmentObject private var sourceManager: SourceManager

    var body: some View {
        NavigationStack {
            List {
                if let error = sourceManager.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }

                ForEach(sourceManager.sources) { source in
                    Section(source.name) {
                        ForEach(source.apps) { app in
                            NavigationLink(value: app) {
                                AppRow(app: app)
                            }
                        }
                    }
                }
            }
            .navigationTitle("UrukStore")
            .navigationDestination(for: StoreApp.self) { app in
                if let source = sourceManager.sources.first(where: { $0.apps.contains(app) }) {
                    AppDetailView(app: app, source: source)
                }
            }
            .refreshable { await sourceManager.refreshAll() }
            .overlay {
                if sourceManager.sources.isEmpty && !sourceManager.isRefreshing {
                    ContentUnavailableView(
                        "No Sources Added",
                        systemImage: "tray",
                        description: Text("Add a repo from the Sources tab to see apps here.")
                    )
                }
            }
        }
    }
}

private struct AppRow: View {
    let app: StoreApp

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: app.iconURL) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 12).fill(.quaternary)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.headline)
                if let subtitle = app.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let version = app.latestVersion?.version {
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

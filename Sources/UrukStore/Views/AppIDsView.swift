import SwiftUI
import AltSign

struct AppIDsView: View {
    @EnvironmentObject private var installManager: InstallManager

    @State private var appIDs: [ALTAppID] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var revokingIdentifiers: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    ForEach(appIDs, id: \.identifier) { appID in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(appID.name).font(.headline)
                                Text(appID.bundleIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if revokingIdentifiers.contains(appID.identifier) {
                                ProgressView()
                            } else {
                                Button(role: .destructive) {
                                    revoke(appID)
                                } label: {
                                    Text("Revoke")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                } footer: {
                    Text("Free Apple ID accounts can only register 10 new App IDs per week, shared across every tool signing with this account. Revoke ones you no longer need to free up room.")
                }
            }
            .navigationTitle("App IDs (\(appIDs.count))")
            .refreshable { await load() }
            .task { await load() }
            .overlay {
                if isLoading && appIDs.isEmpty {
                    ProgressView()
                } else if appIDs.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No App IDs",
                        systemImage: "app.badge",
                        description: Text("App IDs you register while signing will show up here.")
                    )
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            appIDs = try await installManager.fetchAppIDs()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func revoke(_ appID: ALTAppID) {
        revokingIdentifiers.insert(appID.identifier)
        Task {
            do {
                try await installManager.revokeAppID(appID)
                appIDs.removeAll { $0.identifier == appID.identifier }
            } catch {
                errorMessage = error.localizedDescription
            }
            revokingIdentifiers.remove(appID.identifier)
        }
    }
}

import SwiftUI

struct AppDetailView: View {
    let app: StoreApp
    let source: Source

    @EnvironmentObject private var installManager: InstallManager
    @State private var installState: InstallState = .idle
    @State private var errorMessage: String?

    enum InstallState {
        case idle, installing, failed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    AsyncImage(url: app.iconURL) { $0.resizable() } placeholder: {
                        RoundedRectangle(cornerRadius: 18).fill(.quaternary)
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.title2.bold())
                        if let developer = app.developerName {
                            Text(developer).foregroundStyle(.secondary)
                        }
                        Text("from \(source.name)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Button(action: install) {
                    if installState == .installing {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Install").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(installState == .installing)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Divider()

                Text("About")
                    .font(.headline)
                Text(app.localizedDescription)
                    .font(.body)
            }
            .padding()
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func install() {
        installState = .installing
        errorMessage = nil
        Task {
            do {
                try await installManager.install(app, from: source)
                installState = .idle
            } catch {
                installState = .failed
                errorMessage = error.localizedDescription
            }
        }
    }
}

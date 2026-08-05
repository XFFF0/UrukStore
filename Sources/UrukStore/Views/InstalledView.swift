import SwiftUI

struct InstalledView: View {
    @EnvironmentObject private var installManager: InstallManager

    var body: some View {
        NavigationStack {
            List(installManager.installedApps) { app in
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).font(.headline)
                    HStack {
                        Text("v\(app.version)")
                        if let days = installManager.daysUntilExpiration(for: app) {
                            Spacer()
                            Text(days <= 1 ? "Expires today" : "Expires in \(days)d")
                                .foregroundStyle(days <= 1 ? .red : .secondary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Installed")
            .overlay {
                if installManager.installedApps.isEmpty {
                    ContentUnavailableView(
                        "No Apps Installed",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text("Apps you install from the Store will show up here.")
                    )
                }
            }
        }
    }
}

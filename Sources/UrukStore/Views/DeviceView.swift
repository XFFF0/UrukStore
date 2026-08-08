import SwiftUI
import UniformTypeIdentifiers

struct DeviceView: View {
    @StateObject private var connection = DeviceConnection.shared

    @State private var isPickingFile = false
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Pairing File") {
                    if connection.hasPairingFile {
                        Label("Pairing file imported", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("No pairing file yet", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }

                    Button("Import Pairing File") {
                        isPickingFile = true
                    }
                } footer: {
                    Text("A .mobiledevicepairing file trusts UrukStore to install apps directly, the same way SideStore does. Get docs.sidestore.io/docs/advanced/pairing-file if you don't have one.")
                }

                Section("Local VPN Tunnel") {
                    Text("UrukStore expects a local VPN tunnel app (e.g. StosVPN) to be installed and running on this device — it's what makes the connection to the device possible without a cable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Connection") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(connection.isStarted ? "Connected" : "Not connected")
                            .foregroundStyle(connection.isStarted ? .green : .secondary)
                    }
                    if let udid = connection.udid {
                        HStack {
                            Text("Device UDID")
                            Spacer()
                            Text(udid).font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    Button(action: connect) {
                        if isConnecting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Connect").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConnecting || !connection.hasPairingFile)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Device")
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.data, .xml, .plainText]) { result in
                if case .success(let url) = result {
                    do {
                        try connection.importPairingFile(from: url)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil
        Task {
            do {
                try await connection.start()
            } catch {
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
}

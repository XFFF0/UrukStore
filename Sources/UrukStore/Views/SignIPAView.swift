import SwiftUI
import UniformTypeIdentifiers

private let ipaContentType = UTType(filenameExtension: "ipa") ?? .data

struct SignIPAView: View {
    @EnvironmentObject private var installManager: InstallManager

    @State private var isPickingFile = false
    @State private var isSigning = false
    @State private var errorMessage: String?
    @State private var signedFileURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if installManager.signingIdentity == nil {
                    ContentUnavailableView(
                        "Sign In First",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Go to the Account tab and sign in with your Apple ID before signing an IPA.")
                    )
                } else if let signedFileURL {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("Signed successfully")
                            .font(.headline)
                        Text(signedFileURL.lastPathComponent)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        ShareLink(item: signedFileURL) {
                            Label("Share / Save Signed IPA", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Sign Another") {
                            self.signedFileURL = nil
                        }
                    }
                    .padding()
                } else {
                    ContentUnavailableView(
                        "No IPA Selected",
                        systemImage: "doc.badge.plus",
                        description: Text("Pick an unsigned .ipa from Files — from your own CI builds or anywhere else — and UrukStore will sign it with your Apple ID.")
                    )

                    Button(action: { isPickingFile = true }) {
                        if isSigning {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Label("Choose IPA File", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSigning)
                    .padding(.horizontal)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                }
            }
            .navigationTitle("Sign IPA")
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [ipaContentType]) { result in
                switch result {
                case .success(let url):
                    sign(fileAt: url)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func sign(fileAt url: URL) {
        isSigning = true
        errorMessage = nil

        Task {
            do {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

                let signed = try await installManager.signLocalIPA(at: url)
                signedFileURL = signed
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigning = false
        }
    }
}

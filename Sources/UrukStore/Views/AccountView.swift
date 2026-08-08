import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var installManager: InstallManager

    @State private var appleID = ""
    @State private var password = ""
    @State private var anisetteServerURLString = "https://ani.sidestore.io"
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    @State private var isAwaitingTwoFactorCode = false
    @State private var twoFactorCode = ""
    @State private var twoFactorContinuation: CheckedContinuation<String?, Never>?

    var body: some View {
        NavigationStack {
            Form {
                if installManager.isRestoringSession {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Restoring session…")
                        }
                    }
                } else if let identity = installManager.signingIdentity {
                    Section("Signed In") {
                        Text(identity.account.appleID)
                        Text("Team: \(identity.team.name)")
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        Button("Sign Out", role: .destructive) {
                            installManager.signOut()
                        }
                    } footer: {
                        Text("You'll stay signed in next time you open UrukStore.")
                    }
                } else {
                    Section("Apple ID") {
                        TextField("Apple ID", text: $appleID)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                    }

                    Section {
                        TextField("Anisette server URL", text: $anisetteServerURLString)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("Needed to talk to Apple's Developer Services API. Use one specific server's address (e.g. the default), not a servers.json list URL. Self-host your own: github.com/Dadoum/anisette-v3-server.")
                    }

                    Section {
                        Button(action: signIn) {
                            if isSigningIn {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("Sign In").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSigningIn || appleID.isEmpty || password.isEmpty)
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Account")
            .alert("Two-Factor Code", isPresented: $isAwaitingTwoFactorCode) {
                TextField("Code", text: $twoFactorCode)
                    .keyboardType(.numberPad)
                Button("Submit") {
                    twoFactorContinuation?.resume(returning: twoFactorCode)
                    twoFactorContinuation = nil
                    twoFactorCode = ""
                }
                Button("Cancel", role: .cancel) {
                    twoFactorContinuation?.resume(returning: nil)
                    twoFactorContinuation = nil
                }
            } message: {
                Text("Enter the code sent to your trusted device or phone number.")
            }
        }
    }

    private func signIn() {
        guard let anisetteURL = URL(string: anisetteServerURLString) else {
            errorMessage = "Invalid anisette server URL."
            return
        }

        isSigningIn = true
        errorMessage = nil

        Task {
            do {
                try await installManager.signIn(
                    appleID: appleID,
                    password: password,
                    anisetteServerURL: anisetteURL,
                    twoFactorCodeProvider: {
                        await withCheckedContinuation { continuation in
                            self.twoFactorContinuation = continuation
                            self.isAwaitingTwoFactorCode = true
                        }
                    }
                )
                password = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }
}

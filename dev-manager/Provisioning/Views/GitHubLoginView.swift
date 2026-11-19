import SwiftUI

struct GitHubLoginView: View {
    @ObservedObject var model: ProvisioningModel
    @FocusState private var hostFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign in to GitHub CLI").font(.title2.weight(.semibold))
            switch model.loginState {
            case let .entry(error):
                Text("Choose a GitHub host. Continuing allows GitHub CLI to save credentials and prefer HTTPS for this host. Keychain is preferred, but the CLI may fall back to plaintext storage. GitHub CLI tries to copy the device code, and the app opens the browser when ready.")
                TextField("Hostname", text: $model.loginHostInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($hostFocused)
                    .onSubmit { model.continueLogin() }
                if error { Text("Enter a valid hostname or HTTPS root URL without credentials, a port, query, or fragment.").foregroundStyle(.red) }
                HStack {
                    Spacer()
                    Button("Cancel") { model.dismissLogin() }.keyboardShortcut(.cancelAction)
                    Button("Continue") { model.continueLogin() }.keyboardShortcut(.defaultAction)
                }
            case .preflight:
                ProgressView("Checking existing credentials for \(model.selectedAuthHost)…")
                cancelButton
            case let .waiting(code, url):
                Text("Complete sign-in for \(model.selectedAuthHost) in your browser.")
                if let code {
                    Text(code).font(.title.monospaced()).textSelection(.enabled)
                    Button("Copy code") { model.copyLoginDeviceCode() }
                    Text("GitHub CLI tries to copy this code automatically. Use Copy code if needed.").font(.caption)
                } else { ProgressView("Waiting for device code…") }
                if url != nil { Button("Open browser") { model.openLoginBrowser() } }
                cancelButton
            case .verifying:
                ProgressView("Verifying credentials for \(model.selectedAuthHost)…")
                cancelButton
            case let .blocked(message), let .error(message):
                Text(message)
                HStack {
                    Button("Choose another host") { model.chooseLoginHost() }
                    Button("Retry") { model.continueLogin() }
                    Spacer()
                    Button("Close") { model.dismissLogin() }.keyboardShortcut(.cancelAction)
                }
            case let .success(login, cancelled, plaintext):
                Text(cancelled ? "Sign-in was cancelled, but credentials for \(login) on \(model.selectedAuthHost) were saved and verified." : "Signed in as \(login) on \(model.selectedAuthHost).")
                if plaintext { Text("GitHub CLI reported plaintext credential storage for this host.").foregroundStyle(.orange) }
                HStack { Spacer(); Button("Done") { model.dismissLogin() }.keyboardShortcut(.defaultAction) }
            case .cancelling:
                ProgressView("Cancelling…")
                cancelButton
            case .cancelled:
                Text("Sign-in was cancelled; no authenticated account was confirmed.")
                Button("Close") { model.dismissLogin() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { hostFocused = true }
        .onExitCommand { model.dismissLogin() }
    }

    private var cancelButton: some View {
        HStack { Spacer(); Button("Cancel") { model.dismissLogin() }.keyboardShortcut(.cancelAction) }
    }
}

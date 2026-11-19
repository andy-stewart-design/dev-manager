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
                Text("Paste this code in your browser to finish signing in to \(model.selectedAuthHost).")
                if let code {
                    HStack {
                        Text(code).font(.title.monospaced()).textSelection(.enabled)
                        Spacer()
                        Button("Copy code") { model.copyLoginDeviceCode() }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                } else { ProgressView("Waiting for device code…") }
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.loginCodeCopied ? "Code copied to clipboard. Waiting for sign-in…" : "Waiting for sign-in…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    Button("Cancel") { model.dismissLogin() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Open browser") { model.openLoginBrowser() }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .keyboardShortcut(.defaultAction)
                        .disabled(url == nil)
                }
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

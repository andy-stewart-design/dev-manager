# Dev Manager

Dev Manager is a native SwiftUI macOS app for running local web projects without leaving one workspace. Add a project folder, choose its command (typically `pnpm dev`), and use Start/Stop to manage the actual process and its children. Live output is bounded for a useful log view. When a server starts, Dev Manager discovers its actual localhost URL and can open it in the browser.

The settings gear exposes project metadata, the command, and entry removal (removal does not delete anything from disk). Normal Quit stops managed processes with best-effort cleanup and attempts recovery on the next launch. Closing the window is not the same as quitting: processes remain running. Only one app instance should be used at a time.

## Requirements

- macOS 15 or later
- Apple Silicon and a logged-in administrator for optional machine-changing setup
- Node.js and the appropriate package manager available through an existing installation or Setup
- Each project’s dependencies installed separately
- A project command that can run through a zsh login/interactive environment

The optional Setup surface checks supported local Apple developer tools, Homebrew, fnm, Node, and pnpm. It can hand off Apple Command Line Tools to Apple’s graphical installer and Homebrew.pkg to macOS Installer; Dev Manager does not collect passwords or perform those privileged GUI steps itself. It can optionally add or restore its marked fnm block in `~/.zshrc`, with explicit consent; it never edits `~/.zprofile`.

Setup accepts stable Node 22/24/26 and pnpm 10/11/12 after checking that they run together; exact patch versions are not required. Existing usable versions are reused without automatic upgrades. fnm is optional when a supported unmanaged Node/pnpm pair is already available, and is used for app-managed Node installation when needed.

Dev Manager does not install project dependencies. Current arbitrary project commands remain shell-based and require their own dependencies and compatible tool versions; the app does not yet choose commands or versions from repository metadata and does not provide a runner fallback.

Dev Manager is not a full interactive PTY terminal.

## Build from source

1. Open `dev-manager.xcodeproj` in Xcode. The project was created with Xcode 27.2, so use a current Xcode.
2. Select the `dev-manager` app scheme and run or build the app. The app target and scheme are both `dev-manager`; the product is **Dev Manager**.

The current project metadata is version `0.1.0`, build `1`, with a macOS 15.0 deployment target.

## Distribution

1. In the app target’s **General** settings, set numeric **Version** and **Build** values (for example, `0.1.0` and `1`). Keep the minimum macOS version at 15 and confirm the **AppIcon** asset is selected. Do not put an alpha suffix in Apple’s numeric version; use it only in the ZIP filename.
2. In **Signing & Capabilities**, choose the paid Apple Developer Program team and a valid **Developer ID Application** certificate with its matching private key available. Keep **Hardened Runtime** on and **App Sandbox** off.
3. Edit the app scheme and set **Archive** to **Release**. Choose **Product > Archive**. In Organizer, choose **Distribute App**, then **Direct Distribution** (or **Custom Developer ID** if that is the available UI). Select the paid team and **Developer ID Application** signing—not Development or App Store—then sign, notarize, wait for acceptance, and export the notarized app.
4. Quit Xcode’s running copy normally before opening the exported app from Finder. Do a quick Finder check of Start, log output, Open, Stop, and Quit; this is not a full test suite.
5. In Finder, compress the exported `Dev Manager.app` and rename the ZIP, for example, `DevManager-0.1.0-alpha.1.zip`. Share the ZIP, not the `.xcarchive` or a Debug build; keep the archive for debugging. For the next alpha, increment the numeric Build value and the filename.

Do not commit private keys, `.p12` files, credentials, or build artifacts.

## Known limitations

- The initial baseline covers Vite, Next, and Astro HTTP projects, including delayed startup wrappers; multi-site projects, silent-server fallback, and HTTPS verification remain deferred.

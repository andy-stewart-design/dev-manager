import AppKit

final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    weak var runner: ProjectRunner?
    private var terminationRequested = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationRequested else { return .terminateLater }
        guard let runner else { return .terminateNow }
        guard runner.beginTermination() else { return .terminateLater }
        terminationRequested = true

        // The runner's main-actor portion only coordinates. Each blocking process-group
        // operation is explicitly detached inside stopAll, so quit never blocks AppKit.
        Task { @MainActor [weak self, weak runner] in
            let succeeded = await runner?.stopAll() ?? true
            runner?.finishTermination(success: succeeded)
            self?.terminationRequested = false
            sender.reply(toApplicationShouldTerminate: succeeded)
        }
        return .terminateLater
    }
}

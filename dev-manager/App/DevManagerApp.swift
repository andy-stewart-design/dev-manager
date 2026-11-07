import SwiftUI

@main
struct dev_managerApp: App {
    @StateObject private var projectStore = ProjectStore()
    @StateObject private var projectRunner = ProjectRunner()
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var lifecycle

    var body: some Scene {
        WindowGroup {
            ContentView(store: projectStore, runner: projectRunner)
                .onAppear {
                    lifecycle.runner = projectRunner
                }
        }
    }
}

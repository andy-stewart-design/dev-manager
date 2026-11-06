import SwiftUI

@main
struct dev_managerApp: App {
    @StateObject private var projectStore = ProjectStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: projectStore)
        }
    }
}

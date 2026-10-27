import SwiftUI

@main
struct PROXYApp: App {
    init() {
        NPCComponent.registerComponent()
        NPCSystem.registerSystem()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

import SwiftUI

@main
struct PROXYApp: App {
    init() {
        NPCComponent.registerComponent()
        NPCSystem.registerSystem()
        DroneComponent.registerComponent()
        DroneSystem.registerSystem()
        TargetComponent.registerComponent()
        MissionSystem.registerSystem()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

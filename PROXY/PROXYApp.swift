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

        startDeliveryTourIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    private func startDeliveryTourIfNeeded() {
        guard CommandLine.arguments.contains("--delivery-tour") else { return }
        let gs = GameState.shared

        // Landscape Left, Toast Visible (1.2s ... 5.2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            gs.islandSideOverride = .left
            gs.hudThemePreset = .ice
            gs.prestigeLevel = 0
            gs.droneAltitudeMM = 163.0
            gs.fuel = 83.0
            gs.droneShield = 80.0
            gs.showToast(icon: "shield.slash.fill", text: "Shield at 80%", isWarning: true)
            SessionLogger.shared.log("DELIVERY_TOUR: Landscape Left (Shield at 80%)", category: "TOUR")
        }

        // Landscape Right, Bloom Theme, Toast Visible (5.5s ... 9.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
            gs.islandSideOverride = .right
            gs.hudThemePreset = .bloom
            gs.prestigeLevel = 3
            gs.droneAltitudeMM = 210.0
            gs.fuel = 75.0
            gs.droneShield = 90.0
            gs.score = 2400
            gs.showToast(icon: "checkmark.circle.fill", text: "Sector secured", isWarning: false)
            SessionLogger.shared.log("DELIVERY_TOUR: Landscape Right (Sector secured)", category: "TOUR")
        }

        // Return to normal interactive state
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            gs.islandSideOverride = .auto
            SessionLogger.shared.log("DELIVERY_TOUR: Interactive Mode", category: "TOUR")
        }
    }
}

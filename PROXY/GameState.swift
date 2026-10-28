import Foundation
import Observation
import UIKit
import AudioToolbox

/// Central observable game state for PROXY: mission progress, fuel, score, prestige and currencies.
@Observable
final class GameState {
    static let shared = GameState()

    // MARK: - Core Gameplay
    var score: Int = 0
    var fuel: Float = 100.0              // Percentage 0...100
    var maxFuel: Float = 100.0
    var isFuelEmpty: Bool { fuel <= 0 }

    // MARK: - Zoom State
    var zoomFactor: Float = 1.0          // 1.0X, 2.0X, 4.0X

    func cycleZoom() {
        if zoomFactor < 1.9 {
            zoomFactor = 2.0
        } else if zoomFactor < 3.9 {
            zoomFactor = 4.0
        } else {
            zoomFactor = 1.0
        }

        // Mechanical optical servo audio & tactile haptic tick
        AudioServicesPlaySystemSound(1104) // Camera shutter / optical click
        AudioServicesPlaySystemSound(1057) // Stepper tick / lens motor
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        if zoomFactor > 3.5 {
            radioMessage = "OPERATOR: Optical 4.0X telephoto active. Precision lock ready."
        } else if zoomFactor > 1.5 {
            radioMessage = "OPERATOR: Optical 2.0X engaged. Telemetry synced."
        } else {
            radioMessage = "OPERATOR: Wide field 1.0X restored."
        }

        SessionLogger.shared.log("OPTICAL ZOOM: switched magnification to \(zoomFactor)X", category: "OPTICS")
    }

    // MARK: - Drone Gimbal Aiming (Joystick Reticle Control)
    var reticleOffset: CGPoint = .zero
    var isGimbalAimActive: Bool = false
    var resetGimbalTrigger: Int = 0
    var showVirtualControlsOverride: Bool = false

    func resetGimbal() {
        reticleOffset = .zero
        isGimbalAimActive = false
        resetGimbalTrigger += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        radioMessage = "OPERATOR: Targeting reticle re-centered to boresight."
        SessionLogger.shared.log("GIMBAL: Re-centered targeting reticle to center boresight", category: "GIMBAL")
    }

    // MARK: - Prestige Mechanic (0...3)
    /// Level 0: Pure cartoon. Level 1: Ants / Pest Control. Level 2: Tactical wireframe. Level 3: Full thermal FLIR reality.
    var prestigeLevel: Int = 0 {
        didSet {
            updatePrestigeTheme()
        }
    }

    // MARK: - Tool Slots (0: SCAN, 1: TAG, 2: BOOST)
    enum ToolSlot: Int, CaseIterable {
        case scan = 0
        case tag = 1
        case boost = 2

        var title: String {
            switch self {
            case .scan: return "SCAN"
            case .tag: return "TAG"
            case .boost: return "BOOST"
            }
        }

        var iconName: String {
            switch self {
            case .scan: return "viewfinder"
            case .tag: return "scope"
            case .boost: return "bolt.fill"
            }
        }
    }

    var selectedToolIndex: Int = 1
    var selectedTool: ToolSlot {
        ToolSlot(rawValue: selectedToolIndex) ?? .tag
    }

    // MARK: - Visible Meta (GOLIATH reference)
    var gems: Int = 42
    var credits: Int = 1250
    var currentMissionName: String = "OPERATION CITADEL"
    var currentSector: String = "LOW"
    var targetsRemaining: Int = 3
    var targetsTotal: Int = 3

    // MARK: - Radio Mission Feed
    var radioMessage: String = "OPERATOR: Reconnaissance active. Three targets identified in sector LOW."

    var droneAltitudeMM: Float = 50.0    // Millimeters above terrain
    var droneHeadingDeg: Float = 0.0     // Compass heading degrees

    // MARK: - Reticle Targeting State
    var isTargetLocked: Bool = false
    var lockedTargetId: Int? = nil
    var lockProgress: Float = 0.0        // 0.0...1.0 hover progress
    var tagBannerTimer: Float = 0.0      // Flash celebratory banner
    var tagBannerTitle: String = "TARGET CONFIRMED"
    var tagBannerSubtitle: String = "+500 RECON POINTS"
    var strikePopupTimer: Float = 0.0
    var strikePopupText: String = "STRIKE"
    var screenFlashTimer: Float = 0.0
    var isAdvancingSector: Bool = false

    // MARK: - Drone Combat & Counter-Attack Defense
    var droneShield: Float = 100.0       // 0...100% Shield / Hull Integrity
    var hostileWarningTimer: Float = 0.0 // Flashes warning when NPCs launch counter-attack
    var droneDamageFlashTimer: Float = 0.0 // Screen glitch/acid flash when drone is hit by NPC
    var hostileWarningText: String = "THREAT // INCOMING HOSTILE FIRE"

    func damageDrone(amount: Float) {
        droneShield = max(0, droneShield - amount)
        droneDamageFlashTimer = 0.35
        hostileWarningText = "HULL IMPACT // SHIELD \(Int(droneShield))%"
        hostileWarningTimer = 1.5

        if droneShield == 0 {
            // Emergency shield recharge sequence
            radioMessage = "OPERATOR: Drone shield compromised! Initiating emergency circuit cycle."
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.droneShield = 50.0
                self?.radioMessage = "OPERATOR: Emergency shield auxiliary online [50%]."
            }
        }
    }

    // MARK: - Ammunition & Ordnance System
    var ammo: Int = 8                    // Active rounds in magazine (e.g. 8 Hellfire / Micro-Strikes)
    var maxAmmo: Int = 8                 // Full magazine capacity
    var isReloading: Bool = false
    var reloadProgress: Float = 0.0      // 0.0...1.0 during reload cycle
    var fireRecoilTimer: Float = 0.0     // Brief visual kick for reticle/HUD on discharge

    /// Attempts to discharge one round of ammunition. Returns true if round was fired.
    func fireWeapon() -> Bool {
        if isReloading {
            return false
        }
        if ammo <= 0 {
            startReload()
            return false
        }
        ammo -= 1
        fireRecoilTimer = 0.16 // 160ms recoil kick
        if ammo == 0 {
            // Auto reload when magazine empty
            startReload()
        }
        return true
    }

    /// Triggers a tactical reload cycle (e.g. 1.4 seconds)
    func startReload() {
        guard !isReloading, ammo < maxAmmo else { return }
        isReloading = true
        reloadProgress = 0.0
        radioMessage = "OPERATOR: Ordnance depleted. Auto-reloading tactical magazine."
        SessionLogger.shared.log("ORDNANCE RELOAD: reloading magazine from \(ammo)/\(maxAmmo)", category: "WEAPONS")
    }

    /// Updates weapon reload and recoil timers every frame
    func updateWeapons(dt: Float) {
        if fireRecoilTimer > 0 {
            fireRecoilTimer = max(0, fireRecoilTimer - dt)
        }
        guard isReloading else { return }
        reloadProgress += dt / 1.4 // 1.4-second reload time
        if reloadProgress >= 1.0 {
            ammo = maxAmmo
            isReloading = false
            reloadProgress = 0.0
            radioMessage = "OPERATOR: Ordnance replenished. Weapons hot [\(maxAmmo)/\(maxAmmo)]."
            SessionLogger.shared.log("ORDNANCE READY: magazine full (\(maxAmmo)/\(maxAmmo))", category: "WEAPONS")
        }
    }

    private func updatePrestigeTheme() {
        switch prestigeLevel {
        case 0:
            currentMissionName = "OPERATION CITADEL"
            radioMessage = "OPERATOR: Reconnaissance active. Three friendly targets identified in sector LOW."
        case 1:
            currentMissionName = "PEST CONTROL SWARM"
            radioMessage = "OPERATOR: Bio-hazard infestation detected. Eradicate crop pests in sector 4."
        case 2:
            currentMissionName = "SYNAPSE TACTICAL"
            radioMessage = "OPERATOR: Visual recognition neural net active. 96% hostile combatant match."
        case 3:
            currentMissionName = "SILENT DAWN (FLIR)"
            radioMessage = "OPERATOR: Strike cleared hot. Confirm bugsplat. Zero collateral."
        default:
            break
        }
    }

    func resetMission() {
        fuel = maxFuel
        droneShield = 100.0
        ammo = maxAmmo
        isReloading = false
        score = 0
        prestigeLevel = 0
        zoomFactor = 1.0
        targetsRemaining = targetsTotal
        updatePrestigeTheme()
    }

    func cycleTool(delta: Int) {
        let count = ToolSlot.allCases.count
        selectedToolIndex = (selectedToolIndex + delta + count) % count
    }
}

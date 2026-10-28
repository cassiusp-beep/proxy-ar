import Foundation
import Observation
import UIKit
import SwiftUI
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

    // MARK: - Volvo Windshield HUD Settings
    var hudThemePreset: HUDThemePreset = .ice
    var cornerRadiusSetting: CGFloat = 55.0

    enum IslandSide: String, CaseIterable {
        case auto = "Auto"
        case left = "Left"
        case right = "Right"
    }
    var islandSideOverride: IslandSide = .auto

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
            radioMessage = "Optics: 4.0X precision zoom engaged"
        } else if zoomFactor > 1.5 {
            radioMessage = "Optics: 2.0X precision grid"
        } else {
            radioMessage = "Optics: 1.0X normal view"
        }

        SessionLogger.shared.log("SYNTHETIC SENSOR ZOOM: switched magnification to \(zoomFactor)X", category: "OPTICS")
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
    var radioMessage: String = "Recon: 3 targets in the lower sector"

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

    // MARK: - Single Top-Center Toast System
    struct HUDToast: Equatable {
        let icon: String
        let text: String
        let isWarning: Bool
    }

    var activeToast: HUDToast? = nil
    private var toastDismissWorkItem: DispatchWorkItem? = nil

    /// Shows a single toast at top center under the heading scale for ~2.0s
    func showToast(icon: String, text: String, isWarning: Bool = false) {
        toastDismissWorkItem?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            activeToast = HUDToast(icon: icon, text: text, isWarning: isWarning)
        }
        let workItem = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.25)) {
                self?.activeToast = nil
            }
        }
        toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    // MARK: - Drone Combat & Counter-Attack Defense
    var droneShield: Float = 100.0       // 0...100% Shield / Hull Integrity
    var isConnectionLost: Bool = false   // True when shield hits 0% (Lost connection lockout)
    var connectionLostCountdown: Float = 0.0
    var hostileWarningTimer: Float = 0.0 // Flashes warning when NPCs launch counter-attack
    var droneDamageFlashTimer: Float = 0.0 // Brief 300ms soft edge vignette pulse
    var damageShakeOffset: CGSize = .zero
    var hostileWarningText: String = "Threat: incoming hostile fire"

    func damageDrone(amount: Float) {
        guard !isConnectionLost else { return }
        droneShield = max(0, droneShield - amount)
        droneDamageFlashTimer = 0.30 // 300ms soft vignette pulse
        hostileWarningText = "Hull impact: shield \(Int(droneShield))%"
        hostileWarningTimer = 1.5
        showToast(icon: "shield.slash.fill", text: "Shield hit (\(Int(droneShield))%)", isWarning: true)

        // Light screen shake (strictly respects Reduce Motion)
        if !UIAccessibility.isReduceMotionEnabled {
            let dx = CGFloat.random(in: -3.5...3.5)
            let dy = CGFloat.random(in: -3.0...3.0)
            damageShakeOffset = CGSize(width: dx, height: dy)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.damageShakeOffset = CGSize(width: -dx * 0.4, height: -dy * 0.4)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                self?.damageShakeOffset = .zero
            }
        } else {
            damageShakeOffset = .zero
        }

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if droneShield <= 0 {
            droneShield = 0
            isConnectionLost = true
            connectionLostCountdown = 3.8
            radioMessage = "Operator: Hull breach, connection lost"
            AudioServicesPlaySystemSound(1053)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            SnapshotStore.shared.captureAction(tag: "connection_lost")
            SessionLogger.shared.log("CRITICAL: Drone shield depleted to 0% — LOST CONNECTION", category: "COMBAT")
            showToast(icon: "exclamationmark.triangle.fill", text: "Connection lost", isWarning: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) { [weak self] in
                guard let self else { return }
                self.droneShield = 50.0
                self.isConnectionLost = false
                self.connectionLostCountdown = 0.0
                self.radioMessage = "Operator: Uplink re-established. Auxiliary power online."
                AudioServicesPlaySystemSound(1025)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.showToast(icon: "checkmark.circle.fill", text: "Auxiliary power restored [50%]", isWarning: false)
                SessionLogger.shared.log("RECOVERY: Drone connection re-established, shield at 50%", category: "COMBAT")
            }
        } else {
            showToast(icon: "shield.slash.fill", text: "Shield at \(Int(droneShield))%", isWarning: true)
        }
    }

    // MARK: - 360° Tactical Radar Sensing
    struct RadarThreat: Identifiable {
        let id: UUID
        let azimuthRad: Float      // Relative angle: 0 = boresight, +pi/2 = right, -pi/2 = left, pi = behind
        let distanceNorm: Float    // 0.0...1.0 mapped to radar outer perimeter (0.40m range)
        let isProjectile: Bool     // True for incoming attacks (SAMs, tracers, bio-acid, corks)
        let isTagged: Bool         // For ground NPCs: true if neutralized
        let isNearestThreat: Bool  // True for the highest priority incoming projectile
    }

    var radarThreats: [RadarThreat] = []
    var activeThreatCount: Int { radarThreats.filter { $0.isProjectile }.count }
    var hasIncomingHostile: Bool { activeThreatCount > 0 }

    // MARK: - Tactical Evasive Countermeasure BOOST
    var boostActiveTimer: Float = 0.0          // Countdown for active thruster surge (1.4s)
    var isBoostActive: Bool { boostActiveTimer > 0 }
    var boostDeflectionTimer: Float = 0.0      // Flash banner countdown on successful deflection
    var boostDeflectionText: String = ""
    var boostDeflectedCount: Int = 0

    /// Engages tactical thruster surge: burns 15% fuel to engage kinetic shield & deflect incoming projectiles
    @discardableResult
    func triggerBoost() -> Bool {
        guard !isConnectionLost else {
            SessionLogger.shared.log("TACTICAL BOOST REJECTED: Drone connection offline", category: "COUNTERMEASURE")
            return false
        }
        guard fuel >= 10.0 else {
            radioMessage = "OPERATOR: ⚠ INSUFFICIENT FUEL FOR EVASIVE BOOST [\(Int(fuel))%] ⚠"
            AudioServicesPlaySystemSound(1053) // Low fuel warning buzz
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            SessionLogger.shared.log("TACTICAL BOOST REJECTED: Insufficient fuel (\(Int(fuel))%)", category: "COUNTERMEASURE")
            return false
        }

        // Consume 15% fuel
        fuel = max(0, fuel - 15.0)
        boostActiveTimer = 1.4

        // Sound & Haptic FX
        AudioServicesPlaySystemSound(1026) // Heavy thruster ignition / sonic blast
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        radioMessage = "Operator: Tactical boost engaged, kinetic shield online"
        showToast(icon: "bolt.fill", text: "Tactical boost engaged", isWarning: false)
        SnapshotStore.shared.captureAction(tag: "boost_engage")
        SessionLogger.shared.log("TACTICAL BOOST ACTIVATED: Consumed 15% fuel (remaining: \(Int(fuel))%), 1.4s kinetic deflection shield deployed", category: "COUNTERMEASURE")
        return true
    }

    // MARK: - Ammunition & Ordnance System
    var ammo: Int = 8                    // Active rounds in magazine (e.g. 8 Hellfire / Micro-Strikes)
    var maxAmmo: Int = 8                 // Full magazine capacity
    var isReloading: Bool = false
    var reloadProgress: Float = 0.0      // 0.0...1.0 during reload cycle
    var fireRecoilTimer: Float = 0.0     // Brief visual kick for reticle/HUD on discharge

    /// Attempts to discharge one round of ammunition. Returns true if round was fired.
    func fireWeapon() -> Bool {
        if isConnectionLost || isReloading {
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
            radioMessage = "CITADEL RECON // 3 TARGETS IN SECTOR LOW"
        case 1:
            currentMissionName = "PEST CONTROL SWARM"
            radioMessage = "BIO-SWARM // PURGE PESTS IN SECTOR 4"
        case 2:
            currentMissionName = "SYNAPSE TACTICAL"
            radioMessage = "SYNAPSE NET // 96% HOSTILE MATCH"
        case 3:
            currentMissionName = "SILENT DAWN (FLIR)"
            radioMessage = "SILENT DAWN FLIR // STRIKE CLEARED HOT"
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
        boostActiveTimer = 0
        boostDeflectionTimer = 0
        radarThreats.removeAll()
        updatePrestigeTheme()
    }

    func cycleTool(delta: Int) {
        let count = ToolSlot.allCases.count
        selectedToolIndex = (selectedToolIndex + delta + count) % count
    }
}

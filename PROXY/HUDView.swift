import SwiftUI
import UIKit
import AudioToolbox

/// Landscape military-grade drone HUD inspired by GOLIATH, styled with sleek Mil-Tech & Smoked Glass aesthetics.
struct HUDView: View {
    @Bindable var gameState = GameState.shared
    @Bindable var settings: PlacementSettings

    @State private var radioCharCount: Int = 0
    @State private var radioTimer: Timer? = nil

    private var isThermal: Bool {
        gameState.prestigeLevel >= 2
    }

    // Adaptive theme colors: Sleek Mil-Tech Cyan & Amber in normal view, Tactical Monochrome in Prestige thermal
    private var primaryColor: Color {
        isThermal ? Color(red: 0.20, green: 0.95, blue: 0.40) : Color(red: 0.18, green: 0.78, blue: 0.96) // Tactical Phosphor vs Sleek Stealth Cyan
    }
    private var accentColor: Color {
        isThermal ? Color.white : Color(red: 1.00, green: 0.32, blue: 0.20) // Thermal White vs High-Threat Amber/Crimson
    }
    private var warningColor: Color {
        isThermal ? Color(red: 1.0, green: 0.82, blue: 0.20) : Color(red: 1.00, green: 0.76, blue: 0.15) // Amber
    }

    var body: some View {
        ZStack {
            // 1. Military Drone Flight Boundary Bezel (Contoured to iPhone display curvature with compass & coordinates)
            CurvedScreenBezelView(
                color: primaryColor,
                isFlashing: gameState.screenFlashTimer > 0,
                flashColor: accentColor,
                heading: gameState.droneHeadingDeg
            )
            .ignoresSafeArea()

            // 1b. Artificial Synthetic Sensor Crop Surveillance Framing
            if gameState.zoomFactor > 1.05 {
                syntheticSensorCropOverlay
                    .transition(.opacity)
            }

            // 2. Razor-Sharp Mil-Tech Drone Reticle with Ammunition Indicator
            CenterReticleView(
                isLocked: gameState.isTargetLocked,
                progress: gameState.lockProgress,
                color: gameState.isTargetLocked ? accentColor : primaryColor,
                prestige: gameState.prestigeLevel,
                strikeText: gameState.strikePopupText,
                isStriking: gameState.strikePopupTimer > 0,
                strikeColor: accentColor,
                altitudeMM: gameState.droneAltitudeMM,
                ammo: gameState.ammo,
                maxAmmo: gameState.maxAmmo,
                isReloading: gameState.isReloading,
                reloadProgress: gameState.reloadProgress,
                recoilKick: gameState.fireRecoilTimer > 0,
                zoomFactor: gameState.zoomFactor
            )
            .offset(x: gameState.reticleOffset.x, y: gameState.reticleOffset.y)

            // 3. Main Dual-Wing Flight Deck Canvas Layout (Wide 19.5:9 Landscape Architecture)
            GeometryReader { geo in
                let w = geo.size.width

                ZStack(alignment: .top) {
                    // 3A. Top Center Navigation & Tactical Comms Ribbon
                    VStack(spacing: 3) {
                        topCenterCompassBar
                        missionBrevityCommsPill
                    }
                    .frame(maxWidth: min(420, w * 0.52))
                    .position(x: w / 2, y: 32)

                    // 3B. Left Flight-Deck Wing: Avionics, Altitude Ladder, 360° Radar & Ergonomic Scan Pod
                    HStack(spacing: 0) {
                        flightAvionicsLeftWing
                            .frame(width: 158)
                            .padding(.leading, 32)
                            .padding(.vertical, 14)
                        Spacer()
                    }

                    // 3C. Right Defense-Deck Wing: Status, Optics, Defense Meters & Ergonomic Weapon Stations
                    HStack(spacing: 0) {
                        Spacer()
                        weaponsDefenseRightWing
                            .frame(width: 168)
                            .padding(.trailing, 32)
                            .padding(.vertical, 14)
                    }
                }
            }

            // 4. Tactical Neutralization Confirmation Toast
            if gameState.tagBannerTimer > 0 {
                VStack {
                    tagConfirmationBanner
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .padding(.top, 76)
                    Spacer()
                }
            }

            // 5. Hostile Counter-Fire Warning Banner
            if gameState.hostileWarningTimer > 0 {
                VStack {
                    hostileThreatBanner
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .padding(.top, 76)
                    Spacer()
                }
            }

            // 6. Tactical Boost Threat Deflection Toast Banner
            if gameState.boostDeflectionTimer > 0 {
                VStack {
                    boostDeflectionBanner
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .padding(.top, 76)
                    Spacer()
                }
            }

            // 7. Tactical Boost Evasive Thruster Surge Screen Overlay
            if gameState.isBoostActive {
                evasiveSurgeOverlay
                    .transition(.opacity)
            }

            // 8. Red Screen Damage Flash Vignette (Hostile Impact)
            if gameState.droneDamageFlashTimer > 0 {
                RoundedRectangle(cornerRadius: 54, style: .continuous)
                    .stroke(Color.red.opacity(Double(gameState.droneDamageFlashTimer / 0.45)), lineWidth: 16)
                    .background(Color.red.opacity(Double(gameState.droneDamageFlashTimer / 0.45) * 0.18))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // 9. Full-Screen Lost Connection / Telemetry Offline Overlay
            if gameState.isConnectionLost {
                lostConnectionOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onAppear {
            startRadioTypewriter()
            DroneAudioEngine.shared.start()
        }
        .onChange(of: gameState.radioMessage) { _, _ in
            startRadioTypewriter()
        }
    }

    // MARK: - Top Bar (Smoked Glass Mil-Tech Layout)

    // MARK: - Top Bar (Unified Single-Tier Mil-Tech Layout)

    // MARK: - 3A. Top Center Navigation & Tactical Comms Ribbon

    private var topCenterCompassBar: some View {
        let heading = Int(gameState.droneHeadingDeg) % 360
        return VStack(spacing: 2) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 6))
                .foregroundStyle(accentColor)

            HStack(spacing: 6) {
                ForEach(-3...3, id: \.self) { offset in
                    let markDeg = (heading + offset * 15 + 360) % 360
                    VStack(spacing: 1) {
                        Text(compassMarkLabel(markDeg))
                            .font(.system(size: offset == 0 ? 8 : 7, weight: offset == 0 ? .black : .semibold, design: .monospaced))
                            .foregroundStyle(offset == 0 ? .white : primaryColor.opacity(0.6))
                            .lineLimit(1)
                        Rectangle()
                            .fill(offset == 0 ? accentColor : primaryColor.opacity(0.4))
                            .frame(width: 1, height: offset == 0 ? 7 : 4)
                    }
                    .frame(width: 26)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(smokedGlassBacking(cornerRadius: 5))
        }
    }

    private func compassMarkLabel(_ deg: Int) -> String {
        switch deg {
        case 0: return "N"
        case 45: return "NE"
        case 90: return "E"
        case 135: return "SE"
        case 180: return "S"
        case 225: return "SW"
        case 270: return "W"
        case 315: return "NW"
        default: return "\(deg)°"
        }
    }

    private var missionBrevityCommsPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(primaryColor)

            Text(displayedRadioText)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(smokedGlassBacking(cornerRadius: 5))
    }

    // MARK: - 3B. Left Flight-Deck Wing (Avionics, Altimeter Ladder, Radar & Thumb Scan Pod)

    private var dynamicIslandSensorHousing: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(primaryColor)
                .frame(width: 4, height: 4)
            Text("FLIR 01")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(primaryColor)
                .lineLimit(1)
            Text("•")
                .font(.system(size: 6))
                .foregroundStyle(Color.white.opacity(0.3))
            Text("SIG -42dBm")
                .font(.system(size: 6, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            HStack(spacing: 1) {
                ForEach(0..<4, id: \.self) { _ in
                    Rectangle()
                        .fill(primaryColor)
                        .frame(width: 1.5, height: 5)
                }
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 1.5, height: 5)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(smokedGlassBacking(cornerRadius: 4))
    }

    private var flightAvionicsLeftWing: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Hardware Sensor Housing
            dynamicIslandSensorHousing

            // Altitude & Heading Telemetry
            AltHdgTelemetryBadge(
                altitudeMM: gameState.droneAltitudeMM,
                headingDeg: gameState.droneHeadingDeg,
                primaryColor: primaryColor
            )

            // Vertical Altitude Ladder Tape
            verticalAltitudeLadder

            // 360° Tactical Radar Threat Instrument
            HStack(spacing: 6) {
                tacticalRadarWidget
                VStack(alignment: .leading, spacing: 1.5) {
                    Text("360° THREAT")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundStyle(primaryColor)
                        .lineLimit(1)
                    Text(gameState.hasIncomingHostile ? "HOSTILE INBOUND" : "SECTOR CLEAR")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(gameState.hasIncomingHostile ? Color.red : Color.white.opacity(0.6))
                        .lineLimit(1)
                    Text("RNG: 25M")
                        .font(.system(size: 6, weight: .semibold, design: .monospaced))
                        .foregroundStyle(primaryColor.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .padding(4)
            .background(smokedGlassBacking(cornerRadius: 7))

            // Gimbal Slew Reset (when active)
            if gameState.isGimbalAimActive {
                Button {
                    gameState.resetGimbal()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "scope")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(accentColor)
                        Text("GIMBAL")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                        Text(GameInput.shared.isControllerConnected ? "[L3]" : "RESET")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(primaryColor)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(smokedGlassBacking(cornerRadius: 4))
                }
            }

            Spacer()

            // Ergonomic Left-Thumb Pulse Scan Pod (L2)
            ergonomicScanPod
        }
    }

    private var verticalAltitudeLadder: some View {
        let nominalAlt: Float = 190.0
        let delta = gameState.droneAltitudeMM - nominalAlt
        let vs = String(format: "%+.1f M/S", delta > 5 ? 0.2 : (delta < -5 ? -0.2 : 0.0))

        return HStack(spacing: 4) {
            VStack(spacing: 2.5) {
                ForEach([-20, -10, 0, 10, 20], id: \.self) { tick in
                    HStack(spacing: 2) {
                        Rectangle()
                            .fill(tick == 0 ? accentColor : primaryColor.opacity(0.4))
                            .frame(width: tick == 0 ? 8 : 4, height: 1)
                        if tick == 0 {
                            Text("190")
                                .font(.system(size: 6, weight: .bold, design: .monospaced))
                                .foregroundStyle(accentColor)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text("V/S TAPE")
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .foregroundStyle(primaryColor.opacity(0.7))
                    .lineLimit(1)
                Text(vs)
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .foregroundStyle(delta.magnitude < 15 ? primaryColor : warningColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(smokedGlassBacking(cornerRadius: 4))
    }

    private var ergonomicScanPod: some View {
        let isSelected = gameState.selectedTool == .scan
        return Button {
            gameState.selectedToolIndex = GameState.ToolSlot.scan.rawValue
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isSelected ? Color.black : primaryColor)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text("SCAN")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                        if GameInput.shared.isControllerConnected {
                            Text("L2")
                                .font(.system(size: 6, weight: .black, design: .monospaced))
                                .padding(.horizontal, 2.5)
                                .padding(.vertical, 0.5)
                                .background(isSelected ? Color.black : Color.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 2))
                                .foregroundStyle(isSelected ? Color.white : Color.white)
                        }
                    }
                    Text("LIDAR ECHO")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.black.opacity(0.7) : Color.white.opacity(0.5))
                }

                Spacer()

                Circle()
                    .fill(isSelected ? Color.black : primaryColor)
                    .frame(width: 4, height: 4)
            }
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.black : .white)
            .background(
                isSelected ? primaryColor : Color.white.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? primaryColor : Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: isSelected ? primaryColor.opacity(0.6) : .clear, radius: 5)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3C. Right Defense-Deck Wing (Status, Optics, Defense Meters & Weapon Stations)

    private var weaponsDefenseRightWing: some View {
        VStack(alignment: .trailing, spacing: 7) {
            // Target counter, Mode & Hero Shutter Bar
            HStack(spacing: 4) {
                HStack(spacing: 2) {
                    Text("TGT")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(primaryColor.opacity(0.8))
                    Text("\(gameState.targetsTotal - gameState.targetsRemaining)/\(gameState.targetsTotal)")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(warningColor)
                }

                Text("•")
                    .font(.system(size: 5))
                    .foregroundStyle(Color.white.opacity(0.3))

                Button {
                    let next = (gameState.prestigeLevel + 1) % 4
                    gameState.prestigeLevel = next
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: prestigeIcon(gameState.prestigeLevel))
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(primaryColor)
                        Text(prestigeBadgeTitle(gameState.prestigeLevel))
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }

                Text("•")
                    .font(.system(size: 5))
                    .foregroundStyle(Color.white.opacity(0.3))

                Button {
                    AudioServicesPlaySystemSound(1108)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    SnapshotStore.shared.captureAction(tag: "hero_manual")
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "camera.shutter.button.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(accentColor)
                        Text("HERO")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(smokedGlassBacking(cornerRadius: 5))

            // Score Badge
            HStack(spacing: 3) {
                Text("SCORE")
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                Text("\(gameState.score)")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(smokedGlassBacking(cornerRadius: 4))

            // Optics Zoom Selector
            Button {
                gameState.cycleZoom()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(primaryColor)
                    Text("OPTICS")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(primaryColor.opacity(0.85))
                    Text(String(format: "%.1fX", gameState.zoomFactor))
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                    if GameInput.shared.isControllerConnected {
                        Text("○")
                            .font(.system(size: 6, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 2)
                            .padding(.vertical, 0.5)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 2))
                    }
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(smokedGlassBacking(cornerRadius: 4))
            }

            // Defense Shield & Ordnance Multi-Segment Telemetry Pod
            VStack(alignment: .trailing, spacing: 2.5) {
                HStack(spacing: 3) {
                    Text("DEF")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(primaryColor.opacity(0.8))
                    HStack(spacing: 1) {
                        ForEach(0..<8, id: \.self) { idx in
                            let activeBlocks = Int((gameState.droneShield / 100.0) * 8.0)
                            Rectangle()
                                .fill(idx < activeBlocks ? shieldColor : Color.white.opacity(0.12))
                                .frame(width: 3.5, height: 5)
                        }
                    }
                    Text("\(Int(gameState.droneShield))%")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundStyle(shieldColor)
                }

                Button {
                    gameState.startReload()
                } label: {
                    HStack(spacing: 3) {
                        Text(gameState.isReloading ? "RELOAD" : "ORD")
                            .font(.system(size: 6, weight: .bold, design: .monospaced))
                            .foregroundStyle(warningColor)
                        Text(gameState.isReloading ? "\(Int(gameState.reloadProgress * 100))%" : "\(gameState.ammo)/\(gameState.maxAmmo)")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(gameState.ammo <= 2 ? warningColor : .white)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3.5)
            .background(smokedGlassBacking(cornerRadius: 5))

            Spacer()

            // Bottom-Right Ergonomic Weapon Pods (Boost L1 + Tag R2)
            VStack(alignment: .trailing, spacing: 5) {
                ergonomicBoostPod
                ergonomicTagPod
            }
        }
    }

    private var ergonomicTagPod: some View {
        let isSelected = gameState.selectedTool == .tag
        return Button {
            gameState.selectedToolIndex = GameState.ToolSlot.tag.rawValue
            GameInput.shared.tagTriggered = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                GameInput.shared.tagTriggered = false
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(isSelected ? Color.black : accentColor)
                    .frame(width: 5, height: 5)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text("TAG / FIRE")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                        if GameInput.shared.isControllerConnected {
                            Text("R2")
                                .font(.system(size: 6, weight: .black, design: .monospaced))
                                .padding(.horizontal, 2.5)
                                .padding(.vertical, 0.5)
                                .background(isSelected ? Color.black : Color.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 2))
                                .foregroundStyle(isSelected ? Color.white : Color.white)
                        }
                    }
                    Text(gameState.isTargetLocked ? "LOCKED" : "STRIKE")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.black.opacity(0.8) : (gameState.isTargetLocked ? accentColor : Color.white.opacity(0.6)))
                }

                Spacer()

                Text("[\(gameState.ammo)]")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.black : (gameState.ammo <= 2 ? warningColor : .white))
            }
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.black : .white)
            .background(
                isSelected ? accentColor : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? accentColor : Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: isSelected ? accentColor.opacity(0.65) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
    }

    private var ergonomicBoostPod: some View {
        let isSelected = gameState.selectedTool == .boost
        let active = gameState.isBoostActive
        return Button {
            gameState.selectedToolIndex = GameState.ToolSlot.boost.rawValue
            _ = GameState.shared.triggerBoost()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: active ? "bolt.shield.fill" : "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(active ? Color.cyan : (isSelected ? Color.black : Color.white))

                VStack(alignment: .leading, spacing: 0.5) {
                    HStack(spacing: 2.5) {
                        Text("BOOST")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                        if GameInput.shared.isControllerConnected {
                            Text("L1")
                                .font(.system(size: 5, weight: .black, design: .monospaced))
                                .padding(.horizontal, 2)
                                .padding(.vertical, 0.5)
                                .background(isSelected ? Color.black : Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 2))
                        }
                    }
                    Text(active ? "DEFLECTING" : "SURGE // -15%")
                        .font(.system(size: 5.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(active ? Color.cyan : (isSelected ? Color.black.opacity(0.7) : Color.white.opacity(0.5)))
                }

                Spacer()

                Text(active ? "ON" : "⚡")
                    .font(.system(size: 6, weight: .black, design: .monospaced))
                    .foregroundStyle(active ? Color.cyan : (isSelected ? Color.black : Color.white.opacity(0.7)))
            }
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 7)
            .padding(.vertical, 4.5)
            .foregroundStyle(isSelected ? Color.black : .white)
            .background(
                active ? Color.cyan.opacity(0.3) : (isSelected ? Color.cyan : Color.white.opacity(0.04)),
                in: RoundedRectangle(cornerRadius: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(active ? Color.cyan : (isSelected ? Color.cyan : Color.white.opacity(0.12)), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var fuelColor: Color {
        if gameState.fuel > 50 { return primaryColor }
        if gameState.fuel > 20 { return warningColor }
        return Color.red
    }

    private var shieldColor: Color {
        if gameState.droneShield > 60 { return primaryColor }
        if gameState.droneShield > 30 { return warningColor }
        return Color.red
    }

    private func headingWithCardinal(_ deg: Float) -> String {
        let normalized = Int(deg) % 360
        let cardinals = ["N", "NE", "E", "SE", "S", "SW", "W", "NW", "N"]
        let index = Int((Double(normalized) + 22.5) / 45.0)
        let cardinal = cardinals[index % 8]
        return String(format: "%03d° %@", normalized, cardinal)
    }

    private func prestigeBadgeTitle(_ level: Int) -> String {
        switch level {
        case 0: return "ARCADE"
        case 1: return "BIO-SWARM"
        case 2: return "RECON-FLIR"
        default: return "SPEC-OPS"
        }
    }

    private func prestigeIcon(_ level: Int) -> String {
        switch level {
        case 0: return "gamecontroller.fill"
        case 1: return "ant.fill"
        case 2: return "scope"
        default: return "waveform.path.ecg"
        }
    }

    // Dynamic 360° Tactical Radar Threat Sensing Widget (Sleek 56x56 Circular Instrument)
    private var tacticalRadarWidget: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let sweepRad = (now.truncatingRemainder(dividingBy: 2.0) / 2.0) * 2.0 * .pi
            let size: CGFloat = 56
            let center = CGPoint(x: size / 2, y: size / 2)
            let radarRadius: CGFloat = 22.0

            ZStack {
                // Smoked glass circular base
                Circle()
                    .fill(Color(red: 0.04, green: 0.06, blue: 0.08).opacity(0.92))
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .stroke(
                                gameState.hasIncomingHostile
                                    ? Color.red.opacity(0.90)
                                    : (gameState.isBoostActive ? Color.cyan.opacity(0.90) : primaryColor.opacity(0.35)),
                                lineWidth: (gameState.hasIncomingHostile || gameState.isBoostActive) ? 1.5 : 0.75
                            )
                    )
                    .shadow(
                        color: gameState.hasIncomingHostile
                            ? Color.red.opacity(0.7)
                            : (gameState.isBoostActive ? Color.cyan.opacity(0.65) : .clear),
                        radius: 6
                    )

                // Concentric range circles (10M inner, 25M outer)
                Circle()
                    .stroke(primaryColor.opacity(0.18), lineWidth: 0.75)
                    .frame(width: 22, height: 22)

                Circle()
                    .stroke(
                        gameState.hasIncomingHostile
                            ? Color.red.opacity(0.30)
                            : primaryColor.opacity(0.25),
                        lineWidth: 0.75
                    )
                    .frame(width: 44, height: 44)

                // Crosshair coordinate axes
                Rectangle()
                    .fill(primaryColor.opacity(0.15))
                    .frame(width: 44, height: 0.5)

                Rectangle()
                    .fill(primaryColor.opacity(0.15))
                    .frame(width: 0.5, height: 44)

                // Rotating 360° radar sweep line
                Path { path in
                    path.move(to: center)
                    let endX = center.x + CGFloat(cos(sweepRad)) * radarRadius
                    let endY = center.y + CGFloat(sin(sweepRad)) * radarRadius
                    path.addLine(to: CGPoint(x: endX, y: endY))
                }
                .stroke(
                    gameState.hasIncomingHostile ? Color.red.opacity(0.75) : primaryColor.opacity(0.75),
                    lineWidth: 1.0
                )

                // Center drone marker (triangle pointed along boresight)
                Image(systemName: "location.north.fill")
                    .font(.system(size: 6, weight: .black))
                    .foregroundStyle(gameState.isBoostActive ? Color.cyan : primaryColor)

                // Dynamic 360° Radar Threat Blips
                ForEach(gameState.radarThreats) { threat in
                    let xOff = CGFloat(sin(threat.azimuthRad) * threat.distanceNorm) * radarRadius
                    let yOff = CGFloat(-cos(threat.azimuthRad) * threat.distanceNorm) * radarRadius

                    if threat.isProjectile {
                        // Incoming Hostile Projectile (crimson diamond)
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 5, weight: .black))
                            .rotationEffect(Angle(radians: Double(threat.azimuthRad) + .pi))
                            .foregroundStyle(Color(red: 1.0, green: 0.15, blue: 0.3))
                            .offset(x: xOff, y: yOff)
                    } else {
                        // Ground Target / NPC
                        Circle()
                            .fill(threat.isTagged ? Color.green.opacity(0.6) : Color(red: 1.0, green: 0.75, blue: 0.15))
                            .frame(width: 3.0, height: 3.0)
                            .offset(x: xOff, y: yOff)
                    }
                }

                // Range readout label
                VStack {
                    HStack {
                        Spacer()
                        if gameState.hasIncomingHostile {
                            Text("⚠ \(gameState.activeThreatCount)")
                                .font(.system(size: 6, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.red)
                        } else {
                            Text("25M")
                                .font(.system(size: 5, weight: .bold, design: .monospaced))
                                .foregroundStyle(primaryColor.opacity(0.6))
                        }
                    }
                    Spacer()
                }
                .padding(3)
                .frame(width: size, height: size)
            }
        }
        .frame(width: 56, height: 56)
    }

    // Tactical Tag/Neutralization Banner (with Sector Sterilized Climax Fanfare)
    private var tagConfirmationBanner: some View {
        let isSectorClear = gameState.tagBannerTitle.contains("STERILIZED")
        let bannerColor = isSectorClear ? Color(red: 0.20, green: 0.95, blue: 0.40) : accentColor

        return HStack(spacing: 8) {
            Image(systemName: isSectorClear ? "star.fill" : "target")
                .foregroundStyle(bannerColor)
                .font(.system(size: isSectorClear ? 16 : 14, weight: .black))

            VStack(alignment: .leading, spacing: 1) {
                Text(gameState.tagBannerTitle.uppercased())
                    .font(.system(size: isSectorClear ? 13 : 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                Text(gameState.tagBannerSubtitle.uppercased())
                    .font(.system(size: isSectorClear ? 10 : 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(bannerColor)
            }

            if isSectorClear {
                Image(systemName: "star.fill")
                    .foregroundStyle(bannerColor)
                    .font(.system(size: 16, weight: .black))
            }
        }
        .padding(.horizontal, isSectorClear ? 18 : 14)
        .padding(.vertical, isSectorClear ? 10 : 7)
        .background(smokedGlassBacking(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(bannerColor, lineWidth: isSectorClear ? 1.75 : 1.0)
        )
        .shadow(color: bannerColor.opacity(isSectorClear ? 0.75 : 0.45), radius: isSectorClear ? 16 : 8)
    }

    // Hostile Retaliation Warning Banner
    private var hostileThreatBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.red)

            Text(gameState.hostileWarningText.uppercased())
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(.white)

            Text("// EVASIVE ACTION")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.red.opacity(0.85), lineWidth: 1.5)
                )
        )
        .shadow(color: Color.red.opacity(0.65), radius: 10, x: 0, y: 0)
    }

    // Boost Deflection Confirmation Toast Banner
    private var boostDeflectionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(Color.cyan)

            Text(gameState.boostDeflectionText)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(.white)

            Text("// INTERCEPTED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.cyan)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Color(red: 0.04, green: 0.12, blue: 0.18).opacity(0.95),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.cyan, lineWidth: 1.5)
        )
        .shadow(color: Color.cyan.opacity(0.75), radius: 12)
    }

    // Boost Evasive Surge Overlay (Screen edges glow cyan with subtle vignette)
    private var evasiveSurgeOverlay: some View {
        ZStack {
            Rectangle()
                .fill(
                    RadialGradient(
                        colors: [.clear, Color.cyan.opacity(0.12)],
                        center: .center,
                        startRadius: 200,
                        endRadius: 520
                    )
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Color.cyan)

                    Text("EVASIVE COUNTERMEASURE ACTIVE [\(String(format: "%.1f", gameState.boostActiveTimer))S]")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.cyan, lineWidth: 1))
                .padding(.bottom, 64)
            }
            .allowsHitTesting(false)
        }
    }

    // Full-Screen Digital Surveillance Enlargement Overlay (Frame remains full screen)
    private var syntheticSensorCropOverlay: some View {
        GeometryReader { geo in
            ZStack {
                // 1. Full-Screen Surveillance CRT edge vignette
                RadialGradient(
                    colors: [.clear, Color.black.opacity(gameState.zoomFactor > 3.0 ? 0.38 : 0.22)],
                    center: .center,
                    startRadius: 200,
                    endRadius: 520
                )
                .ignoresSafeArea()

                // 2. Full-Screen Fine CRT Horizontal Raster Scanlines
                VStack(spacing: 6) {
                    ForEach(0..<Int(geo.size.height / 6.0), id: \.self) { _ in
                        Rectangle()
                            .fill(primaryColor.opacity(gameState.zoomFactor > 3.0 ? 0.05 : 0.03))
                            .frame(height: 1)
                    }
                }
                .ignoresSafeArea()

                // 3. Full-Screen Digital Surveillance Telemetry (Inset to match outer bezels)
                VStack {
                    HStack {
                        Text("┌ DIGITAL MAGNIFICATION: \(String(format: "%.1fX", gameState.zoomFactor)) // SENSOR MATRIX: 4096×2160")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(primaryColor)
                        Spacer()
                        Text("PIXEL BINNING: \(gameState.zoomFactor > 3.0 ? "4×4" : "2×2") // GAIN: +12dB ┐")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(primaryColor)
                    }
                    .padding(.horizontal, 56)
                    .padding(.top, 40)

                    Spacer()

                    HStack {
                        Text("└ RESOLUTION ENHANCE: ACTIVE // DIGI-FOV: \(gameState.zoomFactor > 3.0 ? "14°" : "28°")")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(primaryColor)
                        Spacer()
                        Text("PRECISION BORESIGHT: ACTIVE ┘")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(primaryColor)
                    }
                    .padding(.horizontal, 56)
                    .padding(.bottom, 40)
                }
            }
        }
        .allowsHitTesting(false)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: gameState.zoomFactor)
    }

    // Full-Screen Lost Connection / Telemetry Dropout Overlay
    private var lostConnectionOverlay: some View {
        ZStack {
            // Dark CRT glitch background with flashing crimson edge
            Color.black.opacity(0.88)
                .ignoresSafeArea()

            // Horizontal CRT static scanlines
            VStack(spacing: 4) {
                ForEach(0..<36, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.red.opacity(0.08))
                        .frame(height: 1.5)
                }
            }
            .ignoresSafeArea()

            // Outer emergency beacon stroke
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.red.opacity(0.85), lineWidth: 4)
                .padding(24)
                .ignoresSafeArea()

            // Central Telemetry Lost Alert Box
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 26, weight: .black))
                        .foregroundStyle(.red)

                    Text("LOST CONNECTION")
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                }

                Text("UAV-01 SENSOR TELEMETRY COLLAPSED // HULL INTEGRITY 0%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red)

                Text("HOSTILE COUNTER-FIRE SEVERED CARRIER SIGNAL")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))

                Divider()
                    .background(Color.red.opacity(0.5))
                    .frame(width: 300)
                    .padding(.vertical, 4)

                // Reconnection Progress Bar
                VStack(spacing: 6) {
                    HStack {
                        Text("RE-ESTABLISHING AUXILIARY LINK...")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Text("3.8s")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                    .frame(width: 270)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.15))

                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.red)
                                .frame(width: geo.size.width * 0.7)
                        }
                    }
                    .frame(width: 270, height: 6)
                }

                Text("CONTROLS LOCKED // AWAITING SYSTEM REBOOT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.yellow)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.02, blue: 0.02).opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.red, lineWidth: 2)
                    )
            )
            .shadow(color: Color.red.opacity(0.85), radius: 24, x: 0, y: 0)
        }
        .allowsHitTesting(true) // Lock out touches while connection is lost
    }

    // MARK: - Reusable Smoked Glass Backing

    private func smokedGlassBacking(cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(red: 0.04, green: 0.06, blue: 0.08).opacity(0.78))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
        }
    }

    // MARK: - Radio Typewriter

    private var displayedRadioText: String {
        let msg = gameState.radioMessage
        let count = min(radioCharCount, msg.count)
        let index = msg.index(msg.startIndex, offsetBy: count)
        return String(msg[..<index])
    }

    private func startRadioTypewriter() {
        radioCharCount = 0
        radioTimer?.invalidate()
        radioTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            if radioCharCount < gameState.radioMessage.count {
                radioCharCount += 1
            } else {
                timer.invalidate()
            }
        }
    }
}

// MARK: - Center Reticle (Mil-Tech Drone Crosshair)

struct CenterReticleView: View {
    let isLocked: Bool
    let progress: Float
    let color: Color
    let prestige: Int
    var strikeText: String = ""
    var isStriking: Bool = false
    var strikeColor: Color = .white
    var altitudeMM: Float = 0
    var ammo: Int = 8
    var maxAmmo: Int = 8
    var isReloading: Bool = false
    var reloadProgress: Float = 0.0
    var recoilKick: Bool = false
    var zoomFactor: Float = 1.0

    var body: some View {
        ZStack {
            // High-Impact Floating Combat Score Badge directly at Reticle Center
            if isStriking && !strikeText.isEmpty {
                Text(strikeText)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(strikeColor, in: RoundedRectangle(cornerRadius: 4))
                    .shadow(color: strikeColor.opacity(0.85), radius: 10, y: 2)
                    .offset(y: -46)
                    .scaleEffect(isStriking ? 1.15 : 0.8)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isStriking)
            }

            // Radial Target Lock Progress Ring
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .butt))
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.05), value: progress)
            }

            // Outer Target Acquisition Brackets [   ]
            HStack(spacing: isLocked ? 46 : 56) {
                // Left bracket
                Path { p in
                    p.move(to: CGPoint(x: 10, y: 0))
                    p.addLine(to: CGPoint(x: 0, y: 0))
                    p.addLine(to: CGPoint(x: 0, y: 28))
                    p.addLine(to: CGPoint(x: 10, y: 28))
                }
                .stroke(color, lineWidth: 1.5)
                .frame(width: 10, height: 28)

                // Right bracket
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0))
                    p.addLine(to: CGPoint(x: 10, y: 0))
                    p.addLine(to: CGPoint(x: 10, y: 28))
                    p.addLine(to: CGPoint(x: 0, y: 28))
                }
                .stroke(color, lineWidth: 1.5)
                .frame(width: 10, height: 28)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isLocked)

            // Precision Mil-Tech Central Crosshair
            crosshairGlyph

            // Lock telemetry readout (appears only when target acquired)
            if isLocked {
                Text(lockStatusText)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
                    .offset(y: 28)
            }

            // Optical Zoom Precision Sniper Reticle (Active when 2.0X or 4.0X engaged)
            if zoomFactor > 1.05 {
                // Precision mil-dot ticks at 14pt, 20pt, 26pt along crosshair axes
                ZStack {
                    ForEach([14, 20, 26], id: \.self) { d in
                        Circle()
                            .fill(color.opacity(0.85))
                            .frame(width: 1.5, height: 1.5)
                            .offset(x: CGFloat(d))
                        Circle()
                            .fill(color.opacity(0.85))
                            .frame(width: 1.5, height: 1.5)
                            .offset(x: -CGFloat(d))
                        Circle()
                            .fill(color.opacity(0.85))
                            .frame(width: 1.5, height: 1.5)
                            .offset(y: CGFloat(d))
                        Circle()
                            .fill(color.opacity(0.85))
                            .frame(width: 1.5, height: 1.5)
                            .offset(y: -CGFloat(d))
                    }
                }

                // Illuminated Magnification Badge
                HStack(spacing: 4) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 8, weight: .bold))
                    Text(zoomFactor > 3.5 ? "4.0X DIGI-ZOOM" : "2.0X SENSOR CROP")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                }
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(color.opacity(0.5), lineWidth: 0.75)
                )
                .offset(y: -30)
            }
        }
        .offset(y: recoilKick ? -6 : 0)
        .animation(.spring(response: 0.15, dampingFraction: 0.5), value: recoilKick)
        .scaleEffect(isLocked ? 1.12 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isLocked)
    }

    @ViewBuilder
    private var crosshairGlyph: some View {
        switch prestige {
        case 0:
            // Precision Tactical Crosshair with center dot
            ZStack {
                Rectangle()
                    .fill(color)
                    .frame(width: 18, height: 1)
                Rectangle()
                    .fill(color)
                    .frame(width: 1, height: 18)
                Circle()
                    .stroke(color, lineWidth: 0.75)
                    .frame(width: 8, height: 8)
            }

        case 1:
            // Bio-Pest Swarm Tactical Scanner
            ZStack {
                Circle()
                    .stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: 22, height: 22)
                Rectangle()
                    .fill(color)
                    .frame(width: 14, height: 1)
                Rectangle()
                    .fill(color)
                    .frame(width: 1, height: 14)
                Circle()
                    .fill(color)
                    .frame(width: 3, height: 3)
            }

        case 2:
            // Mil-Spec Drone Scope with Mil-Dot ticks
            ZStack {
                Circle()
                    .stroke(color, lineWidth: 1)
                    .frame(width: 28, height: 28)
                Rectangle()
                    .fill(color)
                    .frame(width: 34, height: 0.75)
                Rectangle()
                    .fill(color)
                    .frame(width: 0.75, height: 34)
            }

        default:
            // Ultra-Fine FLIR Thermal Crosshair
            ZStack {
                Rectangle()
                    .fill(color)
                    .frame(width: 40, height: 0.5)
                Rectangle()
                    .fill(color)
                    .frame(width: 0.5, height: 40)
                Circle()
                    .stroke(color.opacity(0.4), lineWidth: 0.5)
                    .frame(width: 16, height: 16)
            }
        }
    }

    private var lockStatusText: String {
        switch prestige {
        case 0: return "ACQUIRING TARGET"
        case 1: return "BIO-PEST IDENTIFIED"
        case 2: return "TARGET LOCKED // EO-IR"
        default: return "THERMAL SIGNATURE LOCK"
        }
    }
}

// MARK: - Tactical HUD Frame & Corner Brackets (Zero Slop / No Screen-Boxing)

struct CurvedScreenBezelView: View {
    let color: Color
    var isFlashing: Bool = false
    var flashColor: Color = .white
    var heading: Float = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let padH: CGFloat = 36 // Clean inset clearing Dynamic Island
            let padV: CGFloat = 16 // Clean inset clearing status & home bar
            let bracketSize: CGFloat = 16

            ZStack {
                // Screen flash on impact / neutralization (smooth radial edge flash)
                if isFlashing {
                    Rectangle()
                        .fill(
                            RadialGradient(
                                colors: [flashColor.opacity(0.35), flashColor.opacity(0.05), .clear],
                                center: .center,
                                startRadius: 100,
                                endRadius: max(w, h) * 0.6
                            )
                        )
                        .allowsHitTesting(false)
                }

                // Four open corner brackets (┌ ┐ └ ┘) framing the combat viewport
                // Top-Left ┌
                Path { p in
                    p.move(to: CGPoint(x: padH, y: padV + bracketSize))
                    p.addLine(to: CGPoint(x: padH, y: padV))
                    p.addLine(to: CGPoint(x: padH + bracketSize, y: padV))
                }
                .stroke(color.opacity(0.30), lineWidth: 1.0)

                // Top-Right ┐
                Path { p in
                    p.move(to: CGPoint(x: w - padH - bracketSize, y: padV))
                    p.addLine(to: CGPoint(x: w - padH, y: padV))
                    p.addLine(to: CGPoint(x: w - padH, y: padV + bracketSize))
                }
                .stroke(color.opacity(0.30), lineWidth: 1.0)

                // Bottom-Left └
                Path { p in
                    p.move(to: CGPoint(x: padH, y: h - padV - bracketSize))
                    p.addLine(to: CGPoint(x: padH, y: h - padV))
                    p.addLine(to: CGPoint(x: padH + bracketSize, y: h - padV))
                }
                .stroke(color.opacity(0.30), lineWidth: 1.0)

                // Bottom-Right ┘
                Path { p in
                    p.move(to: CGPoint(x: w - padH - bracketSize, y: h - padV))
                    p.addLine(to: CGPoint(x: w - padH, y: h - padV))
                    p.addLine(to: CGPoint(x: w - padH, y: h - padV - bracketSize))
                }
                .stroke(color.opacity(0.30), lineWidth: 1.0)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Granular Isolated Subview: Altitude & Heading Badge (Prevents Full-HUD Re-renders)

struct AltHdgTelemetryBadge: View {
    let altitudeMM: Float
    let headingDeg: Float
    let primaryColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(primaryColor)
                .frame(width: 2, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("ALT")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(primaryColor.opacity(0.8))
                    Text(String(format: "%.0fMM", altitudeMM))
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 4) {
                    Text("HDG")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(primaryColor.opacity(0.8))
                    Text(headingWithCardinal(headingDeg))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 0.04, green: 0.06, blue: 0.08).opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                )
        )
    }

    private func headingWithCardinal(_ deg: Float) -> String {
        let normalized = Int(deg) % 360
        let cardinals = ["N", "NE", "E", "SE", "S", "SW", "W", "NW", "N"]
        let index = Int((Double(normalized) + 22.5) / 45.0)
        let cardinal = cardinals[index % 8]
        return String(format: "%03d° %@", normalized, cardinal)
    }
}

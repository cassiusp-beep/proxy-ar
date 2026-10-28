import SwiftUI

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

            // 3. Main HUD Overlay Layout (Inset 52 pt horizontally to clear Dynamic Island)
            VStack(spacing: 0) {
                // Top Bar: Mission, Tactical Comms, Resources
                topBar
                    .padding(.horizontal, 52)
                    .padding(.top, 10)

                Spacer()

                // Center Margins: Flight Telemetry on Left, Optics & Power on Right
                HStack(alignment: .center) {
                    leftTelemetry
                        .padding(.leading, 52)

                    Spacer()

                    rightTelemetry
                        .padding(.trailing, 52)
                }

                Spacer()

                // Bottom Bar: Tactical Radar, Smoked Tool Selector, Target Status & Score
                bottomBar
                    .padding(.horizontal, 52)
                    .padding(.bottom, 12)
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

            // 6. Red Screen Damage Flash Vignette (Hostile Impact)
            if gameState.droneDamageFlashTimer > 0 {
                RoundedRectangle(cornerRadius: 54, style: .continuous)
                    .stroke(Color.red.opacity(Double(gameState.droneDamageFlashTimer / 0.45)), lineWidth: 16)
                    .background(Color.red.opacity(Double(gameState.droneDamageFlashTimer / 0.45) * 0.18))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // 7. Full-Screen Lost Connection / Telemetry Offline Overlay
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

    private var topBar: some View {
        HStack(alignment: .center, spacing: 8) {
            // Live Feed & Sector Tag
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text(gameState.currentMissionName.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("[\(gameState.currentSector)]")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(warningColor)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(smokedGlassBacking(cornerRadius: 6))

            // Central Operator Radio Transmission Line
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(primaryColor)

                Text(displayedRadioText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(smokedGlassBacking(cornerRadius: 6))

            Spacer()

            // Target Count & Mode Badge
            HStack(spacing: 8) {
                // Target Counter: 2/3
                HStack(spacing: 4) {
                    Text("TGT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(primaryColor.opacity(0.8))
                    Text("\(gameState.targetsTotal - gameState.targetsRemaining)/\(gameState.targetsTotal)")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(warningColor)
                }

                Divider()
                    .frame(height: 10)
                    .background(Color.white.opacity(0.2))

                // Mode Button
                Button {
                    let next = (gameState.prestigeLevel + 1) % 4
                    gameState.prestigeLevel = next
                    SessionLogger.shared.log("Prestige pill tapped: switched to \(next)", category: "HUD")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: prestigeIcon(gameState.prestigeLevel))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(primaryColor)
                        Text(prestigeBadgeTitle(gameState.prestigeLevel))
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(smokedGlassBacking(cornerRadius: 6))
        }
    }

    // MARK: - Margins Telemetry (Flight HUD)

    private var leftTelemetry: some View {
        VStack(alignment: .leading, spacing: 3) {
            AltHdgTelemetryBadge(
                altitudeMM: gameState.droneAltitudeMM,
                headingDeg: gameState.droneHeadingDeg,
                primaryColor: primaryColor
            )

            // Gimbal Slew Reticle Status (Active when joysticks used to aim)
            if gameState.isGimbalAimActive {
                Button {
                    gameState.resetGimbal()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "scope")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(accentColor)
                        Text("GIMBAL SLEW")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                        Text(GameInput.shared.isControllerConnected ? "[L3]" : "CENTER")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(primaryColor)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(smokedGlassBacking(cornerRadius: 4))
                }
            }
        }
    }

    private var rightTelemetry: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Optical Zoom Pill
            Button {
                gameState.cycleZoom()
            } label: {
                HStack(spacing: 5) {
                    Text("DIGI-ZOOM")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(primaryColor.opacity(0.85))
                    Text(String(format: "%.1fX", gameState.zoomFactor))
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)

                    if GameInput.shared.isControllerConnected {
                        Text("○")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 2))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(smokedGlassBacking(cornerRadius: 5))
            }

            // Tactical Hull Shield & Ordnance
            HStack(spacing: 6) {
                VStack(alignment: .trailing, spacing: 3) {
                    // Shield
                    HStack(spacing: 4) {
                        Text("DEF")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(primaryColor.opacity(0.8))
                        Text("\(Int(gameState.droneShield))%")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(shieldColor)
                    }

                    // Ammo
                    Button {
                        gameState.startReload()
                    } label: {
                        HStack(spacing: 4) {
                            Text(gameState.isReloading ? "RELOAD" : "ORD")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(primaryColor.opacity(0.8))
                            Text(gameState.isReloading ? "\(Int(gameState.reloadProgress * 100))%" : "\(gameState.ammo)/\(gameState.maxAmmo)")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundStyle(gameState.ammo <= 2 ? warningColor : .white)
                        }
                    }
                }

                Rectangle()
                    .fill(shieldColor)
                    .frame(width: 2, height: 26)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(smokedGlassBacking(cornerRadius: 6))
        }
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

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(alignment: .bottom, spacing: 14) {
            // Tactical Radar Widget
            tacticalRadarWidget

            Spacer()

            // 3-Slot Smoked Glass Tool Selector
            HStack(spacing: 6) {
                ForEach(GameState.ToolSlot.allCases, id: \.self) { tool in
                    toolSlotButton(tool: tool)
                }
            }
            .padding(4)
            .background(smokedGlassBacking(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
            )

            Spacer()

            // Recon Score
            HStack(spacing: 5) {
                Text("SCORE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                Text("\(gameState.score)")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(smokedGlassBacking(cornerRadius: 6))
        }
    }

    private func toolSlotButton(tool: GameState.ToolSlot) -> some View {
        let isSelected = gameState.selectedTool == tool
        return Button {
            gameState.selectedToolIndex = tool.rawValue
            if tool == .tag {
                GameInput.shared.tagTriggered = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    GameInput.shared.tagTriggered = false
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tool.iconName)
                    .font(.system(size: 11, weight: .bold))

                Text(tool.title.uppercased())
                    .font(.system(size: 10, weight: .black, design: .monospaced))

                // Ammunition badge for TAG tool slot
                if tool == .tag {
                    Text("[\(gameState.ammo)]")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.black : (gameState.ammo <= 2 ? warningColor : primaryColor))
                }

                // PlayStation controller button prompt
                if GameInput.shared.isControllerConnected {
                    if tool == .tag {
                        Text("R2")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(isSelected ? .black : .white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(isSelected ? Color.white : Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 2))
                    } else if tool == .scan {
                        Text("L2")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(isSelected ? .black : .white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(isSelected ? Color.white : Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 2))
                    }
                }
            }
            .foregroundStyle(isSelected ? Color.black : (isThermal ? primaryColor : .white))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected ? (isThermal ? primaryColor : accentColor) : Color.white.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? (isThermal ? primaryColor : accentColor) : Color.clear, lineWidth: 1)
            )
            .shadow(color: isSelected ? (isThermal ? primaryColor : accentColor).opacity(0.5) : .clear, radius: 6)
        }
    }

    // Tactical Radar Widget with grid lines & range rings
    private var tacticalRadarWidget: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.05, green: 0.07, blue: 0.09).opacity(0.85))
                .frame(width: 68, height: 58)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(primaryColor.opacity(0.4), lineWidth: 0.75)
                )

            // Radar concentric range circles
            Circle()
                .stroke(primaryColor.opacity(0.20), lineWidth: 0.75)
                .frame(width: 22, height: 22)

            Circle()
                .stroke(primaryColor.opacity(0.25), lineWidth: 0.75)
                .frame(width: 44, height: 44)

            // Crosshair lines
            Rectangle()
                .fill(primaryColor.opacity(0.20))
                .frame(width: 52, height: 0.5)

            Rectangle()
                .fill(primaryColor.opacity(0.20))
                .frame(width: 0.5, height: 44)

            // Center drone marker
            Circle()
                .fill(primaryColor)
                .frame(width: 4, height: 4)

            // Target blips
            Circle()
                .fill(accentColor)
                .frame(width: 3.5, height: 3.5)
                .offset(x: 10, y: -8)

            Circle()
                .fill(accentColor)
                .frame(width: 3.5, height: 3.5)
                .offset(x: -12, y: 11)

            // Radar sweep tag
            VStack {
                HStack {
                    Text("RDR // 25M")
                        .font(.system(size: 6, weight: .black, design: .monospaced))
                        .foregroundStyle(primaryColor.opacity(0.7))
                    Spacer()
                }
                Spacer()
            }
            .padding(4)
            .frame(width: 68, height: 58)
        }
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

    // Artificial Synthetic Sensor Crop Framing (Digital Surveillance Reconnaissance Mode)
    private var syntheticSensorCropOverlay: some View {
        ZStack {
            // Surveillance CRT edge vignette
            RadialGradient(
                colors: [.clear, Color.black.opacity(gameState.zoomFactor > 3.0 ? 0.44 : 0.28)],
                center: .center,
                startRadius: 170,
                endRadius: 440
            )
            .ignoresSafeArea()

            // Outer Digital Framing Telemetry Brackets
            VStack {
                HStack {
                    Text("┌ SYNTHETIC SENSOR CROP [\(String(format: "%.0fX", gameState.zoomFactor))] // DIGI-FOV \(gameState.zoomFactor > 3.0 ? "14°" : "28°")")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(primaryColor)
                    Spacer()
                    Text("SENSOR MATRIX: 4096×2160 // GAIN: +12dB ┐")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(primaryColor)
                }
                .padding(.horizontal, 64)
                .padding(.top, 44)

                Spacer()

                HStack {
                    Text("└ RESOLUTION ENHANCE: ON // IR-BAND: ACTIVE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(primaryColor)
                    Spacer()
                    Text("PRECISION SIGHTLINE: 0.25 MIL ┘")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(primaryColor)
                }
                .padding(.horizontal, 64)
                .padding(.bottom, 44)
            }

            // Central Artificial Sensor Crop Boundary Box with Cross-Rulers
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    primaryColor.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.5, dash: [10, 6])
                )
                .frame(width: gameState.zoomFactor > 3.0 ? 320 : 420,
                       height: gameState.zoomFactor > 3.0 ? 180 : 240)
                .overlay(
                    // Fine CRT horizontal scanlines across the cropped zone
                    VStack(spacing: 6) {
                        ForEach(0..<16, id: \.self) { _ in
                            Rectangle()
                                .fill(primaryColor.opacity(0.06))
                                .frame(height: 1)
                        }
                    }
                )
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

// MARK: - Curved Screen Bezel (Contoured to iPhone display curvature with Tactical Compass & Coordinates)

struct CurvedScreenBezelView: View {
    let color: Color
    var isFlashing: Bool = false
    var flashColor: Color = .white
    var heading: Float = 0
    private let cornerRadius: CGFloat = 52

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pad: CGFloat = 10

            ZStack {
                // Screen flash on impact / neutralization
                if isFlashing {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(flashColor, lineWidth: 4.5)
                        .padding(pad)
                        .shadow(color: flashColor.opacity(0.9), radius: 14)
                }

                // 1. Continuous curved outer boundary following the iPhone OLED glass
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                color.opacity(0.50),
                                color.opacity(0.12),
                                color.opacity(0.50),
                                color.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                    .padding(pad)

                // 2. Parallel subtle contour track
                RoundedRectangle(cornerRadius: cornerRadius - 4, style: .continuous)
                    .stroke(color.opacity(0.08), lineWidth: 0.75)
                    .padding(pad + 4)

                // 3. Four corner curved accent brackets highlighting the rounded corners
                Path { path in
                    // Top-Left corner curve
                    path.addArc(
                        center: CGPoint(x: pad + cornerRadius, y: pad + cornerRadius),
                        radius: cornerRadius,
                        startAngle: .degrees(175),
                        endAngle: .degrees(275),
                        clockwise: false
                    )

                    // Top-Right corner curve
                    path.addArc(
                        center: CGPoint(x: w - pad - cornerRadius, y: pad + cornerRadius),
                        radius: cornerRadius,
                        startAngle: .degrees(265),
                        endAngle: .degrees(365),
                        clockwise: false
                    )

                    // Bottom-Right corner curve
                    path.addArc(
                        center: CGPoint(x: w - pad - cornerRadius, y: h - pad - cornerRadius),
                        radius: cornerRadius,
                        startAngle: .degrees(355),
                        endAngle: .degrees(455),
                        clockwise: false
                    )

                    // Bottom-Left corner curve
                    path.addArc(
                        center: CGPoint(x: pad + cornerRadius, y: h - pad - cornerRadius),
                        radius: cornerRadius,
                        startAngle: .degrees(85),
                        endAngle: .degrees(185),
                        clockwise: false
                    )
                }
                .stroke(color.opacity(0.80), lineWidth: 2.0)

                // 4. Tactical Compass Tick Marks along top edge
                HStack(spacing: 14) {
                    ForEach(-4...4, id: \.self) { i in
                        let deg = (Int(heading) + i * 10 + 360) % 360
                        VStack(spacing: 2) {
                            Rectangle()
                                .fill(color.opacity(i == 0 ? 0.9 : 0.4))
                                .frame(width: 1, height: i == 0 ? 8 : 4)
                            if i == 0 {
                                Text("\(deg)°")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .foregroundStyle(color)
                            }
                        }
                    }
                }
                .position(x: w / 2, y: pad + 14)
            }
        }
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

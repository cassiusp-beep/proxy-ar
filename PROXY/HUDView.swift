import SwiftUI
import UIKit
import AudioToolbox

// MARK: - Windshield Liquid Glass ViewModifier

extension View {
    @ViewBuilder
    func windshieldGlass(cornerRadius: CGFloat = 16, isDepressed: Bool = false) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(isDepressed ? 0.03 : 0.07))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isDepressed ? 0.35 : 0.65), location: 0.0),
                                .init(color: Color.white.opacity(0.18), location: 0.40),
                                .init(color: Color.white.opacity(0.06), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            }
            .shadow(color: Color.black.opacity(isDepressed ? 0.35 : 0.18), radius: isDepressed ? 2 : 6, x: 0, y: isDepressed ? 1 : 3)
    }
}

// MARK: - Main Volvo Windshield HUD Overlay

struct HUDView: View {
    @Bindable var gameState = GameState.shared
    @Bindable var settings: PlacementSettings

    @State private var activeAlert: IslandAlert? = nil
    @State private var alertDismissWorkItem: DispatchWorkItem? = nil
    @State private var prevTargetLocked: Bool = false
    @State private var prevDamageTimer: Float = 0
    @State private var prevDeflectionTimer: Float = 0

    // Volvo Automotive Theme resolved against Prestige level
    private var theme: HUDTheme {
        HUDTheme.theme(for: gameState.hudThemePreset, prestige: gameState.prestigeLevel)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let isIslandOnLeft = geo.safeAreaInsets.leading > 30

            ZStack {
                // 0. Full-Screen Red Impact Flash & Perimeter Strobe
                if gameState.droneDamageFlashTimer > 0 {
                    let intensity = Double(min(gameState.droneDamageFlashTimer / 0.35, 1.0))
                    ZStack {
                        // Edge-focused crimson impact vignette
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.red.opacity(0.0),
                                Color.red.opacity(0.28 * intensity),
                                Color.red.opacity(0.70 * intensity)
                            ]),
                            center: .center,
                            startRadius: min(w, h) * 0.18,
                            endRadius: max(w, h) * 0.75
                        )

                        // Outer windshield perimeter red impact glow
                        RoundedRectangle(cornerRadius: gameState.cornerRadiusSetting, style: .continuous)
                            .strokeBorder(Color.red.opacity(0.90 * intensity), lineWidth: 4.5)
                            .padding(4)
                            .shadow(color: Color.red.opacity(0.95 * intensity), radius: 18)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.1), value: gameState.droneDamageFlashTimer)
                }

                // Kinetic Deflection Shield Pulse
                if gameState.boostDeflectionTimer > 0 {
                    let intensity = Double(min(gameState.boostDeflectionTimer / 0.40, 1.0))
                    RoundedRectangle(cornerRadius: gameState.cornerRadiusSetting, style: .continuous)
                        .strokeBorder(theme.accent.opacity(0.85 * intensity), lineWidth: 3.5)
                        .padding(4)
                        .shadow(color: theme.accent.opacity(0.90 * intensity), radius: 14)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.1), value: gameState.boostDeflectionTimer)
                }

                // Critical Connection Lost State
                if gameState.isConnectionLost {
                    ZStack {
                        Color.black.opacity(0.40)
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(theme.warning)
                            Text("HULL BREACH // RECONNECTING")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.text)
                            Text(String(format: "RESTORING TELEMETRY (%.1fs)", gameState.connectionLostCountdown))
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                                .foregroundStyle(theme.textSecondary)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.warning.opacity(0.4), lineWidth: 1))
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }

                // 1. Off-Screen Perimeter Target Chevrons
                EdgeTargetChevrons(
                    threats: gameState.radarThreats,
                    viewSize: CGSize(width: w, height: h),
                    theme: theme
                )

                // 2. Top Edge: Windshield Curved Heading Scale
                HeadingScale(
                    headingDeg: gameState.droneHeadingDeg,
                    theme: theme,
                    viewWidth: w
                )
                .position(x: w / 2, y: 26)

                // Mission Radio Text: Calm single-line HUD comms beneath heading
                if !gameState.radioMessage.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform")
                            .font(.system(size: 8))
                            .foregroundStyle(theme.accent)
                        Text(gameState.radioMessage)
                            .font(.system(size: 9.5, weight: .regular, design: .default))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                    .position(x: w / 2, y: 58)
                    .transition(.opacity)
                }

                // 3. Left Edge: Altitude Arc Gauge (Hugs Island cleanly on landscapeLeft)
                EdgeArcGauge(
                    type: .altitude,
                    value: gameState.droneAltitudeMM,
                    maxValue: 400.0,
                    climbRate: altitudeClimbRate,
                    secondaryNumeral: 0,
                    ammo: gameState.ammo,
                    maxAmmo: gameState.maxAmmo,
                    hasIslandOnThisSide: isIslandOnLeft,
                    theme: theme,
                    viewHeight: h
                )
                .position(x: isIslandOnLeft ? 134 : 72, y: h / 2)

                // 4. Right Edge: Fuel & Ordnance Arc Gauge (Mirrored)
                EdgeArcGauge(
                    type: .fuel,
                    value: gameState.fuel,
                    maxValue: 100.0,
                    climbRate: 0,
                    secondaryNumeral: gameState.score,
                    ammo: gameState.ammo,
                    maxAmmo: gameState.maxAmmo,
                    hasIslandOnThisSide: !isIslandOnLeft && geo.safeAreaInsets.trailing > 30,
                    theme: theme,
                    viewHeight: h
                )
                .position(x: w - (!isIslandOnLeft && geo.safeAreaInsets.trailing > 30 ? 134 : 72), y: h / 2)

                // 5. Dynamic Island Hardware Integration Capsule & Spring Alerts
                DynamicIslandHUD(
                    isIslandOnLeft: isIslandOnLeft,
                    isSynced: gameState.isTargetLocked || gameState.droneAltitudeMM > 50,
                    activeAlert: activeAlert,
                    theme: theme,
                    viewWidth: w,
                    viewHeight: h
                )

                // 6. Center: Minimalist Reticle with Target Acquiring Ring (No Text Boxes)
                VolvoReticleView(
                    isLocked: gameState.isTargetLocked,
                    lockProgress: gameState.lockProgress,
                    strikeText: gameState.strikePopupText,
                    isStriking: gameState.strikePopupTimer > 0,
                    recoilKick: gameState.fireRecoilTimer > 0,
                    theme: theme
                )
                .offset(x: gameState.reticleOffset.x, y: gameState.reticleOffset.y)
                .position(x: w / 2, y: h / 2)

                // 7. Bottom Corners: Two Sculpted Glass Keys (Scan L2 & Tag R2)
                VStack {
                    Spacer()
                    HStack {
                        CornerGlassKey(
                            role: .scan,
                            triggerHint: "L2",
                            isSelected: gameState.selectedTool == .scan,
                            theme: theme
                        ) {
                            gameState.selectedToolIndex = GameState.ToolSlot.scan.rawValue
                        }
                        .padding(.leading, isIslandOnLeft ? 52 : 32)
                        .padding(.bottom, 16)

                        Spacer()

                        CornerGlassKey(
                            role: .tag,
                            triggerHint: "R2",
                            isSelected: gameState.selectedTool == .tag,
                            theme: theme
                        ) {
                            gameState.selectedToolIndex = GameState.ToolSlot.tag.rawValue
                            GameInput.shared.tagTriggered = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                GameInput.shared.tagTriggered = false
                            }
                        }
                        .padding(.trailing, !isIslandOnLeft && geo.safeAreaInsets.trailing > 30 ? 52 : 32)
                        .padding(.bottom, 16)
                    }
                }
            }
            .ignoresSafeArea()
            .onAppear {
                DroneAudioEngine.shared.start()
            }
            .onChange(of: gameState.droneDamageFlashTimer) { _, newTimer in
                if newTimer > 0 && prevDamageTimer == 0 {
                    triggerAlert(icon: "shield.slash.fill", text: "Shield \(Int(gameState.droneShield))%", isWarning: true)
                }
                prevDamageTimer = newTimer
            }
            .onChange(of: gameState.boostDeflectionTimer) { _, newTimer in
                if newTimer > 0 && prevDeflectionTimer == 0 {
                    triggerAlert(icon: "shield.lefthalf.filled.badge.checkmark", text: "Threat deflected", isWarning: false)
                }
                prevDeflectionTimer = newTimer
            }
            .onChange(of: gameState.isTargetLocked) { _, locked in
                if locked && !prevTargetLocked {
                    triggerAlert(icon: "target", text: "Target locked", isWarning: false)
                }
                prevTargetLocked = locked
            }
        }
    }

    private var altitudeClimbRate: Float {
        let nominalAlt: Float = 190.0
        let delta = gameState.droneAltitudeMM - nominalAlt
        return delta > 8 ? 0.2 : (delta < -8 ? -0.2 : 0.0)
    }

    private func triggerAlert(icon: String, text: String, isWarning: Bool) {
        alertDismissWorkItem?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            activeAlert = IslandAlert(icon: icon, text: text, isWarning: isWarning)
        }
        let workItem = DispatchWorkItem {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.activeAlert = nil
            }
        }
        alertDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
}

// MARK: - Island Alert Data Model

struct IslandAlert: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let text: String
    let isWarning: Bool
}

// MARK: - 1. Edge Arc Gauge (Volvo Instrument Curve)

struct EdgeArcGauge: View {
    enum GaugeType {
        case altitude
        case fuel
    }

    let type: GaugeType
    let value: Float
    let maxValue: Float
    let climbRate: Float
    let secondaryNumeral: Int
    let ammo: Int
    let maxAmmo: Int
    let hasIslandOnThisSide: Bool
    let theme: HUDTheme
    let viewHeight: CGFloat

    private var progress: Double {
        Double(min(max(value / maxValue, 0.0), 1.0))
    }

    private var arcStrokeColor: Color {
        if type == .fuel && value < 20 {
            return theme.warning
        }
        return theme.accent
    }

    var body: some View {
        let h = min(280.0, viewHeight * 0.68)
        let isRight = (type == .fuel)

        ZStack(alignment: isRight ? .trailing : .leading) {
            // Background Frosted Arc Channel
            ArcTrackShape(isMirrored: isRight, hasIslandCutout: hasIslandOnThisSide)
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .frame(width: 90, height: h)

            // Luminous Sweeping Gradient Band
            ArcTrackShape(isMirrored: isRight, hasIslandCutout: hasIslandOnThisSide)
                .trim(from: 0.0, to: CGFloat(progress))
                .stroke(
                    LinearGradient(
                        colors: [arcStrokeColor.opacity(0.15), arcStrokeColor.opacity(0.85)],
                        startPoint: .bottom,
                        endPoint: .top
                    ),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .frame(width: 90, height: h)
                .shadow(color: arcStrokeColor.opacity(0.40), radius: 6)

            // Precision Etched Needle Index (Volvo Luminous Needle Marker)
            if progress > 0.01 {
                ArcTrackShape(isMirrored: isRight, hasIslandCutout: hasIslandOnThisSide)
                    .trim(from: max(0.0, CGFloat(progress) - 0.016), to: CGFloat(progress))
                    .stroke(
                        Color.white,
                        style: StrokeStyle(lineWidth: 18, lineCap: .butt)
                    )
                    .frame(width: 90, height: h)
                    .shadow(color: Color.white.opacity(0.9), radius: 3)
            }

            // Fine Etched Tick Marks along outer rim
            ArcTicksOverlay(isMirrored: isRight, hasIslandCutout: hasIslandOnThisSide, theme: theme)
                .frame(width: 90, height: h)

            // Inside Center: Large Volvo-style Numeral & Units
            VStack(alignment: isRight ? .trailing : .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if isRight {
                        Text("\(Int(value))")
                            .font(.system(size: 38, weight: .light, design: .rounded))
                            .foregroundStyle(arcStrokeColor)
                            .contentTransition(.numericText())
                        Text("%")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(theme.textSecondary)
                    } else {
                        Text("\(Int(value))")
                            .font(.system(size: 38, weight: .light, design: .rounded))
                            .foregroundStyle(theme.text)
                            .contentTransition(.numericText())
                        Text("mm")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(theme.textSecondary)
                    }
                }

                if type == .altitude {
                    // Vertical Speed: Tiny arrow and number beneath
                    HStack(spacing: 2) {
                        Image(systemName: climbRate > 0 ? "arrow.up" : (climbRate < 0 ? "arrow.down" : "minus"))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(theme.textSecondary)
                        Text(String(format: "%.1f", abs(climbRate)))
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundStyle(theme.textSecondary)
                    }
                } else {
                    // Right Arc: Companion Score Numeral + Glass Ordnance Dots
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("\(secondaryNumeral)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.textSecondary)

                        // Ordnance Glass Beads along inner edge
                        HStack(spacing: 3) {
                            ForEach(0..<maxAmmo, id: \.self) { idx in
                                Circle()
                                    .fill(idx < ammo ? (ammo <= 2 ? theme.warning : theme.accent) : Color.white.opacity(0.12))
                                    .frame(width: 4, height: 4)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                                    )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, isRight ? 18 : 16)
        }
        .frame(width: 120, height: h)
        .allowsHitTesting(false)
    }
}

// MARK: - Arc Track Geometry Shape

struct ArcTrackShape: Shape {
    let isMirrored: Bool
    let hasIslandCutout: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cornerR: CGFloat = 48.0

        if !isMirrored {
            // Left Arc: Starts top-right, curves down along left edge, curves back right at bottom
            let topX = w - 12
            let botX = w - 12
            let spineX: CGFloat = hasIslandCutout ? 38 : 18

            path.move(to: CGPoint(x: topX, y: 12))
            path.addQuadCurve(to: CGPoint(x: spineX, y: cornerR + 10), control: CGPoint(x: spineX + 8, y: 12))
            path.addLine(to: CGPoint(x: spineX, y: h - cornerR - 10))
            path.addQuadCurve(to: CGPoint(x: botX, y: h - 12), control: CGPoint(x: spineX + 8, y: h - 12))
        } else {
            // Right Arc: Mirrored
            let topX: CGFloat = 12
            let botX: CGFloat = 12
            let spineX: CGFloat = w - (hasIslandCutout ? 38 : 18)

            path.move(to: CGPoint(x: topX, y: 12))
            path.addQuadCurve(to: CGPoint(x: spineX, y: cornerR + 10), control: CGPoint(x: spineX - 8, y: 12))
            path.addLine(to: CGPoint(x: spineX, y: h - cornerR - 10))
            path.addQuadCurve(to: CGPoint(x: botX, y: h - 12), control: CGPoint(x: spineX - 8, y: h - 12))
        }

        return path
    }
}

// MARK: - Fine Etched Ticks Overlay

struct ArcTicksOverlay: View {
    let isMirrored: Bool
    let hasIslandCutout: Bool
    let theme: HUDTheme

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let tickCount = 11

            ZStack {
                ForEach(0..<tickCount, id: \.self) { i in
                    let fraction = CGFloat(i) / CGFloat(tickCount - 1)
                    let y = 18 + fraction * (h - 36)
                    let isMajor = (i % 2 == 0)

                    Rectangle()
                        .fill(isMajor ? Color.white.opacity(0.40) : Color.white.opacity(0.18))
                        .frame(width: isMajor ? 7 : 4, height: 0.75)
                        .position(
                            x: isMirrored ? (w - (hasIslandCutout ? 20 : 6)) : (hasIslandCutout ? 20 : 6),
                            y: y
                        )
                }
            }
        }
    }
}

// MARK: - 2. Windshield Curved Heading Scale (Top Edge)

struct HeadingScale: View {
    let headingDeg: Float
    let theme: HUDTheme
    let viewWidth: CGFloat

    var body: some View {
        let currentHeading = Int(headingDeg) % 360

        VStack(spacing: 2) {
            // Subtle Hairline Pointer
            Rectangle()
                .fill(theme.accent)
                .frame(width: 1, height: 6)

            // Current Heading Large Calm Numeral
            Text(headingText(currentHeading))
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(theme.text)
                .contentTransition(.numericText())

            // Hairline Etched Degree Scale on Glass
            HStack(spacing: 12) {
                ForEach(-4...4, id: \.self) { offset in
                    let mark = (currentHeading + offset * 10 + 360) % 360
                    let isMajor = (mark % 30 == 0)

                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(offset == 0 ? theme.accent : Color.white.opacity(isMajor ? 0.35 : 0.15))
                            .frame(width: 0.75, height: isMajor ? 6 : 3.5)

                        if isMajor {
                            Text(cardinalOrDegrees(mark))
                                .font(.system(size: 8, weight: .regular, design: .rounded))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                    .frame(width: 22)
                }
            }
        }
        .frame(maxWidth: min(380, viewWidth * 0.45))
        .allowsHitTesting(false)
    }

    private func headingText(_ deg: Int) -> String {
        let cardinals = ["N", "NE", "E", "SE", "S", "SW", "W", "NW", "N"]
        let index = Int((Double(deg) + 22.5) / 45.0)
        let cardinal = cardinals[index % 8]
        return "\(deg)° \(cardinal)"
    }

    private func cardinalOrDegrees(_ deg: Int) -> String {
        switch deg {
        case 0: return "N"
        case 90: return "E"
        case 180: return "S"
        case 270: return "W"
        default: return "\(deg)°"
        }
    }
}

// MARK: - 3. Minimalist Center Reticle with Acquiring Ring

struct VolvoReticleView: View {
    let isLocked: Bool
    let lockProgress: Float
    let strikeText: String
    let isStriking: Bool
    let recoilKick: Bool
    let theme: HUDTheme

    var body: some View {
        ZStack {
            // Outer Smooth Target Acquiring Progress Ring (Draws smoothly around reticle)
            Circle()
                .trim(from: 0.0, to: CGFloat(min(max(lockProgress, 0.0), 1.0)))
                .stroke(
                    isLocked ? theme.accent : theme.accent.opacity(0.45),
                    style: StrokeStyle(lineWidth: isLocked ? 1.5 : 1.0, lineCap: .round)
                )
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.12), value: lockProgress)
                .scaleEffect(isLocked ? 1.06 : 1.0)
                .shadow(color: isLocked ? theme.accent.opacity(0.65) : .clear, radius: 8)

            // Inner Fine Crosshair Dot
            Circle()
                .fill(isLocked ? theme.accent : Color.white.opacity(0.85))
                .frame(width: 3, height: 3)

            // Four Delicate Hairline Ticks (12, 3, 6, 9 o'clock)
            ForEach([0, 90, 180, 270], id: \.self) { deg in
                Rectangle()
                    .fill(Color.white.opacity(isLocked ? 0.8 : 0.4))
                    .frame(width: 0.75, height: 4)
                    .offset(y: -14)
                    .rotationEffect(.degrees(Double(deg)))
            }

            // Target Neutralized Transient Sparkle (Minimal, no huge red boxes)
            if isStriking {
                Circle()
                    .stroke(theme.accent, lineWidth: 1.5)
                    .frame(width: 56, height: 56)
                    .scaleEffect(1.2)
                    .opacity(0.85)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(recoilKick ? 1.08 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: recoilKick)
        .allowsHitTesting(false)
    }
}

// MARK: - 4. Sculpted Bottom-Corner Glass Keys (Scan & Tag)

struct CornerGlassKey: View {
    enum KeyRole {
        case scan
        case tag
    }

    let role: KeyRole
    let triggerHint: String
    let isSelected: Bool
    let theme: HUDTheme
    let action: () -> Void

    @State private var isTouchDepressed: Bool = false

    private var isPhysicalTriggerPulled: Bool {
        if role == .scan {
            return GameInput.shared.isL2Pressed
        } else {
            return GameInput.shared.isR2Pressed
        }
    }

    private var isDepressed: Bool {
        isTouchDepressed || isPhysicalTriggerPulled
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 7) {
                if role == .scan {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                }

                Text(role == .scan ? "Scan" : "Tag")
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular, design: .default))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .fixedSize()

                Spacer(minLength: 4)

                // Etched Trigger Hint in Glass
                Text(triggerHint)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(theme.textSecondary.opacity(0.6))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    )

                if role == .tag {
                    Circle()
                        .fill(isSelected ? theme.accent : Color.white.opacity(0.20))
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 114, height: 38)
            .windshieldGlass(cornerRadius: 18, isDepressed: isDepressed)
            .scaleEffect(isDepressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isDepressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isTouchDepressed = true }
                .onEnded { _ in isTouchDepressed = false }
        )
    }
}

// MARK: - 5. Dynamic Island Hardware Integration & Spring Alerts

struct DynamicIslandHUD: View {
    let isIslandOnLeft: Bool
    let isSynced: Bool
    let activeAlert: IslandAlert?
    let theme: HUDTheme
    let viewWidth: CGFloat
    let viewHeight: CGFloat

    var body: some View {
        ZStack(alignment: isIslandOnLeft ? .leading : .trailing) {
            // Hardware-matching Island Pill & Software Growth Capsule
            HStack(spacing: 7) {
                if let alert = activeAlert {
                    // Expanding Spring Alert Badge
                    Image(systemName: alert.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(alert.isWarning ? theme.warning : theme.accent)

                    Text(alert.text)
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                } else {
                    // Resting Sync State
                    Circle()
                        .fill(isSynced ? Color.green : theme.warning)
                        .frame(width: 5, height: 5)

                    Text(isSynced ? "Synced" : "Searching…")
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(Color.black.opacity(0.92))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            }
            .shadow(color: Color.black.opacity(0.3), radius: 6)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: activeAlert)
            .position(
                x: isIslandOnLeft ? 52 : (viewWidth - 52),
                y: viewHeight / 2
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 6. Perimeter Off-Screen Target Chevrons (Radar Replacement)

struct EdgeTargetChevrons: View {
    let threats: [GameState.RadarThreat]
    let viewSize: CGSize
    let theme: HUDTheme

    var body: some View {
        let w = viewSize.width
        let h = viewSize.height
        let inset: CGFloat = 16

        ZStack {
            ForEach(threats) { threat in
                // Only show chevrons for targets outside forward boresight
                if abs(threat.azimuthRad) > 0.40 || threat.distanceNorm > 0.65 {
                    let angle = Double(threat.azimuthRad) - .pi / 2
                    let pt = edgeIntersection(angle: angle, width: w, height: h, inset: inset)
                    let chevronColor = threat.isProjectile ? theme.warning : (threat.isTagged ? Color.green.opacity(0.6) : theme.accent)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(chevronColor)
                        .rotationEffect(.radians(angle))
                        .position(pt)
                        .shadow(color: chevronColor.opacity(0.5), radius: 4)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func edgeIntersection(angle: Double, width: CGFloat, height: CGFloat, inset: CGFloat) -> CGPoint {
        let cx = width / 2
        let cy = height / 2
        let halfW = cx - inset
        let halfH = cy - inset

        let cosA = cos(angle)
        let sinA = sin(angle)

        let tX = (cosA > 0) ? halfW / cosA : -halfW / cosA
        let tY = (sinA > 0) ? halfH / sinA : -halfH / sinA

        let t = min(abs(tX), abs(tY))
        return CGPoint(x: cx + CGFloat(cosA * t), y: cy + CGFloat(sinA * t))
    }
}

// MARK: - SwiftUI Previews

#Preview("Volvo Windshield HUD - Ice (Default)") {
    HUDView(settings: PlacementSettings())
        .previewInterfaceOrientation(.landscapeLeft)
        .background(Color(red: 0.10, green: 0.12, blue: 0.14))
}

#Preview("Volvo Windshield HUD - Bloom (Candy)") {
    let gs = GameState.shared
    gs.hudThemePreset = .bloom
    return HUDView(settings: PlacementSettings())
        .previewInterfaceOrientation(.landscapeLeft)
        .background(Color(red: 0.10, green: 0.12, blue: 0.14))
}

#Preview("Volvo Windshield HUD - Prestige 3 (Thermal)") {
    let gs = GameState.shared
    gs.prestigeLevel = 3
    return HUDView(settings: PlacementSettings())
        .previewInterfaceOrientation(.landscapeLeft)
        .background(Color(red: 0.05, green: 0.05, blue: 0.05))
}

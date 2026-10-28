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
                            .fill(Color.white.opacity(isDepressed ? 0.03 : 0.08))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isDepressed ? 0.35 : 0.65), location: 0.0),
                                .init(color: Color.white.opacity(0.20), location: 0.40),
                                .init(color: Color.white.opacity(0.08), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
            }
            .shadow(color: Color.black.opacity(isDepressed ? 0.40 : 0.22), radius: isDepressed ? 3 : 8, x: 0, y: isDepressed ? 1 : 4)
    }

    /// Dark legibility shadow ensuring contrast >= 4.5:1 over bright white markers and dark terrain
    func hudLegibilityShadow() -> some View {
        self
            .shadow(color: Color.black.opacity(0.90), radius: 3, x: 0, y: 1.5)
            .shadow(color: Color.black.opacity(0.50), radius: 7, x: 0, y: 3)
    }
}

// MARK: - Main Volvo Windshield HUD Overlay

struct HUDView: View {
    @Bindable var gameState = GameState.shared
    @Bindable var settings: PlacementSettings

    @State private var prevTargetLocked: Bool = false
    @State private var prevFuelLow: Bool = false
    @State private var isPhotoFlashActive: Bool = false

    private var theme: HUDTheme {
        HUDTheme.theme(for: gameState.hudThemePreset, prestige: gameState.prestigeLevel)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // 1. One Symmetric Frame: Use the larger of safeArea insets on BOTH sides + 14pt edge inset
            let safeLeading = geo.safeAreaInsets.leading
            let safeTrailing = geo.safeAreaInsets.trailing
            let maxSafeArea = max(safeLeading, safeTrailing)
            let effectiveSafeArea = maxSafeArea > 30 ? maxSafeArea : 59.0 // Guaranteed hardware margin
            let edgeInset: CGFloat = 14.0

            // Mirrored margin used identically on BOTH sides
            let symmetricMargin: CGFloat = effectiveSafeArea + edgeInset

            // Island detection (for mirroring sync chip away from obstacle)
            let isIslandOnLeft = (gameState.islandSideOverride == .left) || (gameState.islandSideOverride == .auto && safeLeading > 30)
            let isIslandOnRight = (gameState.islandSideOverride == .right) || (gameState.islandSideOverride == .auto && safeTrailing > 30)

            // Full-height arc coordinates: from below top corner curve to 12pt above corner key cluster
            let arcTopY: CGFloat = 50
            let keyClusterHeight: CGFloat = 38 + 12 + 48 // 38 (stacked) + 12 (gap) + 48 (main) = 98 pt
            let arcBottomY: CGFloat = h - 14 - keyClusterHeight - 12 // Even 12pt gap above key cluster

            ZStack {
                // 1. Simple Soft Damage Vignette Pulse in Theme Warning Color (~300ms)
                if gameState.droneDamageFlashTimer > 0 {
                    let intensity = Double(min(gameState.droneDamageFlashTimer / 0.30, 1.0))
                    RadialGradient(
                        gradient: Gradient(colors: [
                            theme.warning.opacity(0.0),
                            theme.warning.opacity(0.18 * intensity),
                            theme.warning.opacity(0.60 * intensity)
                        ]),
                        center: .center,
                        startRadius: min(w, h) * 0.25,
                        endRadius: max(w, h) * 0.75
                    )
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

                // Hero Shot Camera Shutter Flash
                if isPhotoFlashActive {
                    Color.white.opacity(0.85)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // 2. Off-Screen Perimeter Target Chevrons
                EdgeTargetChevrons(
                    threats: gameState.radarThreats,
                    viewSize: CGSize(width: w, height: h),
                    theme: theme
                )

                // 3. Top Center: Windshield Curved Heading Scale & Single Toast / Radio Comms (Mutually Exclusive)
                VStack(spacing: 8) {
                    HeadingScale(
                        headingDeg: gameState.droneHeadingDeg,
                        theme: theme,
                        viewWidth: w
                    )

                    // Single Toast at Top Center (Hides radio line completely while visible)
                    ZStack {
                        if let toast = gameState.activeToast {
                            HStack(spacing: 7) {
                                Image(systemName: toast.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(toast.isWarning ? theme.warning : theme.accent)

                                Text(toast.text)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(theme.text)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.75))
                            .shadow(color: Color.black.opacity(0.35), radius: 6)
                            .transition(.opacity)
                        } else if !gameState.radioMessage.isEmpty {
                            // Radio line displayed only when NO toast is active
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(theme.accent)

                                Text(gameState.radioMessage)
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(theme.text)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                            .frame(maxWidth: min(390, w * 0.46))
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.22), value: gameState.activeToast != nil)
                }
                .padding(.top, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // 4. Left Edge: Full-Height Instrument Altitude Arc Gauge
                FullHeightArcGauge(
                    type: .altitude,
                    value: gameState.droneAltitudeMM,
                    maxValue: 400.0,
                    climbRate: altitudeClimbRate,
                    secondaryNumeral: 0,
                    shield: gameState.droneShield,
                    ammo: gameState.ammo,
                    maxAmmo: gameState.maxAmmo,
                    spineX: symmetricMargin,
                    topY: arcTopY,
                    bottomY: arcBottomY,
                    theme: theme,
                    viewWidth: w
                )

                // 6. Right Edge: Full-Height Instrument Fuel Arc Gauge
                FullHeightArcGauge(
                    type: .fuel,
                    value: gameState.fuel,
                    maxValue: 100.0,
                    climbRate: 0,
                    secondaryNumeral: gameState.score,
                    shield: gameState.droneShield,
                    ammo: gameState.ammo,
                    maxAmmo: gameState.maxAmmo,
                    spineX: w - symmetricMargin,
                    topY: arcTopY,
                    bottomY: arcBottomY,
                    theme: theme,
                    viewWidth: w
                )

                // 7. Center: Minimalist Volvo Reticle (25% Larger, 2.5pt Strokes)
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

                // 8. Zoom Glass Chip (Directly Below Reticle, Centered on Same Vertical Line)
                ZoomReticleChip(zoomFactor: gameState.zoomFactor, theme: theme) {
                    gameState.cycleZoom()
                }
                .position(
                    x: w / 2 + gameState.reticleOffset.x,
                    y: h / 2 + gameState.reticleOffset.y + 54
                )

                // 9. Bottom Corners: Two Breathe Clusters (Scan+Boost Left, Tag+Photo Right)
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        // Left Cluster: Boost stacked directly above Scan
                        VStack(alignment: .leading, spacing: 12) {
                            StackedShelfButton(
                                iconName: "bolt.fill",
                                label: "Boost",
                                hint: "L1",
                                hintSystemImage: nil,
                                isSelected: gameState.isBoostActive || gameState.selectedTool == .boost,
                                theme: theme
                            ) {
                                gameState.selectedToolIndex = GameState.ToolSlot.boost.rawValue
                                _ = gameState.triggerBoost()
                            }

                            CornerQuarterMainKey(
                                corner: .bottomLeading,
                                label: "Scan",
                                hint: "L2",
                                iconName: "viewfinder",
                                isSelected: gameState.selectedTool == .scan,
                                theme: theme
                            ) {
                                gameState.selectedToolIndex = GameState.ToolSlot.scan.rawValue
                            }
                        }
                        .padding(.leading, symmetricMargin)
                        .padding(.bottom, 14)

                        Spacer()

                        // Center Bottom Row: Synced State Button
                        SyncStateGlassChip(
                            isSynced: gameState.isTargetLocked || gameState.droneAltitudeMM > 50,
                            theme: theme
                        ) {
                            gameState.showToast(icon: "antenna.radiowaves.left.and.right", text: "Telemetry link active", isWarning: false)
                        }
                        .padding(.bottom, 16)

                        Spacer()

                        // Right Cluster: Photo stacked directly above Tag
                        VStack(alignment: .trailing, spacing: 12) {
                            StackedShelfButton(
                                iconName: "camera.fill",
                                label: "Photo",
                                hint: nil,
                                hintSystemImage: "triangle",
                                isSelected: false,
                                theme: theme
                            ) {
                                triggerPhotoCapture()
                            }

                            CornerQuarterMainKey(
                                corner: .bottomTrailing,
                                label: "Tag",
                                hint: "R2",
                                iconName: "target",
                                isSelected: gameState.selectedTool == .tag,
                                theme: theme
                            ) {
                                gameState.selectedToolIndex = GameState.ToolSlot.tag.rawValue
                                GameInput.shared.tagTriggered = true
                                FlashlightController.shared.flash()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    GameInput.shared.tagTriggered = false
                                }
                            }
                        }
                        .padding(.trailing, symmetricMargin)
                        .padding(.bottom, 14)
                    }
                }
            }
            .offset(x: gameState.damageShakeOffset.width, y: gameState.damageShakeOffset.height)
            .ignoresSafeArea()
            .onAppear {
                DroneAudioEngine.shared.start()
            }
            .onChange(of: gameState.isTargetLocked) { _, locked in
                if locked && !prevTargetLocked {
                    gameState.showToast(icon: "target", text: "Target locked", isWarning: false)
                }
                prevTargetLocked = locked
            }
            .onChange(of: gameState.fuel) { _, newFuel in
                if newFuel < 20.0 && !prevFuelLow {
                    gameState.showToast(icon: "battery.25", text: "Fuel low (\(Int(newFuel))%)", isWarning: true)
                    prevFuelLow = true
                } else if newFuel >= 20.0 {
                    prevFuelLow = false
                }
            }
            .onChange(of: gameState.targetsRemaining) { _, remaining in
                if remaining == 0 {
                    gameState.showToast(icon: "checkmark.circle.fill", text: "Sector secured", isWarning: false)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var altitudeClimbRate: Float {
        let nominalAlt: Float = 190.0
        let delta = gameState.droneAltitudeMM - nominalAlt
        return delta > 8 ? 0.2 : (delta < -8 ? -0.2 : 0.0)
    }

    private func triggerPhotoCapture() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        AudioServicesPlaySystemSound(1108) // Camera shutter
        SnapshotStore.shared.captureAction(tag: "manual_hero")
        withAnimation(.easeOut(duration: 0.08)) {
            isPhotoFlashActive = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.18)) {
                self.isPhotoFlashActive = false
            }
        }
        gameState.showToast(icon: "camera.fill", text: "Hero shot saved", isWarning: false)
    }
}

// MARK: - 1. Center Bottom Row Sync State Glass Chip

struct SyncStateGlassChip: View {
    let isSynced: Bool
    let theme: HUDTheme
    var onTap: (() -> Void)? = nil

    @State private var isTouchDepressed: Bool = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap?()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isSynced ? Color.green : theme.warning)
                    .frame(width: 6, height: 6)

                Text(isSynced ? "Synced" : "Searching…")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.text)
                    .hudLegibilityShadow()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isTouchDepressed ? 0.35 : 0.60), location: 0.0),
                                .init(color: Color.white.opacity(0.18), location: 0.50),
                                .init(color: Color.white.opacity(0.08), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: Color.black.opacity(0.25), radius: 6, y: 2)
            .scaleEffect(isTouchDepressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isTouchDepressed)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isTouchDepressed = true }
                .onEnded { _ in isTouchDepressed = false }
        )
    }
}

// MARK: - 2. Full-Height Instrument Arc Gauge

struct FullHeightArcGauge: View {
    enum GaugeType {
        case altitude
        case fuel
    }

    let type: GaugeType
    let value: Float
    let maxValue: Float
    let climbRate: Float
    let secondaryNumeral: Int
    let shield: Float
    let ammo: Int
    let maxAmmo: Int
    let spineX: CGFloat
    let topY: CGFloat
    let bottomY: CGFloat
    let theme: HUDTheme
    let viewWidth: CGFloat

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
        let isRight = (type == .fuel)

        ZStack {
            // A. Arc Track: 4 pt, low-opacity
            FullHeightArcShape(
                isRight: isRight,
                spineX: spineX,
                topY: topY,
                bottomY: bottomY
            )
            .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 4.0, lineCap: .round))

            // B. Value Band: 8 pt, theme accent gradient with round cap
            FullHeightArcShape(
                isRight: isRight,
                spineX: spineX,
                topY: topY,
                bottomY: bottomY
            )
            .trim(from: 0.0, to: CGFloat(progress))
            .stroke(
                LinearGradient(
                    colors: [arcStrokeColor.opacity(0.35), arcStrokeColor],
                    startPoint: .bottom,
                    endPoint: .top
                ),
                style: StrokeStyle(lineWidth: 8.0, lineCap: .round)
            )
            .shadow(color: arcStrokeColor.opacity(0.50), radius: 8)

            // C. Needle: 3 pt stroke with round cap
            FullHeightArcNeedle(
                isRight: isRight,
                spineX: spineX,
                topY: topY,
                bottomY: bottomY,
                progress: progress,
                needleColor: .white
            )

            // D. Major Ticks (2.5pt) and Minor Ticks (1.5pt) with 13pt Semibold Numerals
            FullHeightArcTicks(
                type: type,
                isRight: isRight,
                spineX: spineX,
                topY: topY,
                bottomY: bottomY,
                theme: theme
            )

            // E. Large Gauge Numeral (46pt semibold) & Secondary Readouts (15pt medium)
            // Sits inside arc, vertically centered on arc, with 12pt gap from tick numerals
            let readoutCenterY: CGFloat = (topY + bottomY) / 2

            VStack(alignment: isRight ? .trailing : .leading, spacing: 5) {
                // Dominant Numeral (46pt semibold)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(value))")
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .foregroundStyle(isRight ? arcStrokeColor : theme.text)
                        .contentTransition(.numericText())
                        .hudLegibilityShadow()

                    Text(isRight ? "%" : "mm")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.textSecondary)
                        .hudLegibilityShadow()
                }

                if type == .altitude {
                    // Vertical Speed (15pt medium, clearly labeled)
                    HStack(spacing: 5) {
                        Text("V/S")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.textSecondary)

                        Image(systemName: climbRate > 0 ? "arrow.up" : (climbRate < 0 ? "arrow.down" : "minus"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(theme.textSecondary)

                        Text(String(format: "%+.1f m/s", climbRate))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .hudLegibilityShadow()

                    // Dedicated Hull Shield Meter (15pt medium)
                    HStack(spacing: 5) {
                        Text("Shield")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.textSecondary)

                        HStack(spacing: 2.5) {
                            ForEach(0..<8, id: \.self) { seg in
                                let threshold = Float(seg + 1) * 12.5
                                Rectangle()
                                    .fill(shield >= threshold ? (shield < 25 ? theme.warning : theme.accent) : Color.white.opacity(0.18))
                                    .frame(width: 5, height: 7)
                                    .cornerRadius(1)
                            }
                        }

                        Text("\(Int(shield))%")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(shield < 25 ? theme.warning : theme.textSecondary)
                    }
                    .hudLegibilityShadow()
                } else {
                    // Right Side: Score and Ordnance (15pt medium)
                    HStack(spacing: 5) {
                        Text("Score")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.textSecondary)

                        Text("\(secondaryNumeral)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.text)
                    }
                    .hudLegibilityShadow()

                    HStack(spacing: 5) {
                        Text("Ord")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.textSecondary)

                        Text("\(ammo)/\(maxAmmo)")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.textSecondary)

                        HStack(spacing: 3) {
                            ForEach(0..<maxAmmo, id: \.self) { idx in
                                Circle()
                                    .fill(idx < ammo ? (ammo <= 2 ? theme.warning : theme.accent) : Color.white.opacity(0.20))
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                    .hudLegibilityShadow()
                }
            }
            .frame(width: 170, alignment: isRight ? .trailing : .leading)
            .position(
                x: isRight ? (spineX - 44 - 85) : (spineX + 44 + 85),
                y: readoutCenterY
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

// MARK: - Full-Height Arc Rail Shape

struct FullHeightArcShape: Shape {
    let isRight: Bool
    let spineX: CGFloat
    let topY: CGFloat
    let bottomY: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: spineX, y: bottomY))
        path.addLine(to: CGPoint(x: spineX, y: topY))
        return path
    }
}

// MARK: - Full-Height Arc Needle (3pt Stroke with Round Cap)

struct FullHeightArcNeedle: View {
    let isRight: Bool
    let spineX: CGFloat
    let topY: CGFloat
    let bottomY: CGFloat
    let progress: Double
    let needleColor: Color

    var body: some View {
        let span = bottomY - topY
        let currentY = bottomY - CGFloat(progress) * span
        let needleLen: CGFloat = 13.0

        Path { path in
            let xStart = spineX - needleLen / 2
            let xEnd = spineX + needleLen / 2
            path.move(to: CGPoint(x: xStart, y: currentY))
            path.addLine(to: CGPoint(x: xEnd, y: currentY))
        }
        .stroke(needleColor, style: StrokeStyle(lineWidth: 3.0, lineCap: .round))
        .shadow(color: needleColor.opacity(0.95), radius: 4)
    }
}

// MARK: - Full-Height Arc Ticks & 13pt Semibold Numerals (Pointing Inward)

struct FullHeightArcTicks: View {
    let type: FullHeightArcGauge.GaugeType
    let isRight: Bool
    let spineX: CGFloat
    let topY: CGFloat
    let bottomY: CGFloat
    let theme: HUDTheme

    var body: some View {
        let majorSteps = 5
        let numerals: [Int] = (type == .altitude)
            ? [0, 100, 200, 300, 400]
            : [0, 25, 50, 75, 100]

        ZStack {
            // Minor Ticks (1.5pt stroke) pointing inward toward screen center
            ForEach(0..<17, id: \.self) { i in
                if i % 4 != 0 {
                    let fraction = CGFloat(i) / 16.0
                    let y = bottomY - fraction * (bottomY - topY)

                    Path { p in
                        let tickLen: CGFloat = 5.0
                        let x1 = isRight ? (spineX - tickLen) : (spineX + tickLen)
                        p.move(to: CGPoint(x: spineX, y: y))
                        p.addLine(to: CGPoint(x: x1, y: y))
                    }
                    .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                }
            }

            // Major Ticks (2.5pt stroke) with 13pt Semibold Numerals pointing inward
            ForEach(0..<majorSteps, id: \.self) { i in
                let fraction = CGFloat(i) / CGFloat(majorSteps - 1)
                let y = bottomY - fraction * (bottomY - topY)

                Path { p in
                    let tickLen: CGFloat = 8.0
                    let x1 = isRight ? (spineX - tickLen) : (spineX + tickLen)
                    p.move(to: CGPoint(x: spineX, y: y))
                    p.addLine(to: CGPoint(x: x1, y: y))
                }
                .stroke(Color.white.opacity(0.75), lineWidth: 2.5)

                let num = numerals[i]
                let numX = isRight ? (spineX - 22) : (spineX + 22)

                Text("\(num)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
                    .hudLegibilityShadow()
                    .position(x: numX, y: y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 3. Windshield Curved Heading Scale (Top Edge)

struct HeadingScale: View {
    let headingDeg: Float
    let theme: HUDTheme
    let viewWidth: CGFloat

    var body: some View {
        let currentHeading = Int(headingDeg) % 360

        VStack(spacing: 3) {
            // Dominant Heading Numeral (18pt semibold)
            Text(headingText(currentHeading))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.text)
                .hudLegibilityShadow()
                .contentTransition(.numericText())

            // Center Boresight Hairline Pointer (2.5pt width)
            Rectangle()
                .fill(theme.accent)
                .frame(width: 2.5, height: 7)

            // Hairline Scale with degree numbers every 15° (13pt semibold)
            HStack(spacing: 16) {
                ForEach(-3...3, id: \.self) { offset in
                    let markDeg = (currentHeading + offset * 15 + 360) % 360
                    let isCenter = (offset == 0)

                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(isCenter ? theme.accent : Color.white.opacity(0.50))
                            .frame(width: isCenter ? 2.5 : 1.5, height: 7)

                        Text(cardinalOrDegrees(markDeg))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(isCenter ? theme.accent : theme.textSecondary)
                            .hudLegibilityShadow()
                    }
                    .frame(width: 32)
                }
            }
        }
        .frame(maxWidth: min(390, viewWidth * 0.46))
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

// MARK: - 4. Minimalist Volvo Reticle (2.5pt Strokes, 58pt Diameter)

struct VolvoReticleView: View {
    let isLocked: Bool
    let lockProgress: Float
    let strikeText: String
    let isStriking: Bool
    let recoilKick: Bool
    let theme: HUDTheme

    var body: some View {
        ZStack {
            // Outer Smooth Target Acquiring Progress Ring (2.5pt stroke, 58pt diameter: +25%)
            Circle()
                .trim(from: 0.0, to: CGFloat(min(max(lockProgress, 0.0), 1.0)))
                .stroke(
                    isLocked ? theme.accent : theme.accent.opacity(0.50),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .frame(width: 58, height: 58)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.12), value: lockProgress)
                .scaleEffect(isLocked ? 1.06 : 1.0)
                .shadow(color: isLocked ? theme.accent.opacity(0.70) : .clear, radius: 8)

            // Inner Fine Crosshair Dot (3.5pt)
            Circle()
                .fill(isLocked ? theme.accent : Color.white.opacity(0.90))
                .frame(width: 3.5, height: 3.5)
                .hudLegibilityShadow()

            // Four Hairline Ticks (2.5pt stroke)
            ForEach([0, 90, 180, 270], id: \.self) { deg in
                Rectangle()
                    .fill(Color.white.opacity(isLocked ? 0.90 : 0.50))
                    .frame(width: 1.5, height: 6)
                    .offset(y: -19)
                    .rotationEffect(.degrees(Double(deg)))
                    .hudLegibilityShadow()
            }

            if isStriking {
                Circle()
                    .stroke(theme.accent, lineWidth: 2.0)
                    .frame(width: 72, height: 72)
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

// MARK: - 5. Zoom Reticle Glass Chip (Directly Below Reticle)

struct ZoomReticleChip: View {
    let zoomFactor: Float
    let theme: HUDTheme
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                Text(String(format: "%.0fX", zoomFactor))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(zoomFactor > 1.0 ? theme.accent : theme.text)
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 0.75))
            .shadow(color: Color.black.opacity(0.35), radius: 5)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dedicated Non-Clipping Trigger Badge

struct TriggerBadge: View {
    let text: String?
    let systemImage: String?
    let theme: HUDTheme

    var body: some View {
        HStack(spacing: 0) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textSecondary.opacity(0.90))
            } else if let text = text {
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textSecondary.opacity(0.90))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 0.75)
        )
        .fixedSize()
    }
}

// MARK: - 6. Corner Quarter Main Keys (Scan L2 & Tag R2: 17pt Semibold, Width 156)

struct CornerQuarterMainKey: View {
    enum CornerRole {
        case bottomLeading
        case bottomTrailing
    }

    let corner: CornerRole
    let label: String
    let hint: String
    let iconName: String
    let isSelected: Bool
    let theme: HUDTheme
    let action: () -> Void

    @State private var isTouchDepressed: Bool = false

    private var isPhysicalTriggerPulled: Bool {
        if corner == .bottomLeading {
            return GameInput.shared.isL2Pressed
        } else {
            return GameInput.shared.isR2Pressed
        }
    }

    private var isDepressed: Bool {
        isTouchDepressed || isPhysicalTriggerPulled
    }

    private var strokeGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(isDepressed ? 0.35 : 0.65), location: 0.0),
                .init(color: Color.white.opacity(0.18), location: 0.40),
                .init(color: Color.white.opacity(0.06), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 8) {
                if corner == .bottomTrailing {
                    TriggerBadge(text: hint, systemImage: nil, theme: theme)
                    Spacer(minLength: 4)
                }

                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)

                // Main Key Label (17pt semibold)
                Text(label)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.text)
                    .hudLegibilityShadow()
                    .lineLimit(1)
                    .fixedSize()

                if corner == .bottomLeading {
                    Spacer(minLength: 4)
                    TriggerBadge(text: hint, systemImage: nil, theme: theme)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 156, height: 48) // Guaranteed comfortable width, 48pt touch target
            .background {
                QuarterSegmentShape(corner: corner)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                QuarterSegmentShape(corner: corner)
                    .fill(Color.white.opacity(isDepressed ? 0.03 : 0.08))
            }
            .overlay {
                QuarterSegmentShape(corner: corner)
                    .stroke(strokeGradient, lineWidth: 1.0)
            }
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

// MARK: - Stacked Shelf Button (Boost L1 & Photo △: Width 136)

struct StackedShelfButton: View {
    let iconName: String
    let label: String
    let hint: String?
    let hintSystemImage: String?
    let isSelected: Bool
    let theme: HUDTheme
    let action: () -> Void

    @State private var isTouchDepressed: Bool = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)

                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.text)
                    .hudLegibilityShadow()
                    .lineLimit(1)
                    .fixedSize()

                Spacer(minLength: 4)

                TriggerBadge(text: hint, systemImage: hintSystemImage, theme: theme)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: 136, height: 38)
            .windshieldGlass(cornerRadius: 12, isDepressed: isTouchDepressed)
            .scaleEffect(isTouchDepressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isTouchDepressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isTouchDepressed = true }
                .onEnded { _ in isTouchDepressed = false }
        )
    }
}

// MARK: - Quarter-Segment Screen Corner Conforming Shape

struct QuarterSegmentShape: Shape {
    let corner: CornerQuarterMainKey.CornerRole

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cornerR: CGFloat = 28.0

        if corner == .bottomLeading {
            path.move(to: CGPoint(x: 0, y: 10))
            path.addQuadCurve(to: CGPoint(x: 10, y: 0), control: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: w - 8, y: 0))
            path.addQuadCurve(to: CGPoint(x: w, y: 8), control: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: w, y: h - 8))
            path.addQuadCurve(to: CGPoint(x: w - 8, y: h), control: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: cornerR, y: h))
            path.addQuadCurve(to: CGPoint(x: 0, y: h - cornerR), control: CGPoint(x: 0, y: h))
            path.closeSubpath()
        } else {
            path.move(to: CGPoint(x: 8, y: 0))
            path.addLine(to: CGPoint(x: w - 10, y: 0))
            path.addQuadCurve(to: CGPoint(x: w, y: 10), control: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: w, y: h - cornerR))
            path.addQuadCurve(to: CGPoint(x: w - cornerR, y: h), control: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: 8, y: h))
            path.addQuadCurve(to: CGPoint(x: 0, y: h - 8), control: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: 0, y: 8))
            path.addQuadCurve(to: CGPoint(x: 8, y: 0), control: CGPoint(x: 0, y: 0))
            path.closeSubpath()
        }

        return path
    }
}

// MARK: - Perimeter Off-Screen Target Chevrons

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
                if abs(threat.azimuthRad) > 0.40 || threat.distanceNorm > 0.65 {
                    let angle = Double(threat.azimuthRad) - .pi / 2
                    let pt = edgeIntersection(angle: angle, width: w, height: h, inset: inset)
                    let chevronColor = threat.isProjectile ? theme.warning : (threat.isTagged ? Color.green.opacity(0.6) : theme.accent)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(chevronColor)
                        .rotationEffect(.radians(angle))
                        .position(pt)
                        .shadow(color: chevronColor.opacity(0.6), radius: 5)
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

#Preview("Volvo Windshield HUD - Ice", traits: .landscapeLeft) {
    HUDView(settings: PlacementSettings())
        .background(Color(red: 0.10, green: 0.12, blue: 0.14))
}

#Preview("Volvo Windshield HUD - Bloom", traits: .landscapeLeft) {
    let gs = GameState.shared
    gs.hudThemePreset = .bloom
    return HUDView(settings: PlacementSettings())
        .background(Color(red: 0.10, green: 0.12, blue: 0.14))
}

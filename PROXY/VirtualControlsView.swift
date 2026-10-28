import SwiftUI
import simd

/// Compact on-screen thumbsticks placed safely above the HUD widgets, active only when no physical controller is attached.
struct VirtualControlsView: View {
    @Bindable var input = GameInput.shared

    @State private var leftOffset: CGSize = .zero
    @State private var rightOffset: CGSize = .zero

    private let baseRadius: CGFloat = 36
    private let thumbRadius: CGFloat = 18

    var body: some View {
        if !input.isControllerConnected || GameState.shared.showVirtualControlsOverride {
            HStack(alignment: .bottom) {
                // Left Thumbstick: Horizontal drone flight (Pitch & Roll Strafe)
                thumbstick(
                    offset: leftOffset,
                    label: "GIMBAL SLEW",
                    color: Color(red: 0.20, green: 0.85, blue: 0.95) // Cyan
                ) { gesture in
                    let translation = gesture.translation
                    let dist = sqrt(translation.width * translation.width + translation.height * translation.height)
                    let clamped = min(dist, baseRadius)
                    let angle = atan2(translation.height, translation.width)

                    let x = cos(angle) * clamped
                    let y = sin(angle) * clamped
                    leftOffset = CGSize(width: x, height: y)

                    let normX = Float(x / baseRadius)
                    let normY = Float(-y / baseRadius)
                    input.virtualMove = SIMD2<Float>(normX, normY)
                } onEnded: {
                    leftOffset = .zero
                    input.virtualMove = .zero
                }

                Spacer()

                // Re-center button between sticks when reticle is slewed
                if GameState.shared.isGimbalAimActive {
                    Button {
                        GameState.shared.resetGimbal()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "scope")
                                .font(.system(size: 8, weight: .bold))
                            Text("BORESIGHT")
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                        }
                        .foregroundStyle(Color(red: 0.20, green: 0.85, blue: 0.95))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.8), in: Capsule())
                        .overlay(Capsule().stroke(Color(red: 0.20, green: 0.85, blue: 0.95).opacity(0.4), lineWidth: 0.75))
                    }
                    .padding(.bottom, 20)
                }

                Spacer()

                // Right Thumbstick: Drone Gimbal (Yaw & Altitude)
                thumbstick(
                    offset: rightOffset,
                    label: "GIMBAL (ALT/YAW)",
                    color: Color(red: 1.00, green: 0.82, blue: 0.15) // Amber
                ) { gesture in
                    let translation = gesture.translation
                    let dist = sqrt(translation.width * translation.width + translation.height * translation.height)
                    let clamped = min(dist, baseRadius)
                    let angle = atan2(translation.height, translation.width)

                    let x = cos(angle) * clamped
                    let y = sin(angle) * clamped
                    rightOffset = CGSize(width: x, height: y)

                    let normX = Float(x / baseRadius)
                    let normY = Float(-y / baseRadius)
                    input.virtualLook = SIMD2<Float>(normX, normY)
                } onEnded: {
                    rightOffset = .zero
                    input.virtualLook = .zero
                }
            }
            .padding(.horizontal, 54)
            .padding(.bottom, 76) // Elevates cleanly above mini-map, tool bar, and score!
        }
    }

    private func thumbstick(
        offset: CGSize,
        label: String,
        color: Color,
        onChanged: @escaping (DragGesture.Value) -> Void,
        onEnded: @escaping () -> Void
    ) -> some View {
        ZStack {
            // Base ring
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: baseRadius * 2, height: baseRadius * 2)
                .overlay(
                    Circle().stroke(color.opacity(0.35), lineWidth: 1.5)
                )

            // Draggable thumb knob
            Circle()
                .fill(color.opacity(0.65))
                .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                )
                .offset(offset)

            // Label
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(color.opacity(0.8))
                .offset(y: baseRadius + 12)
        }
        .frame(width: baseRadius * 2, height: baseRadius * 2)
        .contentShape(Circle().scale(1.4))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged(onChanged)
                .onEnded { _ in onEnded() }
        )
    }
}

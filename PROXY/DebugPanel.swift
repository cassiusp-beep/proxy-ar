import SwiftUI

struct DebugPanel: View {
    @Bindable var settings: PlacementSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Calibration").font(.headline)
                Spacer()
                Button("Close") { settings.showDebug = false }
            }

            Picker("Setup", selection: $settings.setup) {
                ForEach(PhysicalSetup.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)  // four setups: a segmented control is too cramped in landscape

            // The whole offset on one line, outside the scroll view, so every screenshot has it.
            Text(String(format: "X %+.1f  Y %+.1f  Z %+.1f mm  %.1f°  %.3f×",
                        settings.x * 1000, settings.y * 1000, settings.z * 1000, settings.yawDegrees, settings.scale))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // MARK: - Critique Demo: Prestige & Mission
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PRESTIGE FILTER (CRITIQUE DEMO)")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(Color(red: 1.00, green: 0.25, blue: 0.55))

                        row("Prestige", value: "\(GameState.shared.prestigeLevel) · \(prestigeDescription(GameState.shared.prestigeLevel))") {
                            Slider(
                                value: Binding(
                                    get: { Double(GameState.shared.prestigeLevel) },
                                    set: { GameState.shared.prestigeLevel = Int($0) }
                                ),
                                in: 0...3,
                                step: 1
                            )
                        }

                        HStack(spacing: 8) {
                            Button("Reset Mission") {
                                GameState.shared.resetMission()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Refill Fuel") {
                                GameState.shared.fuel = 100
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))

                    Divider()

                    offsetSlider("X", value: $settings.x)
                    offsetSlider("Y", value: $settings.y)
                    offsetSlider("Z", value: $settings.z)

                    row("Opacity", value: String(format: "%.0f%%", settings.cityOpacity * 100)) {
                        Slider(value: $settings.cityOpacity, in: 0.15...1, step: 0.05)
                    }
                    nudgePad

                    row("Yaw", value: String(format: "%.1f°", settings.yawDegrees)) {
                        Slider(value: $settings.yawDegrees, in: -180...180, step: 0.5)
                    }
                    row("Scale", value: String(format: "%.3f×", settings.scale)) {
                        Slider(value: $settings.scale, in: 0.5...2.0, step: 0.005)
                    }

                    Toggle("City", isOn: $settings.showCity)
                    Toggle("NPCs", isOn: $settings.showNPCs)
                    Toggle("Placeholder box", isOn: $settings.showPlaceholder)
                    Toggle("Pin occlusion (city off)", isOn: $settings.pinOcclusion)
                    Toggle("Hand occlusion", isOn: $settings.handOcclusion)
                    Toggle("LiDAR occlusion", isOn: $settings.lidarOcclusion)
                    Toggle("Show mesh", isOn: $settings.showMesh)
                    // Viewpoint-diverse sampling before the lock (DIVERSE_SAMPLING); off is the
                    // old consecutive "Hold steady…" lock. Applies to the next lock.
                    Toggle("Sweep while locking", isOn: $settings.diverseSampling)
                    Button("Re-lock (keep world)") { settings.relockRequest += 1 }
                        .buttonStyle(.bordered)

                    Divider()
                    Text("Fidelity scan: lock first, then move slowly around the model, 20–40 cm away.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if settings.isScanning {
                        ProgressView(value: Double(settings.scanCoverage), total: Double(DepthScan.autoFitCoverage)) {
                            Text("Scanning: \(Int(settings.scanCoverage * 100))% of the model, \(settings.scanPoints) points")
                                .font(.caption)
                        }
                    }
                    HStack {
                        if settings.isScanning {
                            Button("Fit now") { settings.fitRequest += 1 }
                                .buttonStyle(.borderedProminent)
                                .disabled(settings.scanPoints < DepthScan.minPointsToFit)
                            Button("Cancel") { settings.isScanning = false }
                                .buttonStyle(.bordered)
                        } else {
                            Button("Start scan") { settings.isScanning = true }
                                .buttonStyle(.bordered)
                        }
                        // No "Apply fit": the fit is biased (along-ray LiDAR depth bias, yaw sd
                        // 1.8°) and made alignment worse on device. Its result stays read-only
                        // until an along-ray fit lands (PlacementSettings.applyFit, playbook §5, §1).
                    }
                    if let status = settings.fitStatus {
                        Text(status)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }

            HStack {
                Button("Print values") { settings.printValues() }
                    .buttonStyle(.borderedProminent)
                Button("Reset") { settings.reset() }
                    .buttonStyle(.bordered)
                Button("Sync") { settings.syncRequest += 1 }
                    .buttonStyle(.bordered)
                Button("Snapshot") { settings.snapshotRequest += 1 }
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    /// 0.5 mm / 0.1° steps in the model's own terms, as seen from the front.
    private var nudgePad: some View {
        let step: Float = 0.0005
        return VStack(alignment: .leading, spacing: 6) {
            Text("Nudge 0.5 mm (as seen from the front)").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                nudge("Back") { settings.nudge([-step, 0, 0]) }
                nudge("Front") { settings.nudge([step, 0, 0]) }
                nudge("Left") { settings.nudge([0, 0, step]) }
                nudge("Right") { settings.nudge([0, 0, -step]) }
            }
            HStack(spacing: 6) {
                nudge("Up") { settings.nudge([0, step, 0]) }
                nudge("Down") { settings.nudge([0, -step, 0]) }
                nudge("⟲ 0.1°") { settings.nudge(.zero, yawDegrees: 0.1) }
                nudge("⟳ 0.1°") { settings.nudge(.zero, yawDegrees: -0.1) }
            }
        }
    }

    private func nudge(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
    }

    private func offsetSlider(_ label: String, value: Binding<Float>) -> some View {
        row(label, value: String(format: "%+.1f mm", value.wrappedValue * 1000)) {
            Slider(value: value, in: -0.5...0.5, step: 0.0005)
        }
    }

    private func row(_ label: String, value: String, @ViewBuilder slider: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(label).frame(width: 44, alignment: .leading)
            slider()
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .frame(width: 80, alignment: .trailing)
        }
    }

    private func prestigeDescription(_ level: Int) -> String {
        switch level {
        case 0: return "Cartoon"
        case 1: return "Cam FLIR"
        case 2: return "Mixed"
        case 3: return "White-Hot"
        default: return "Custom"
        }
    }
}

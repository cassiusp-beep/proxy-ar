import SwiftUI

struct ContentView: View {
    @State private var settings = PlacementSettings()
    @State private var gameState = GameState.shared

    var body: some View {
        ZStack {
            ARViewContainer(settings: settings, zoomFactor: gameState.zoomFactor)
                .ignoresSafeArea()

            if settings.isLocked {
                HUDView(settings: settings)
                    .transition(.opacity)

                VStack {
                    Spacer()
                    VirtualControlsView()
                }

                if gameState.isFuelEmpty {
                    RefuelSheet()
                        .transition(.opacity)
                }
            } else {
                // Pre-lock guidance pill
                VStack {
                    HStack(alignment: .top) {
                        Text(settings.markerSeenTwice ? "Marker seen twice? Hide extra copies"
                             : settings.needsBothMarkers ? "Show both markers"
                             : settings.isSampling
                                ? (settings.diverseSampling
                                   ? "Move slowly side to side… \(settings.samplingViewpoints)/\(DIVERSE_TARGET_VIEWPOINTS)"
                                   : "Hold steady…")
                             : "Locate your Field Unit")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .onTapGesture(count: 2) {
                                settings.isLocked = true
                            }

                        Spacer()
                    }
                    .padding(12)

                    Spacer()
                }
            }

            // Debug panel toggleable via three-finger tap in any state
            if settings.showDebug {
                HStack {
                    Spacer()
                    DebugPanel(settings: settings)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                .padding(12)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: settings.showDebug)
        .animation(.easeInOut(duration: 0.3), value: settings.isLocked)
    }
}

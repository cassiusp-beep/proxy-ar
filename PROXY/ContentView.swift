import SwiftUI

struct ContentView: View {
    @State private var settings = PlacementSettings()

    var body: some View {
        ZStack {
            ARViewContainer(settings: settings)
                .ignoresSafeArea()

            // Landscape: the phone sits sideways in a Backbone-style controller.
            HStack(alignment: .top) {
                Text(settings.isLocked ? "LOCKED"
                     : settings.markerSeenTwice ? "Marker seen twice? Hide extra copies"
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

                Spacer()

                if settings.showDebug {
                    DebugPanel(settings: settings)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(12)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: settings.showDebug)
        }
    }
}

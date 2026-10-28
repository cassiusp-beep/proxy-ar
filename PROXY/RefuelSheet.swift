import SwiftUI

/// Free-to-play satirical meta refuel prompt, echoing GOLIATH's microtransaction structure.
struct RefuelSheet: View {
    @Bindable var gameState = GameState.shared

    @State private var isWatchingAd: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header Icon
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 56, height: 56)
                    Image(systemName: "battery.0")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.red)
                }

                VStack(spacing: 4) {
                    Text("DRONE POWER DEPLETED")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Field Unit power reserves exhausted. Authorize immediate tactical resupply to continue operations.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }

                if isWatchingAd {
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text("STREAMING RECRUITMENT BROADCAST…")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.20, green: 0.65, blue: 1.00))
                    }
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 10) {
                        // Instant Refuel for Gems
                        Button {
                            if gameState.gems >= 20 {
                                gameState.gems -= 20
                            }
                            gameState.fuel = 100
                            gameState.droneShield = 100
                            gameState.radioMessage = "Operator: Fast recharge complete. Drone cleared for flight."
                        } label: {
                            HStack {
                                Text("💎")
                                Text("INSTANT REFUEL (20 GEMS)")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(red: 1.00, green: 0.84, blue: 0.10), in: Capsule()) // Sunshine yellow
                        }

                        // Watch Fake Ad
                        Button {
                            isWatchingAd = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                isWatchingAd = false
                                gameState.fuel = 100
                                gameState.droneShield = 100
                                gameState.radioMessage = "Operator: Field sponsorship acknowledged. Battery 100%."
                            }
                        } label: {
                            HStack {
                                Image(systemName: "play.rectangle.fill")
                                Text("WATCH SPONSOR INTEL (FREE)")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.15), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(24)
            .frame(width: 380)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.5), radius: 20)
        }
    }
}

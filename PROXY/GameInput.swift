import Foundation
import GameController
import Observation
import simd

/// Unified input manager for both hardware gamepads (Backbone One / MFi) and on-screen virtual sticks.
@Observable
final class GameInput {
    static let shared = GameInput()

    /// Horizontal movement vector: x is strafe (-1 left, +1 right), y is forward/backward (+1 forward, -1 back).
    var moveVector: SIMD2<Float> = .zero

    /// Yaw rotation input (-1 left, +1 right).
    var yawInput: Float = 0

    /// Altitude adjustment (-1 descend, +1 ascend).
    var altitudeInput: Float = 0

    /// Tag button pressed (A on controller or on-screen button).
    var tagTriggered: Bool = false

    /// Tool cycle request (-1 previous, +1 next).
    var toolCycleDelta: Int = 0

    /// True when a physical game controller is connected.
    var isControllerConnected: Bool = false

    /// On-screen virtual joystick inputs (used when isControllerConnected is false).
    var virtualMove: SIMD2<Float> = .zero {
        didSet { updateActiveInputs() }
    }
    var virtualLook: SIMD2<Float> = .zero {
        didSet { updateActiveInputs() }
    }

    private var activeController: GCController?

    private init() {
        setupControllerObservers()
        checkForConnectedControllers()
    }

    private func setupControllerObservers() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            print("[PROXY] Game controller connected: \(controller.vendorName ?? "Unknown")")
            self?.attachController(controller)
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            print("[PROXY] Game controller disconnected: \(controller.vendorName ?? "Unknown")")
            if self?.activeController == controller {
                self?.activeController = nil
                self?.checkForConnectedControllers()
            }
        }
    }

    private func checkForConnectedControllers() {
        if let controller = GCController.controllers().first {
            attachController(controller)
        } else {
            isControllerConnected = false
            activeController = nil
            updateActiveInputs()
        }
    }

    private func attachController(_ controller: GCController) {
        activeController = controller
        isControllerConnected = true

        guard let gamepad = controller.extendedGamepad else { return }

        // Left Stick: Horizontal drone flight (Pitch forward/back, Roll strafe left/right)
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            guard let self, self.isControllerConnected else { return }
            if GameState.shared.isConnectionLost {
                self.moveVector = .zero
                return
            }
            self.moveVector = SIMD2<Float>(x, y)
        }

        // Right Stick: Gimbal Yaw (pan left/right) and Altitude (climb up / dive down)
        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            guard let self, self.isControllerConnected else { return }
            if GameState.shared.isConnectionLost {
                self.yawInput = 0
                self.altitudeInput = 0
                return
            }
            self.yawInput = x
            self.altitudeInput = y
        }

        // Left Thumbstick Click (L3): Re-center reticle back to center boresight
        gamepad.leftThumbstickButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                guard !GameState.shared.isConnectionLost else { return }
                SessionLogger.shared.log("Controller L3 (Left Stick Click): Re-center targeting reticle", category: "INPUT")
                Task { @MainActor in
                    GameState.shared.resetGimbal()
                }
            }
        }

        // Right Thumbstick Click (R3): Cycle Zoom (1X -> 2X -> 4X)
        gamepad.rightThumbstickButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                guard !GameState.shared.isConnectionLost else { return }
                SessionLogger.shared.log("Controller R3 (Right Stick Click): cycle zoom", category: "INPUT")
                Task { @MainActor in
                    GameState.shared.cycleZoom()
                }
            }
        }

        // Right Trigger [R2]: Cycle Zoom (1X -> 2X -> 4X)
        gamepad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                guard !GameState.shared.isConnectionLost else { return }
                SessionLogger.shared.log("Controller R2 / Right Trigger pressed: cycle zoom", category: "INPUT")
                Task { @MainActor in
                    GameState.shared.cycleZoom()
                }
            }
        }

        // L2 Trigger [L2]: Trigger Scan tool
        gamepad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                guard !GameState.shared.isConnectionLost else { return }
                SessionLogger.shared.log("Controller L2 / Left Trigger pressed: select scan tool", category: "INPUT")
                Task { @MainActor in
                    GameState.shared.selectedToolIndex = GameState.ToolSlot.scan.rawValue
                }
            }
        }

        // Cross [✕] and Square [□] buttons: Attack / Tag action
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                guard !GameState.shared.isConnectionLost else { return }
                SessionLogger.shared.log("Controller ✕ (Button A) pressed: TAG/STRIKE triggered", category: "INPUT")
                self?.tagTriggered = true
                Task { @MainActor in
                    GameState.shared.selectedToolIndex = GameState.ToolSlot.tag.rawValue
                }
            }
        }

        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                guard !GameState.shared.isConnectionLost else { return }
                SessionLogger.shared.log("Controller □ (Button X) pressed: TAG/STRIKE triggered", category: "INPUT")
                self?.tagTriggered = true
                Task { @MainActor in
                    GameState.shared.selectedToolIndex = GameState.ToolSlot.tag.rawValue
                }
            }
        }

        // Circle [○] button: Cycle zoom
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                guard !GameState.shared.isConnectionLost else { return }
                SessionLogger.shared.log("Controller ○ (Button B) pressed: cycle zoom", category: "INPUT")
                Task { @MainActor in
                    GameState.shared.cycleZoom()
                }
            }
        }

        // Triangle [△] button: Reload ammunition (or select scan if full)
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                SessionLogger.shared.log("Controller △ (Button Y) pressed: tactical reload / scan", category: "INPUT")
                Task { @MainActor in
                    if GameState.shared.ammo < GameState.shared.maxAmmo {
                        GameState.shared.startReload()
                    } else {
                        GameState.shared.selectedToolIndex = GameState.ToolSlot.scan.rawValue
                    }
                }
            }
        }

        // Shoulder buttons [L1 / R1]: cycle tools
        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                SessionLogger.shared.log("Controller L1 pressed: prev tool", category: "INPUT")
                Task { @MainActor in
                    GameState.shared.cycleTool(delta: -1)
                }
            }
        }

        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                SessionLogger.shared.log("Controller R1 pressed: next tool", category: "INPUT")
                Task { @MainActor in
                    GameState.shared.cycleTool(delta: 1)
                }
            }
        }

        // D-Pad Up / Down: Switch Prestige theme (0: Cartoon, 1: Ants/Pest, 2: Recon, 3: FLIR Thermal)
        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                Task { @MainActor in
                    let next = min(3, GameState.shared.prestigeLevel + 1)
                    GameState.shared.prestigeLevel = next
                    SessionLogger.shared.log("Controller D-Pad UP: Prestige advanced to \(next)", category: "INPUT")
                }
            }
        }

        gamepad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                Task { @MainActor in
                    let prev = max(0, GameState.shared.prestigeLevel - 1)
                    GameState.shared.prestigeLevel = prev
                    SessionLogger.shared.log("Controller D-Pad DOWN: Prestige decreased to \(prev)", category: "INPUT")
                }
            }
        }

        gamepad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                Task { @MainActor in
                    GameState.shared.resetGimbal()
                    SessionLogger.shared.log("Controller D-Pad LEFT: Re-center targeting reticle", category: "INPUT")
                }
            }
        }
    }

    private func updateActiveInputs() {
        guard !isControllerConnected else { return }
        moveVector = virtualMove
        yawInput = virtualLook.x
        altitudeInput = virtualLook.y
    }
}

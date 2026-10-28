import Foundation
import AVFoundation

/// FlashlightController provides ultra-low latency hardware torch control
/// to produce tactical strobe / muzzle flashes when pulling the trigger in PROXY.
final class FlashlightController: @unchecked Sendable {
    static let shared = FlashlightController()

    private let queue = DispatchQueue(label: "com.cassiuspalacio.proxy.flashlight", qos: .userInteractive)
    private var turnOffWorkItem: DispatchWorkItem?

    private init() {}

    private var backCameraDevice: AVCaptureDevice? {
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), device.hasTorch {
            return device
        }
        if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
            return device
        }
        return nil
    }

    /// Strobes the physical rear LED flash for a crisp, punchy weapon muzzle flash (e.g. 70ms).
    func flash(duration: TimeInterval = 0.070) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let device = self.backCameraDevice, device.isTorchAvailable else { return }

            // Cancel any pending turn-off to maintain seamless illumination during rapid semi-auto fire
            self.turnOffWorkItem?.cancel()

            do {
                try device.lockForConfiguration()
                if device.isTorchModeSupported(.on) {
                    try device.setTorchModeOn(level: 1.0)
                }
                device.unlockForConfiguration()
            } catch {
                return
            }

            // Schedule immediate turn-off after duration
            let workItem = DispatchWorkItem { [weak self] in
                guard self != nil else { return }
                guard let device = self?.backCameraDevice else { return }
                do {
                    try device.lockForConfiguration()
                    device.torchMode = .off
                    device.unlockForConfiguration()
                } catch {
                    // Handled safely
                }
            }

            self.turnOffWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + duration, execute: workItem)
        }
    }

    /// Immediately turns off the torch (used during pause, connection loss, or backgrounding).
    func turnOff() {
        queue.async { [weak self] in
            self?.turnOffWorkItem?.cancel()
            guard let device = self?.backCameraDevice else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
            } catch {
                // Handled safely
            }
        }
    }
}

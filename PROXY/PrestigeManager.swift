import RealityKit
import UIKit

/// Manages the critical Prestige filter transition: swapping candy cartoon materials
/// into cold military FLIR thermal signatures (white-hot people, dark grayscale terrain).
@MainActor
final class PrestigeManager {
    static let shared = PrestigeManager()

    private var originalCityMaterials: [ObjectIdentifier: [any RealityKit.Material]] = [:]
    private var originalNPCMaterials: [ObjectIdentifier: [any RealityKit.Material]] = [:]
    private var cachedHaloEntities: [ObjectIdentifier: Entity] = [:]
    private var isCached = false
    private var currentAppliedLevel: Int? = nil

    // Thermal Materials (FLIR White-Hot Palette)
    private let whiteHotMaterial = UnlitMaterial(color: UIColor.white)
    private let terrainThermalLow = UnlitMaterial(color: UIColor(white: 0.12, alpha: 1.0))
    private let terrainThermalMid = UnlitMaterial(color: UIColor(white: 0.22, alpha: 1.0))
    private let terrainThermalHigh = UnlitMaterial(color: UIColor(white: 0.32, alpha: 1.0))
    private let buildingThermal = UnlitMaterial(color: UIColor(white: 0.40, alpha: 1.0))
    private let roadThermal = UnlitMaterial(color: UIColor(white: 0.18, alpha: 1.0))

    private init() {}

    /// Caches initial cartoon materials so they can be restored cleanly when sliding back to Level 0.
    func cacheOriginals(city: Entity?, npcs: Entity?) {
        guard !isCached else { return }
        if let city { cacheMaterials(from: city, into: &originalCityMaterials) }
        if let npcs { cacheMaterials(from: npcs, into: &originalNPCMaterials) }
        isCached = true
        print("[PROXY] PrestigeManager: Cached \(originalCityMaterials.count) city and \(originalNPCMaterials.count) NPC material slots.")
    }

    /// Applies the prestige level (0: Cartoon, 1: Pip/Subtle, 2: Mixed Thermal, 3: Full White-Hot Reality).
    func apply(level: Int, city: Entity?, npcs: Entity?) {
        if !isCached {
            cacheOriginals(city: city, npcs: npcs)
        }

        // 60FPS Optimization: Prevent redundant recursive scene-graph material mutations
        guard currentAppliedLevel != level else { return }
        currentAppliedLevel = level

        switch level {
        case 0:
            // Prestige 0: Cute Arcade Cartoon
            if let city { restoreMaterials(to: city, from: originalCityMaterials) }
            if let npcs {
                setNPCType(in: npcs, showAnts: false)
                restoreMaterials(to: npcs, from: originalNPCMaterials)
                setThermalHalos(in: npcs, enabled: false)
            }

        case 1:
            // Prestige 1: Sector Pest Control (People become swarming ants)
            if let city { restoreMaterials(to: city, from: originalCityMaterials) }
            if let npcs {
                setNPCType(in: npcs, showAnts: true)
                restoreMaterials(to: npcs, from: originalNPCMaterials)
                setThermalHalos(in: npcs, enabled: false)
            }

        case 2:
            // Prestige 2: Tactical Recon
            if let city { applyThermalToCity(city, fullThermal: false) }
            if let npcs {
                setNPCType(in: npcs, showAnts: false)
                restoreMaterials(to: npcs, from: originalNPCMaterials)
                setThermalHalos(in: npcs, enabled: false)
            }

        case 3:
            // Prestige 3: Cold FLIR Infrared Thermal (All targets are uniform white-hot heat signatures)
            if let city { applyThermalToCity(city, fullThermal: true) }
            if let npcs {
                setNPCType(in: npcs, showAnts: false)
                applyWhiteHotToNPCs(npcs)
                setThermalHalos(in: npcs, enabled: true)
            }

        default:
            break
        }
    }

    private func setNPCType(in npcsRoot: Entity, showAnts: Bool) {
        for npc in npcsRoot.children where npc.components.has(NPCComponent.self) {
            npc.findEntity(named: "body")?.isEnabled = !showAnts
            npc.findEntity(named: "ant")?.isEnabled = showAnts
        }
    }

    // MARK: - Private Helpers

    private func cacheMaterials(from entity: Entity, into storage: inout [ObjectIdentifier: [any RealityKit.Material]]) {
        if let model = entity.components[ModelComponent.self] {
            storage[entity.id] = model.materials
        }
        for child in entity.children {
            cacheMaterials(from: child, into: &storage)
        }
    }

    private func restoreMaterials(to entity: Entity, from storage: [ObjectIdentifier: [any RealityKit.Material]]) {
        if var model = entity.components[ModelComponent.self], let original = storage[entity.id] {
            model.materials = original
            entity.components.set(model)
        }
        for child in entity.children {
            restoreMaterials(to: child, from: storage)
        }
    }

    private func applyThermalToCity(_ entity: Entity, fullThermal: Bool) {
        if var model = entity.components[ModelComponent.self] {
            let name = entity.name.lowercased()
            let thermalMat: any RealityKit.Material
            if name.contains("high") || name.contains("peak") {
                thermalMat = terrainThermalHigh
            } else if name.contains("mid") {
                thermalMat = terrainThermalMid
            } else if name.contains("low") {
                thermalMat = terrainThermalLow
            } else if name.contains("roof") || name.contains("wall") || name.contains("house") {
                thermalMat = buildingThermal
            } else {
                thermalMat = roadThermal
            }
            model.materials = Array(repeating: thermalMat, count: max(model.materials.count, 1))
            entity.components.set(model)
        }
        for child in entity.children {
            applyThermalToCity(child, fullThermal: fullThermal)
        }
    }

    private func applyWhiteHotToNPCs(_ root: Entity) {
        if var model = root.components[ModelComponent.self], root.name != "target_ring" {
            model.materials = Array(repeating: whiteHotMaterial, count: max(model.materials.count, 1))
            root.components.set(model)
        }
        for child in root.children {
            applyWhiteHotToNPCs(child)
        }
    }

    private func setThermalHalos(in npcsRoot: Entity, enabled: Bool) {
        for npc in npcsRoot.children where npc.components.has(NPCComponent.self) {
            if let existingHalo = npc.findEntity(named: "thermal_halo") {
                existingHalo.isEnabled = enabled
            } else if enabled {
                var haloMat = UnlitMaterial(color: UIColor(white: 1.0, alpha: 0.45))
                haloMat.blending = .transparent(opacity: 0.45)
                let halo = ModelEntity(
                    mesh: .generateCylinder(height: 0.0001, radius: 0.004),
                    materials: [haloMat]
                )
                halo.name = "thermal_halo"
                halo.position = [0, 0.0002, 0]
                npc.addChild(halo)
            }
        }
    }
}

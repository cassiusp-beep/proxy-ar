import RealityKit
import UIKit

/// Loads the AR content. Every entity's origin is the pin origin (the pin model's lower-left
/// corner); content extends +X (right) and −Z (away). Models are exported by tools/export_models.py.
enum ContentLoader {
    /// Flip to true for flat, fully unlit cartoon colors; false keeps light shading for depth.
    static let useUnlit = false

    /// The occluder sits this far below the real pins, so the city surface (which touches
    /// the pin tops) always wins the depth test instead of flickering against it.
    static let occluderDrop: Float = 0.0015

    /// Townspeople walking the paths (see NPCSystem).
    static let npcCount = 18

    struct Content {
        let city: Entity?
        let occluder: Entity?
        let placeholder: Entity
        let npcs: Entity?
    }

    @MainActor
    static func loadContent() async -> Content {
        let npcs = TerrainData.shared.map { NPCSystem.spawn(count: npcCount, terrain: $0) }
        return Content(city: await loadCity(), occluder: await loadOccluder(), placeholder: makePlaceholder(), npcs: npcs)
    }

    @MainActor
    private static func loadCity() async -> Entity? {
        do {
            let city = try await Entity(named: "city")
            cartoonize(city)
            let bounds = city.visualBounds(relativeTo: nil)
            print("[PROXY] city.usdz loaded. Bounds min \(bounds.min), max \(bounds.max) (expect x 0…\(PIN_FIELD_SIZE.x), z −\(PIN_FIELD_SIZE.y)…0).")
            return city
        } catch {
            print("[PROXY] city.usdz not found (\(error.localizedDescription)); showing placeholder.")
            return nil
        }
    }

    /// The physical pins as invisible geometry: hides virtual content that is behind a real pin.
    @MainActor
    private static func loadOccluder() async -> Entity? {
        do {
            let pins = try await Entity(named: "pins_occluder")
            apply(OcclusionMaterial(), to: pins)
            pins.position.y = -occluderDrop
            return pins
        } catch {
            print("[PROXY] pins_occluder.usdz not found (\(error.localizedDescription)); no pin occlusion.")
            return nil
        }
    }

    // MARK: Placeholder

    @MainActor
    static func makePlaceholder() -> Entity {
        let root = Entity()

        var slabMaterial = UnlitMaterial(color: UIColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 1))
        slabMaterial.blending = .transparent(opacity: 0.4)
        let slab = ModelEntity(mesh: .generateBox(width: PIN_FIELD_SIZE.x, height: 0.002, depth: PIN_FIELD_SIZE.y),
                               materials: [slabMaterial])
        slab.position = [PIN_FIELD_SIZE.x / 2, 0.001, -PIN_FIELD_SIZE.y / 2]
        root.addChild(slab)

        // Red sphere on the origin corner, plus RGB = XYZ axis bars to read orientation.
        let origin = ModelEntity(mesh: .generateSphere(radius: 0.004),
                                 materials: [UnlitMaterial(color: .systemRed)])
        root.addChild(origin)

        let length: Float = 0.04, thickness: Float = 0.002
        let axes: [(SIMD3<Float>, SIMD3<Float>, UIColor)] = [
            ([length, thickness, thickness], [length / 2, 0, 0], .red),
            ([thickness, length, thickness], [0, length / 2, 0], .green),
            ([thickness, thickness, length], [0, 0, length / 2], .blue),
        ]
        for (size, position, color) in axes {
            let bar = ModelEntity(mesh: .generateBox(size: size), materials: [UnlitMaterial(color: color)])
            bar.position = position
            root.addChild(bar)
        }
        return root
    }

    // MARK: Cartoon restyle

    static let palette: [UIColor] = [
        UIColor(red: 1.00, green: 0.25, blue: 0.55, alpha: 1), // hot pink
        UIColor(red: 1.00, green: 0.84, blue: 0.10, alpha: 1), // sunshine yellow
        UIColor(red: 0.20, green: 0.65, blue: 1.00, alpha: 1), // sky blue
        UIColor(red: 0.45, green: 0.90, blue: 0.20, alpha: 1), // lime
        UIColor(red: 1.00, green: 0.55, blue: 0.10, alpha: 1), // orange
        UIColor(red: 0.60, green: 0.35, blue: 1.00, alpha: 1), // purple
        UIColor(red: 0.10, green: 0.85, blue: 0.80, alpha: 1), // turquoise
    ]

    /// Name keywords that pin a color, checked against entity names (lowercased).
    /// The terrain_* bands and figures come from tools/export_models.py.
    static let keywordColors: [(keywords: [String], color: UIColor)] = [
        (["terrain_low"], palette[3]),
        (["terrain_mid"], palette[1]),
        (["terrain_high"], palette[4]),
        (["terrain_peak"], palette[0]),
        (["figure"], palette[5]),
        (["road", "street", "asphalt", "highway"], UIColor(red: 0.42, green: 0.38, blue: 0.62, alpha: 1)),
        (["tree", "grass", "park", "lawn", "leaf", "foliage"], palette[3]),
        (["water", "river", "lake", "sea", "pool"], palette[2]),
        (["roof"], UIColor(red: 1.00, green: 0.35, blue: 0.20, alpha: 1)),
        (["window", "glass"], palette[6]),
    ]

    static func cartoonize(_ entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            let name = entity.name.lowercased()
            // Meshes exported without materials still need one slot to restyle.
            model.materials = (0..<max(model.materials.count, 1)).map { index in
                material(for: color(name: name, index: index))
            }
            entity.components.set(model)
        }
        for child in entity.children {
            cartoonize(child)
        }
    }

    private static func apply(_ material: any RealityKit.Material, to entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            model.materials = Array(repeating: material, count: max(model.materials.count, 1))
            entity.components.set(model)
        }
        for child in entity.children {
            apply(material, to: child)
        }
    }

    private static func color(name: String, index: Int) -> UIColor {
        if let match = keywordColors.first(where: { entry in entry.keywords.contains { name.contains($0) } }) {
            return match.color
        }
        return palette[stableHash("\(name)#\(index)") % palette.count]
    }

    static func material(for color: UIColor) -> any RealityKit.Material {
        if useUnlit {
            return UnlitMaterial(color: color)
        }
        return SimpleMaterial(color: color, roughness: 0.85, isMetallic: false)
    }

    /// FNV-1a; Swift's Hasher is seeded per launch, so it would reshuffle colors every run.
    private static func stableHash(_ string: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % UInt64(Int.max))
    }
}

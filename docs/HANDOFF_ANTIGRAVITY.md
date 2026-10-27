# PROXY handoff for Gemini / Antigravity (2026-10-27, evening)

This is for the next coding agent: Gemini in Antigravity, working with Cassius (the designer, who also tests on the phone). It explains the project, what already works and must not be touched, and what to build next: the drone, the HUD, missions and the "fun" layer.

**Read in this order:**
1. This file.
2. [PROXY_AR_BRIEF.md](../PROXY_AR_BRIEF.md): the full design brief (premise, HUD, Prestige filter, demo script). Where its numbers conflict with this file, this file wins. The brief's 304.8 mm / 40×40 pin numbers are outdated (see §3).
3. [DECISIONS.md](../DECISIONS.md) 001–022: why things are the way they are. Don't reopen a settled decision without asking Cassius.
4. [docs/HANDOFF.md](HANDOFF.md) and [docs/AR_ALIGNMENT_PLAYBOOK.md](AR_ALIGNMENT_PLAYBOOK.md): only if you have to touch alignment, which you should avoid (§4).

`CLAUDE.md` and `.claude/agents/*.md` were written for Claude Code. Their rules still apply (build command, small files, ask before calibration changes). The agent roles are a workflow description: you can follow the same loop yourself (explore → Cassius approves → build → review → document).

---

## 1. The project in one paragraph

**PROXY** is a speculative 2030 U.S. Air Force recruitment game, a critical design project for DESINV 210 at UC Berkeley. Players fly a cute drone over a cartoon world and "tag" targets for points, and some missions are secretly live. The physical installation is a gray 3D-printed **pin terrain** (the "Field Unit"). Through the phone, an AR overlay turns it into a bright, candy-colored cartoon city. **The gray physical terrain tells the truth; the cartoon screen doesn't.** The better you play, the thinner the cartoon gets: the **Prestige filter** drains the cartoon into a white-hot thermal view.

**Deadline:** the final critique is **Wednesday 2026-10-28, 9:10 am**: a 3-minute in-character pitch, with the app running on Cassius's iPhone. The app must start fast, survive tracking loss and **never crash mid-demo**. Stability beats features.

---

## 2. Environment and device loop

- **Stack:** native iOS, SwiftUI + RealityKit + ARKit. Deployment target iOS 26. The only device is an **iPhone 17 Pro Max**: iPhone-only, **landscape**, held in a Backbone One USB-C (2nd gen) controller.
- **Mac:** `xcode-select` points at CommandLineTools, so **always set `DEVELOPER_DIR`**.
- **Project:** `PROXY.xcodeproj` is hand-written and uses a **synchronized folder**. Any file you add to `PROXY/` joins the target automatically. Don't edit `project.pbxproj` to add files. `Info.plist` is excluded from resources; most plist keys live in build settings as `INFOPLIST_KEY_*`.
- **Simulator:** it can't run ARKit world tracking. Compile-check with the generic build; test on the phone.

**Compile check** (do this after every change):
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project PROXY.xcodeproj -scheme PROXY -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

**Signed device build, install, and launch with console** (wireless works: Mac and phone on Cassius's Personal Hotspot). Values: UDID `00008150-000518D10130C01C`, free team `Q48J597563`, bundle `com.cassiuspalacio.proxy`. `DD` is any derived-data folder outside the project.
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project PROXY.xcodeproj -scheme PROXY -destination 'generic/platform=iOS' \
  -derivedDataPath "$DD" -allowProvisioningUpdates DEVELOPMENT_TEAM=Q48J597563 build
xcrun devicectl device install app --device 00008150-000518D10130C01C \
  "$DD/Build/Products/Debug-iphoneos/PROXY.app"
nohup xcrun devicectl device process launch --device 00008150-000518D10130C01C \
  --terminate-existing --console com.cassiuspalacio.proxy > proxy_console.log 2>&1 &
```

**Pull in-app snapshots** (the app saves one 2 s after every lock, plus a manual **Snapshot** button):
```bash
xcrun devicectl device copy from --device 00008150-000518D10130C01C --domain-type appDataContainer \
  --domain-identifier com.cassiuspalacio.proxy --source Documents --destination ./snaps
```

**Gotchas:**
- `Locked` / `RequestDenied` on launch means the phone is locked. Ask Cassius to unlock it, and suggest setting Auto-Lock to Never.
- `App terminated due to signal 9` means the app was swiped away. After that, nothing more is logged.
- A launch from the Home Screen gives no console. Relaunch from the Mac when you need logs.
- **Never install while Cassius is mid-test.** Installing kills the running app. Ask first.
- **Free-account builds expire after 7 days. Rebuild and reinstall the morning of the critique.**
- App logs are prefixed `[PROXY]`, so grep for that.

---

## 3. Coordinates, sizes and the scene graph (read before placing anything)

**Content frame:** everything game-related lives in **meters from the pin origin**.
- Mapping from Rhino mm (Z-up) to content coordinates: `(x, y, z) = (X − 5, Z − 7.58, −Y) / 1000`.
- Content extends **+x (right) and −z (away from the player)**. **y is up.**
- **The front, where the player stands, is Rhino +X.** In content terms, the player looks roughly along −z from the +z side, and the markers sit in front of the terrain (DECISIONS 008).

**Sizes:**

| Thing | Size |
|---|---|
| Pin field (the playable footprint) | **0.158574 m (x) × 0.146354 m (z)**, `PIN_FIELD_SIZE` in `PlacementSettings.swift` (not the brief's 0.3048) |
| Terrain height | up to about 0.134 m above the origin (a mountain with pueblo settlements) |
| NPC figures | 5.5 mm tall |
| Drone (brief) | about 2.5 cm. Consider 1.5–2 cm, since the field is only 15 cm wide. Ask Cassius |

**Scene graph** (in `ARViewContainer.swift`, class `Coordinator`):
```
AnchorEntity (world anchor, created by the lock in MarkerLock.swift)
└── offsetEntity            ← carries the marker→origin offset, yaw and scale. Don't change its transform.
    ├── city                (city.usdz, cartoonized at load time by ContentLoader)
    ├── occluder            (pins_occluder.usdz, active only when the city is hidden)
    ├── placeholder         (debug box)
    └── npcs                (root "npcs": 18 NPC entities driven by NPCSystem)
```
- **Add all new game content (drone, target rings, effects) as children of `offsetEntity`,** in content-frame coordinates. It then moves with the lock automatically.
- Content loads asynchronously in `Coordinator.init`; `applyVisibility()` toggles things by settings. Follow that pattern: build your entities in a loader, attach them once, and toggle them with `isEnabled`.
- Before a lock, `offsetEntity` isn't attached to the world. Gate gameplay on `settings.isLocked`.

**Terrain queries:** `TerrainData.shared` (in `TerrainData.swift`).
- `height(x:z:)` / `height(at: SIMD2(x, z))`: terrain height from a 318×293 heightfield at 0.5 mm cells. Use it for the drone's minimum altitude and blob-shadow placement. It's cheaper and more reliable than raycasting against the mesh.
- `paths`: 5 named walking paths (FRONT-LOW, LOW-MID, LOW-MID2, MID-HIGH, MID2-HIGH).
- `sites`: 4 settlements:

| Site | Center (x, z) | Radius |
|---|---|---|
| LOW | (0.112, −0.062) | 0.017 |
| MID | (0.051, −0.040) | 0.015 |
| MID2 | (0.060, −0.120) | 0.013 |
| HIGH | (0.029, −0.072) | 0.012 |

  These are natural mission sectors.
- `nodePoint(name)`.
- Only 2 of the 5 paths are exact. The others are approximate until Cassius runs `diorama.py` in paths mode (README).

**Shared state:** `PlacementSettings` (`@Observable`, created in `ContentView`) is passed to `ARViewContainer` and `DebugPanel`.
- UI triggers actions by bumping counters (`syncRequest += 1`), which `updateUIView` forwards to the coordinator.
- **For the game, create a separate `@Observable GameState`** rather than growing `PlacementSettings`, which is about calibration.

**Look:**
- `ContentLoader.palette`: hot pink, sunshine yellow, sky blue, lime, orange, purple, turquoise. `ContentLoader.material(for:)` makes a lightly shaded material. Reuse both so new things match.
- The city's opacity is set with `OpacityComponent`.

**ECS precedent:** `NPC.swift` / `NPCSystem.swift` show the pattern:
- a `Component` struct plus a `System` with an `EntityQuery`
- registered in `PROXYApp.init`
- `dt` clamped to 0.1

Use the same pattern for the drone and targets.

---

## 4. Do not touch (without asking Cassius)

Alignment took 7 device sessions to get right. Session 7 passed the repeatability target for the first time.

- **Lock and calibration code:** `MarkerLock.swift`, `MarkerSampler.swift`, `ViewpointSet.swift`, the session config in `ARViewContainer.runSession`, the lock and `didUpdate anchors` paths.
- **Calibration constants** at the top of `PlacementSettings.swift` (`*_MARKER_TO_ORIGIN`, `*_YAW_DEGREES`, `*_SCALE`, spacings, `PIN_FIELD_SIZE`, `DIVERSE_SAMPLING = false`). Changing any saved constant needs Cassius's explicit OK.
- **`offsetEntity.transform`:** it is the calibration. Never put game transforms on it.
- **Generated files:** `city.usdz`, `pins_occluder.usdz`, `terrain.json`, `terrain_height.bin`. They come from `../Diorama` via `tools/export_models.py`. Never hand-edit them.
- **Outside this folder:** `../Diorama/` and especially `Actuator Release.3dm`, which is READ ONLY. Ask before editing anything outside `AR Experience/`.
- **Print instructions and marker placement:** ask before changing them.
- **The fidelity scan / fit** (`DepthScan`, `FidelityFit`): diagnostic only, and the "apply fit" option was deliberately removed. Leave it.
- **The three-finger tap** opens the debug panel. Keep it. Add game debug controls to `DebugPanel`.

---

## 5. Current state (what works today)

**Works on device:**
- Marker lock, cartoon city on the gray pins, 18 NPCs walking paths and wandering settlements.
- Hand occlusion (person segmentation), LiDAR scene reconstruction.
- Opacity slider, Sync and Re-lock, in-app snapshots.

Setups are in the debug-panel menu:
- **Pin block:** two 50 mm markers in front of the bare pin print. Tested in sessions 5–7, and it looks right to about 1–2 mm.
- **Field Unit 100:** the single 100 mm DockMarker in the Field Unit's sync-dock pocket. **This is the demo setup and it's untested.** Cassius still has to print `DockMarker_print_100mm.pdf` at 100% on stiff card and measure the card's thickness. `DOCK_MARKER_TO_ORIGIN` assumes 1.2 mm; a different thickness changes y by the difference, and that needs Cassius's OK.
- **Field Unit 50** and **Diorama:** also in the menu, not used for the demo.

**Demo lock procedure** (DECISIONS 021, backed by session-7 data):
1. Sync once right before presenting: phone 20–25 cm from the marker, looking down 45–60°, holding still until LOCKED.
2. No scans and no walking around after the lock.
3. If it looks off, Sync again (at most 2 tries).

"Sweep while locking" is **off** (DECISIONS 019: it tested worse).

**Already confirmed in code** (HANDOFF §2 lists them as unconfirmed): the NaN-sample guard, the Field Unit plane-offset logging, `plane_dy_mm` in RELOCK, and the right-only refusal escape.

**Status pill** (`ContentView`): "Locate your Field Unit" → "Hold steady…" → "LOCKED", plus warnings. The game HUD should replace it after the lock, and must keep showing it before the lock.

---

## 6. Game design decisions already made with Cassius

These are settled; don't re-ask.

- **NPC role: "Some are targets".** Most NPCs are ambient townspeople. Each mission marks a few as targets to tag. In the Prestige thermal view, **all** NPCs look like the same white-hot figures. That sameness is the critique's point, so don't make targets visually different under thermal.
- **Loop scope: "Core + visible meta".**
  - **Playable:** mission waves, tagging, fuel drain plus the refuel screen, score, and the Prestige filter.
  - **Shown but shallow:** gems, credits, crate opening, daily reward, a live-event banner, tool upgrades. Static or fake numbers are fine. All currencies are fake; there are no real purchases.
- **GOLIATH is the reference** (SHD Games, App Store): borrow its *structure* (drone-camera HUD, corner brackets, margin readouts, tool selector, radio mission text, free-to-play meta) and flip its *style* to rounded and candy-colored. **No violence:** "tag" instead of ordnance, with cheerful effects, no blood, no explosions on people.
- **Controller:** the Backbone One is an MFi controller, so it appears in `GameController` as `GCExtendedGamepad`. **Always** include on-screen virtual sticks as a fallback. Cassius should check that the grips don't block the camera.
- **Out of scope:** multiplayer and squads (decorative avatars only), accounts, networking, analytics, real maps, real purchases.

---

## 7. What to build, in priority order

There is very little time before 9:10 am. Ship in **cuts**: every cut must leave the app demo-safe, so compile-check and run on the phone before starting the next. If time runs out after Cut 2, that's still a good demo.

### Cut 1: drone flight (brief Phase 2)
New files:
- `DroneComponent.swift` / `DroneSystem.swift` (ECS)
- `DroneFactory` (primitive cartoon quadcopter: rounded body plus 4 spinning rotor discs in palette colors)
- `GameInput.swift` (controller plus virtual sticks)

Behavior:
- **Velocity with damping,** not a physics engine. Bank up to 15° into movement; the rotors spin.
- **Altitude:** each frame, keep at least 0.02 m above `TerrainData.height(at:)`, sampled in a small radius under the drone so it doesn't clip peaks.
- **Bounds:** clamp x to `0…PIN_FIELD_SIZE.x` and z to `−PIN_FIELD_SIZE.y…0`, with a soft margin.
- **Blob shadow:** a transparent dark disc at `(x, terrainHeight + 0.0005, z)`. It sells the illusion.

Controls (brief §5.2):

| Input | Action |
|---|---|
| Left stick | move/strafe relative to the drone's heading |
| Right stick X | yaw |
| R2 / L2 | ascend / descend |
| A | tag |
| L1 / R1 | switch tool |

- **Virtual sticks:** two SwiftUI drag circles at the bottom-left and bottom-right, hidden when a `GCController` is connected. Listen for `GCControllerDidConnect`.
- **Spawn:** at the front-center of the field, about 3 cm above terrain, only after `isLocked`.
- **Speeds:** about 0.05 m/s max, tuned to the 15 cm field. Make every number a named constant at the top of the file.

### Cut 2: targets, reticle, tagging, HUD (the heart of the demo)

**MissionSystem** (new):
- Picks N NPCs (e.g. 3) as targets, ideally near one site (a "sector").
- Adds a `TargetComponent` and a pulsing soft ring under each one (a flat disc that follows the NPC, in hot pink or yellow), plus a small floating label ("TGT 1").
- Add a `CollisionComponent` (small box or capsule) to NPCs so they can be hit-tested.

**Reticle:**
- Raycast from the screen center each frame: `arView.hitTest(center)` or `scene.raycast` filtered to targets.
- When it hits a target, the reticle grows and glows.
- **Tag** by hovering 1.5 s (show a progress ring) or pressing A.
- **On tag:** a cheerful pop (scale bounce plus confetti particles or a sparkle burst), points added. The tagged NPC keeps walking with a "TAGGED" badge. **Never** show harm.

**HUD** (`HUDView.swift`, a SwiftUI overlay in `ContentView` shown when `isLocked`). Landscape layout:
- Rounded corner brackets framing the screen.
- Center reticle echoing the `[ + + ]` logo (two plus signs over a smile, in square brackets).
- **Left margin:** ALT and HDG. **Right margin:** ZOOM and FUEL (vertical bar). Use a bold rounded font: `.system(.headline, design: .rounded)`.
- **Top bar:** mission name, 2–3 static squad avatar circles, gems 💎 and credits counters.
- **Radio text:** types out letter by letter at the top, e.g. "Be advised, Operator. Three targets in sector LOW. Tag them before fuel runs out."
- **Bottom:** 3 tool slots, SCAN / TAG / BOOST. Highlight the selected one; L1/R1 cycle them.
  - SCAN: briefly outline all targets.
  - BOOST: 2 s of speed at a fuel cost.
- **Small corner widgets:** a mini-map (the field rectangle, the drone as a dot, targets as pink dots), plus score and mission timer.
- **Style:** translucent `.ultraThinMaterial` pills, the palette colors, generous rounding.
- **Don't cover the center third:** the city has to stay visible. Keep it legible in bright rooms.

**GameState** (`@Observable`): score, fuel, gems, credits, prestige (0–3), the current mission, the targets remaining, and the selected tool.

### Cut 3: Prestige filter (the critique's key moment; brief §5.6)
- **Debug control:** a Prestige 0–3 slider in `DebugPanel`. Cassius slides it live in front of the room.
- **Simplest robust approach: material swap,** no post-processing.
  - **Level 0:** cartoon, as now.
  - **Levels 1–2:** keep cached copies of the original materials, and add thermal materials: unlit grayscale for the city, with the terrain dark gray to black by height. Crossfade with `OpacityComponent` on a duplicated thermal city, or by swapping materials.
  - **Level 3:** mostly thermal, with the cartoon reduced to outlines (an approximation is fine).
- **NPCs:** **all** turn white-hot (unlit white with a slight bloom-like halo disc). Targets look identical to ambient NPCs.
- **HUD under thermal:** turns monochrome green or white, and the candy colors drain.
- **Optional, if stable:** `ARView.renderCallbacks.postProcess` with a Core Image grayscale and contrast filter for the camera feed at levels 2–3. Test performance on device, and drop it at the first sign of instability.
- **A clean "Reset mission" button** in `DebugPanel` sets prestige 0, refills fuel and picks new targets.

### Cut 4: fuel and visible meta
- **Fuel:** drains over time (about 90 s per full tank, so a demo run doesn't hit zero by accident). At zero, the drone settles, and a "Refuel" sheet offers "Refuel for 💎 20" and "Watch an ad" (fake). Tapping either refills.
- **Meta screens:** shallow, static is OK. A crate-open animation (a box that pops open to a tool-upgrade card), a daily-reward card, a "LIVE EVENT" banner in the top bar. Reachable from a small menu button. Never block gameplay.

### Cut 5: sync-dock flow and polish (brief §5.7)
- **Launch screen:** a calm "SYNCED" screen with the `[ + + ]` logo and a charging indicator. It goes to camera and "Locate your Field Unit" on tap or after a moment.
- **The LOCKED moment:** a satisfying confirmation animation and a sound if possible.
- **App icon** with the `[ + + ]` logo.

### Cut 6 (only if everything else is solid): drone-cam picture-in-picture
- A non-AR render from a camera under the drone, in the bottom-right corner. It becomes the thermal view at Prestige 1. This is finicky (second `ARView` with `cameraMode: .nonAR` sharing cloned entities), so do it last or skip it.

---

## 8. Demo script the app must support (brief §8)

1. **Commission (30 s):** talking. The app is on the SYNCED/launch screen, or locked.
2. **Front stage (1 min):** lift the phone, LOCKED, the city appears, fly the drone, tag a target. Show the Field Unit and the trophy.
3. **Back stage (1 min):** slide Prestige up live, and the cartoon drains to thermal. "And yes, some missions are live."
4. **Let it land (30 s):** the phone goes face up on the Field Unit with the cartoon still running.

The app needs:
- a quick lock
- no crash when tracking is lost or the phone is set down
- a fuel tank that won't run dry during a 3-minute run
- Prestige reachable in one gesture during the pitch. Consider a hidden two-finger swipe or the controller's Menu button besides the debug panel.

---

## 9. Working rules (carried over)

- **Small, single-purpose Swift files.** Constants go at the top of the file that uses them.
- **Compile-check after every change.** Install on the phone at each cut, but only when Cassius says they aren't mid-test.
- **Performance:** AR plus LiDAR plus segmentation already runs. Keep per-frame work light: no allocations in systems, and reuse meshes and materials. Watch for thermal throttling during a 3-minute run.
- **Recording decisions:** add an entry to `DECISIONS.md` per meaningful decision, in its format (number · title, date line, Decision / Alternatives / Familiar or new). Next free number: **023**.
- **Before you stop:** update `docs/HANDOFF.md`, or this file, with what's done and what's next.
- **Ask Cassius** about anything in §4, about drone size and style, and before cutting a brief feature.
- **Morning of the critique:**
  1. Rebuild and reinstall (7-day signing).
  2. Charge the phone.
  3. Do a full 3-minute run-through.

---

## 10. File map

| Path | What |
|---|---|
| `PROXY/PROXYApp.swift` | App entry; registers ECS components and systems (register yours here) |
| `PROXY/ContentView.swift` | ZStack: AR view, status pill, debug panel. Add the HUD overlay here |
| `PROXY/ARViewContainer.swift` | ARView, session, `Coordinator` (scene graph, Sync/Re-lock, snapshots, frame updates) |
| `PROXY/ContentLoader.swift` | Loads the city, occluder, placeholder and NPCs; the cartoon palette and materials |
| `PROXY/NPC.swift`, `NPCSystem.swift` | NPC component, factory and walking system (the ECS pattern to copy) |
| `PROXY/TerrainData.swift` | Heightfield, paths, sites |
| `PROXY/PlacementSettings.swift` | Calibration constants (don't touch), physical setups, observable settings |
| `PROXY/DebugPanel.swift` | Three-finger-tap panel: add Prestige and Reset mission here |
| `PROXY/MarkerLock.swift`, `MarkerSampler.swift`, `ViewpointSet.swift` | Lock logic (don't touch) |
| `PROXY/SnapshotStore.swift` | In-app snapshots |
| `PROXY/DepthScan.swift`, `FidelityFit.swift` | Diagnostic LiDAR scan (leave alone) |
| `tools/` | Model export, marker generation, path routing (Python; `rhino3dm` needed for export) |
| `*_print_*.pdf` | Marker print files (print at 100%) |

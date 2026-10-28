# Handoff: PROXY AR app, Monday 2026-10-26 (evening; §2–§3 updated 2026-10-27)

For the next session's orchestrator. Read this first, then `CLAUDE.md`, then `docs/AR_ALIGNMENT_PLAYBOOK.md`. **The critique is Wednesday 2026-10-28, 9:10 am.** The app must run on Cassius's iPhone, charged.

---

## 1. How to work (the user cares about this)

- **You orchestrate; roles do the work.** Delegate every step to `.claude/agents/` with full context: file paths, prior outputs, device numbers, the user's screenshots. Don't do a role's job inline. The user was explicitly disappointed when this session worked without the agents and without decision trails.
- **Roles:** explorer, ios-builder, healer, reviewer, documenter (from SVSD-Winners, adapted), plus two PROXY-specific roles: **device-runner** (build, install, launch, console capture, measurements log) and **alignment-analyst** (diagnoses logs, scans and screenshots; owns the playbook). They should be registered by name in this new session; if not, run each through a general-purpose agent told to read and follow `.claude/agents/<role>.md`, passing the role's `model:` from its frontmatter (otherwise it runs on the main session's model).
- **Loops:**
  - Feature work: explorer → (human approval) → ios-builder → healer → reviewer → documenter.
  - Device and alignment: device-runner → alignment-analyst → ios-builder → reviewer → device-runner. The user tests on the phone alongside.
- **Agency limits** (playbook §1): build, install, launch and read logs freely. **Ask the user** before changing saved calibration constants, changing physical placement or print instructions, editing outside `AR Experience/`, or changing the brief's design. **Never install while the user is mid-test.**
- Delegate parallel work so roles never edit the same file at once.

---

## 2. Where things stand

- **Pin block alignment confirmed & verified** (Session 8, 2026-10-27; DECISIONS 025, 026): With the two 50 mm markers trimmed to the border and aligned flush with the left and right edges of `pins_block.stl`, the virtual diorama snaps flush across the 43×40 pins. Overhead & perspective snapshots pulled from device (`snap_20261027-170139_1_lock1.jpg`) confirm clean registration.
- **First-Person Perspective (FPV)**: External 3D toy drone removed. The physical iPhone in the user's hands is the drone camera, with dynamic altitude (ALT in mm) and heading (HDG degrees) calculated in real time against the terrain heightfield.
- **Backbone One Controller Integration**: Auto-hides on-screen virtual thumbsticks when plugged in; displays physical PlayStation button hints (`✕` TAG, `L2` SCAN, `R2` ZOOM). Right Trigger and right stick toggle digital zoom (1.0X -> 2.0X -> 4.0X). D-pad Up/Down cycles Prestige themes.
- **3D Ray-Cone Reticle & Assisted Striking (DECISION 028, 029)**: Completely overhauls ant/target striking. Replaced fragile screen-space `arView.hitTest` (which was intercepted by the LiDAR scene reconstruction mesh) with a 3D camera forward vector ray + screen projection engine. Direct hits lock at `rayDist < 35mm` / `screenDist < 85pt`; assisted strike catches near-misses up to 60mm / 140pt upon pressing `✕` or `□`. **Manual trigger only:** Removed auto-strike on hover to preserve full player agency.
- **Juice & Visual Feedback (DECISION 029)**: Dynamic 3D expanding shockwaves (`spawnShockwave`) expand over 0.5s beneath neutralized targets; floating combat text (`+250 PEST ELIMINATED 💥`, `+500 RECON POINTS 🎯`) pops with spring physics directly above the reticle; OLED curved bezel flashes with impact colors (`0.22s`); neutralized targets permanently freeze in place with glowing splat decals.
- **Reality Filter Stability (DECISION 029)**: Reality filters (Prestige levels) are strictly player-controlled via D-Pad Up/Down or tapping the HUD Prestige pill; decoupled from sector advancement to eliminate disorientation. Sector clearing debounced with 3.5s breathing room.
- **Tactile & Audio Feedback**: Heavy haptic strike feedback (`UIImpactFeedbackGenerator(style: .heavy)`), audio pop click, permanent bio-splat rings on terrain, and ant squash animations (`scale = [1.4, 0.2, 1.4]`).
- **SessionLogger Telemetry**: Diagnostic event logging active in `SessionLogger.swift`, appending to `Documents/Logs/session_<timestamp>.log` inside the app container for instant retrieval via `devicectl`.
- **Themed Prestige Progression (Critique Core)**:
  - Level 0 (OPERATION CITADEL): Cheerful cartoon citizens, hot pink target rings, `+500 RECON POINTS`, confetti burst.
  - Level 1 (PEST CONTROL SWARM): Citizens transform into swarming black/brown ants with segmented bodies; reticle shifts to bio-tracking `[ *  * ]`, tagging triggers a lime-green bio-splat (`"PEST ELIMINATED! +250 PEST CREDITS"`). Evoking drone warfare "bugsplat" dehumanization critique.
  - Level 2 (SYNAPSE TACTICAL): Monochromatic tactical HUD, numeric threat confidence ratings.
  - Level 3 (SILENT DAWN / FLIR): Grayscale thermal diorama, uniform white-hot heat signatures. Target rings removed. Stark, cold, silent lock-on (`"BUGSPLAT RECORDED. CONFIRMED IMPACT · 0 COLLATERAL"`).
- **Visual Overhaul (DECISION 030)**: Eliminated cheap toy-like neons and emojis in favor of a sleek Mil-Tech & Smoked Glass aesthetic. 3D diorama upgraded to architectural cel-shaded matte sage/slate/resin materials (`roughness: 0.35`). Ants upgraded to high-gloss obsidian chitin (`roughness: 0.08`), anatomical petiole waist, amber compound eyes, and articulated legs. HUD upgraded with smoked obsidian panels, military comms ribbon, real-time compass tape, raster radar, and precision milliradian crosshairs.
- **Ammunition & Ordnance System (DECISION 031)**: Added an 8-round tactical magazine rack (`AMMO // 08/08`) directly below the center reticle and in the right margin telemetry. Every trigger pull consumes a round, flashes the expended cartridge, decrements the counter, triggers a -6pt spring recoil kick on the reticle, and fires a 3D laser tracer beam in AR space that impacts targets or terrain with kinetic dust puffs. Features auto-reload on empty (1.4s) with animated progress bar, dry-fire lockouts with audio/haptic clicks, and manual reload via controller Triangle (`△`) or tapping the HUD rack.
- **Orbital Strike Ray of Light & NPC Retaliation (DECISION 032)**:
  - **Orbital Strike Ray (`spawnStrikeRay`)**: Firing discharges a 0.24m tall vertical column of light descending from the orbital sky straight down onto the target or terrain, composed of an additive glowing corona cylinder (5.5mm radius), an intense white-hot core (2.2mm radius), and a 24mm ground scorch flare disc, accompanied by a 3.0mm volumetric forward tracer.
  - **Hostile Retaliation (`NPCCombatSystem`)**: Live un-neutralized ants now actively fight back! Striking an ant triggers immediate retaliatory counter-fire from nearby ants, and live ants launch ambient bio-acid spits (Prestige 1) and anti-air darts (Prestige 2/3) toward the drone camera every 4–6s.
  - **Drone Shield & Impact Feedback**: The drone possesses 100% shield integrity (`droneShield`), monitored via an 8-segment `SHIELD // DEF` HUD gauge. Counter-fire impacts within 45mm of the drone camera deplete 15% shield, shake the iPhone with heavy haptics (`.heavy`), trigger impact audio (`1521`), strobe a red screen damage flash vignette (`droneDamageFlashTimer`), and display an incoming threat alert banner (`⚠ THREAT DETECTED // INCOMING COUNTER-FIRE ⚠`).
  - **Diagnostic Bug Fixes**: Fixed Bug A (ambient ants not decrementing remaining target count), Bug B (hardcoded sector string), and Bug C (stale target rings).
- **Streamlined Mil-Tech HUD Declutter Pass (DECISION 033)**: Cleaned up busy UI elements across the viewport. Consolidated top bar into a single slim row (`● OPERATION [LOW]`, central radio transmission line, right `TGT 2/3` and Mode button), removing dummy callsigns and currencies. Decongested center reticle by removing the bulky 8-round magazine rack and ammo text from directly under the crosshairs to provide an open, unobstructed view of the ants. Merged left telemetry into a compact `ALT / HDG` badge, unified right telemetry into `ZOOM` and `DEF / ORD`, and stripped static corner coordinate text blocks from the curved OLED bezel.
- **Hardware-Accelerated Optical Zoom & Precision Aim Assist (DECISION 034 & 035)**:
  - **Native UIKit Scaling**: In `ARViewContainer.updateUIView`, animated `arView.transform = CGAffineTransform(scaleX: targetScale, y: targetScale)` directly via `UIView.animate` to ensure RealityKit's Metal layer physically magnifies from the center crosshair at 1.0X -> 2.0X -> 4.0X.
  - **Optical Aim Assist**: Corrected `screenDist = unzoomed` (eliminating the zoom inversion penalty where distant ants were pushed out of lock range). Expanded lock cone (`100pt` / `45mm`) and accelerated electronic lock-on time to `0.35s` (2.3x faster) in optical zoom.
  - **Precision Strike Bonus**: Striking while zoomed in awards `+25` score and displays `★ OPTICAL PRECISION HIT +25 ★`.
  - **Fly-By-Wire Joystick Drone Flight (DECISION 036)**: Added full dual-stick virtual drone navigation for seated or mobility-constrained play without relying solely on physical phone craning:
  - **Left Thumbstick:** Fly Forward/Backward & Strafe Left/Right (`0.22 m/s`).
  - **Right Thumbstick:** Gimbal Yaw Pan (`55°/s`) & Altitude Climb/Dive (`0.15 m/s`).
  - **Re-Centering:** Click Left Stick (`L3`), tap D-Pad Left, or tap the on-screen `RE-CENTER` pill to snap back to the physical marker origin.
  - **Seamless Additive Gyro:** Physical phone movement and joystick flight work simultaneously in 60fps harmony.
  - **Touchscreen Sticks:** Automatically displays on-screen virtual thumbsticks if no physical controller is attached.
  - **HUD Integration:** Shows active fly-by-wire telemetry (`[ FBW // 28CM ]`) and dynamically updates altitude and compass heading as the drone flies.
- **Audio Ambience**: Procedural synthetic quadcopter rotor hum (~85 Hz fundamental with harmonics) generated via `AVAudioSourceNode` without external asset dependencies.
- **Snapshots & Logs**: Automatically saved to `Documents/Snapshots/` and `Documents/Logs/` inside app container and pulled via `devicectl`.

---

## 3. Immediate next actions, in order

1. **Print the DockMarker:** 100 mm, 100% scale, on a stiff card. **Measure the card's thickness** and report it. `DOCK_MARKER_TO_ORIGIN` assumes 1.2 mm.
2. **Run a Field Unit 100 test** (DECISIONS 021 procedure). Log it in the playbook's measurements log.
3. **Rebuild the morning of the critique** (Wednesday 2026-10-28). Builds expire after 7 days. Install, then run the DECISIONS 021 procedure: one Sync, 20–25 cm away, looking down 45–60°, holding still.

---

## 4. Open user-facing items

- **Pending from the user:** ruler measurements; screenshots per lock.
- **Exact NPC paths:** the user hasn't run `diorama.py` in `RUN_MODE = "paths"` yet. It needs the original Rhino doc (on the `MatterFlowCAD` machine), and it writes `paths.json`; the steps are in the README. Until then, 2 of 5 paths are exact (FRONT-LOW, LOW-MID2); LOW-MID and MID-HIGH are approximate.
- **Field Unit 50 and Field Unit 100** (sync dock): both untested on device. Field Unit 100 needs the DockMarker printed first (§3).
- **Physical questions** raised earlier and unanswered: does the Backbone grip block the camera? The phone plus controller (~25 cm) can't sit in the 100 mm sync-dock pocket.

---

## 5. Key facts and gotchas

- **Coordinates:** content frame = meters from `PINS_ORIGIN` (Rhino (5, 0, 7.58) mm), `(x, y, z) = (X−5, Z−7.58, −Y)/1000`. Models extend +x and −z. **The front (where the player stands) is Rhino +X**, so content yaw relative to the marker is −90°.
- **Diorama placement:** markers trimmed exactly to the black border, top edges against the marble base's front face (Rhino X 182.8), upright as read from the front (notch top-left). LEFT is flush with the base's left side (Y 0), center (207.8, 25.0); RIGHT is flush with the right side (Y 146.35), center (207.8, 121.35); spacing 96.35 mm. Print `CalibrationMarkers_print_50mm.pdf` at 100%.
- **The brief's numbers are outdated** (304.8 mm, 40 × 40 pins). The real pin field is 158.6 × 146.4 mm, 43 × 40 pins. The Rhino measurements win (DECISIONS 007).
- **Device:** UDID `00008150-000518D10130C01C`, free team `Q48J597563`, bundle `com.cassiuspalacio.proxy`. Builds expire after 7 days, so **rebuild the morning of the critique**. Always set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- **Console:** launch detached with `devicectl ... --console` to a log file. `signal 9` means the app was swiped away; `Locked` means the phone is locked. Home-screen launches give no logs.
- **Duplicate markers:** any marker PDF visible on a screen ruins the lock. The guard now refuses it and shows "Marker seen twice? Hide extra copies".
- **The fidelity fit:** solves x, z and yaw; height is a nuisance term (LiDAR reads a few mm deep). Its yaw is noisy (±0.8°), but always positive so far. Its RMS floor is about 4 mm.
- **Content source:** `tools/export_models.py` (needs `rhino3dm`, installed in the scratchpad venv) regenerates `city.usdz`, `pins_occluder.usdz`, `terrain.json` and `terrain_height.bin` from `../Diorama`. Never hand-edit those.

---

## 6. File map

| Path | What |
|---|---|
| `PROXY_AR_BRIEF.md` | The user's full brief (premise, phases, demo script) |
| `CLAUDE.md` | Build command, rules, agent workflow |
| `DECISIONS.md` | Decision trail 001–022 (014 two-marker, 015 agent workflow, 016 open hypotheses, 017 height from markers, 018 duplicate guard, 019 diverse sampling, 020 snapshots, 021 demo procedure, 022 subagent models) |
| `docs/AR_ALIGNMENT_PLAYBOOK.md` | Rules, error budget, device loop, ranked hypotheses, **measurements log**, **next-session protocol** |
| `README.md` | Setup, printing, placement, debug panel, calibration |
| `PROXY/MarkerLock.swift` | Lock logic; a PURE block (simd-only) with the pair math and thresholds; the Coordinator extension |
| `PROXY/MarkerSampler.swift` | Per-marker averaging (ring buffer of 30, circular-mean heading, inlier median) |
| `PROXY/ARViewContainer.swift` | Session config, Sync and Re-lock, scan and fit wiring |
| `PROXY/DepthScan.swift`, `FidelityFit.swift` | LiDAR depth scan and the x/z/yaw fit |
| `PROXY/PlacementSettings.swift` | Calibration constants, settings, nudge and applyFit |
| `PROXY/DebugPanel.swift` | Three-finger-tap panel |
| `PROXY/NPC*.swift`, `TerrainData.swift` | NPCs on paths, heightfield |
| `tools/` | Marker generation, print PDF, model export, path routing |
| Scratchpad (session-specific, may be gone) | `.../scratchpad/check/` holds the numeric checks; `dd-device` and `dd-next` are derived data; `proxy_console_2marker.log` is the last session's log |

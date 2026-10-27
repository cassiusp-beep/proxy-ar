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

- **Pin block works** (sessions 5–7; DECISIONS 014, 019). Two markers on the pin block's front face; per-marker 30-sample averaging; keep-world re-locks. Session 7 round A (consecutive sampling) passed the 0.3° heading repeatability target. Diverse sampling is built but off (DECISIONS 019).
- **Diorama** (two markers on the marble base) locks and re-locks. Heights come from the markers (DECISIONS 017). The duplicate-marker guard refuses double-seen markers (DECISIONS 018).
- **Snapshots** are saved to `Documents/Snapshots` and pulled with `devicectl` (DECISIONS 020).
- **Field Unit 100 is untested.** The single 100 mm DockMarker isn't printed yet. The card's thickness is unmeasured.
- **Follow-ups from DECISIONS 018** (NaN guard, Field Unit plane offset, `plane_dy_mm`, right-only refusal escape) were in progress on 2026-10-27. Their status isn't confirmed here; check before the rebuild.
- The brief's Phase 2 (drone, controller) and Phase 3 (game loop, meta) are deferred. Phase 4 (Prestige filter, sync-dock screens) is deferred too.

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

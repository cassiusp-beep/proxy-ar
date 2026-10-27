# PROXY

**Starting a new session? Read [docs/HANDOFF.md](docs/HANDOFF.md) first** (current state, approved-but-unbuilt work, next actions). Then **read [PROXY_AR_BRIEF.md](PROXY_AR_BRIEF.md)**: it is the full project brief. Where it conflicts with the Rhino file's measured values, the measurements win (see DECISIONS.md 007).

Native iOS AR app (SwiftUI + RealityKit + ARKit). Deployment target iOS 26; the only target device is iPhone 17 Pro Max (iPhone-only, landscape, in a Backbone-style controller). Phase 1: lock city.usdz onto a physical terrain model via a printed image marker. No game logic until phase 2.

## Build

`xcode-select` points at CommandLineTools on this machine, so always set DEVELOPER_DIR:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project PROXY.xcodeproj -scheme PROXY -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

ARKit world tracking needs a real device; the Simulator can't verify AR behavior.

## Rules

- `PROXY/` is a synchronized folder: files added there join the target automatically (Info.plist is excluded from resources).
- Keep Swift files small and single-purpose.
- Calibration constants live at the top of `PROXY/PlacementSettings.swift`.
- 3D content and terrain data come from `../Diorama` via `tools/export_models.py` (run with a Python that has `rhino3dm`); never hand-edit the generated files in `PROXY/`.
- The Field Unit's front (where the player stands) is Rhino +X, not −Y (DECISIONS 008).
- Check `DECISIONS.md` before reopening a settled question.
- **Debugging alignment?** Read [docs/AR_ALIGNMENT_PLAYBOOK.md](docs/AR_ALIGNMENT_PLAYBOOK.md) first: operating rules (what to do without asking), acceptance criteria for saving a calibration, the device build/install/console loop, ranked hypotheses, and the measurements log. Update the log after every device test.

## Agents

Adapted from the SVSD-Winners roster plus PROXY-specific roles, in `.claude/agents/`. **The main session orchestrates and delegates every step to these roles, passing all context (file paths, prior outputs, device results, user screenshots).** It does not do a role's job itself.

- Feature slice: explorer → (human approval) → ios-builder → healer → reviewer → documenter.
- Device and alignment loop: device-runner (build/install/launch/console → measurements log) → alignment-analyst (diagnose, playbook) → ios-builder (fix) → reviewer → documenter. The user tests on the phone side by side.
- Agents created mid-session aren't registered until the next session; until then, run a role through a general-purpose agent told to read and follow `.claude/agents/<role>.md`, and **always pass that role's `model:` from its frontmatter** on the Agent call (sonnet for device-runner, healer, explorer; haiku for documenter; opus for ios-builder, alignment-analyst, reviewer). Without it the agent inherits the main session's model.

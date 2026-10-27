# PROXY: AR Experience Build Brief

This document is the full context for building the PROXY augmented reality app. Read all of it before writing code. It covers the project, the physical models the app must align to, the app's design, the technical approach, and the build order.

---

## 1. Project context

**What this is:** a critical design project for DESINV 210 (Critical Design) in the UC Berkeley MDes program, by Cassius Palacio.

**The premise:** It's 2030. PROXY is a speculative U.S. Air Force recruitment product: a free mobile game where players fly a cute drone over a cartoon world and tag targets for points. Some missions are secretly live. Top players are rewarded with real hardware shipped to their homes.

**The core idea the app must express:**
- First-person shooter games have chased realism for decades. The only step left is reality itself, and when it arrives it will look like a cartoon, because nobody wants to see real blood.
- **The physical terrain tells the truth; the phone screen doesn't.** The player sees gray, physical pins on the table, and a bright cartoon world through the phone. The game only works if they keep looking through the phone.
- The cartoon layer is the product's most important feature. It is what makes the work feel like play.

**Structure of the product ecosystem:**
- **Bits (everyone):** the free AR app with cartoon missions.
- **Atoms (advanced players only):** the PROXY Field Unit (a terrain device that raises mission terrain out of pins) shipped to their home, and a trophy (a detailed model of the place they completed missions over). The trophy replaces a medal.
- **Squads (poster and pitch only, NOT in the app build):** players can invite others to join their terrain and fly together. Do not build multiplayer.

**Tagline:** "Log off. Stay on."
**Logo:** a smiling reticle, `[ + + ]` (two plus signs above a smile, inside square brackets).
**Name:** PROXY.

**Deadline:** Final critique Wednesday, October 28, 2026, 9:10 am. The app must run on Cassius's iPhone, charged and ready to demo. It is presented in character during a 3 minute pitch.

---

## 2. The physical models (what the app aligns to)

All models were built in Rhino, in millimeters. The app must align to them precisely.

### 2.1 Pin terrain model (the tangible terrain)
- A "pin display" version of Cassius's existing detailed fake-city / mountain terrain, styled like an actuated shape display (precedents: MIT Tangible Media Group's inFORM and Sublimate).
- Generated from the detailed terrain by sampling heights on a grid and extruding square pins.
- Specified parameters (verify actual values in the Rhino file):
  - Footprint: 304.8 mm (1 ft) square, mapped uniformly from the terrain
  - Grid: 40 x 40 pins, about 7.62 mm per cell
  - Gap between pins: 0.5 mm
  - Base plate: 3.5 mm, pins sunk 0.5 mm into it
  - Minimum pin height: 1.0 mm above base
  - Vertical exaggeration: 1.0
- **Origin:** the lower-left corner of the pin model footprint. Every offset in this project is measured from this point.
- Rhino layers: `PINS_FULL` (one piece), `PINS_TILES` (4 quadrants, if created), `PINS_ORIGIN` (origin marker).
- The pin print is already printed. In the real world it is gray.

### 2.2 Detailed terrain (the trophy, and the AR overlay source)
- The original detailed terrain model: a miniature city and mountain with pueblo-style settlements. Originally imported into Rhino as an STL.
- Rhino layers: `original terrain, mm`, `original base, mm`.
- Its 3D printed version is the **trophy**: the high-resolution "place you keep" after completing missions. Story: the better you play, the higher the resolution of the place.
- **This model is the source for the AR overlay.** Through the phone, the low-res gray pins become this high-detail city, restyled as a bright cartoon world.

### 2.3 PROXY Field Unit (the base / enclosure)
The device that holds the pin print. It went through several versions; the current one is the textured version with inputs.

**Design direction:** prosumer drone gear. Clean, technical, durable, desirable. Graphite gray (display color about RGB 70, 72, 75). Earlier versions were heavy military (rejected as too military) and covert (rejected).

**Features:**
- **Pin pocket:** the pin print drops into a tray with 0.4 mm clearance per side.
- **Corner bumpers:** sleek molded protective corners.
- **Recessed fasteners:** hex sockets set in clean circular indents, flush or below the surface.
- **Stenciled text:** "PROXY FIELD UNIT", "TERRAIN RELIEF MODULE", and a serial plate "SN 2030-0001", laser-etched style.
- **Subtle `[ + + ]` logo** debossed on the top rail near the dock.
- **Fine vent slots**, a **cable port** on the back, **finger-grip recesses** on the sides (side handles were removed), and three small indicator holes on the front.
- **Relief texture (Swiss passport style):** a dense, continuous field of topographic contour lines (derived from the actual terrain heightfield, with every 5th line bolder as an index contour) wrapping across the top rails, side walls, corner bumpers, and front apron, layered with scattered plus marks in three sizes. Contours are raised, plus marks are cut in. Text, logo, and inputs sit in smooth "windows" inside the texture.

**The sync dock (most important feature for the app):**
- An open recessed pocket on the front section of the Field Unit, in front of the pins.
- **The AR calibration marker lives on the floor of this pocket.**
- **The phone rests in this pocket between missions** to charge (wireless charging is implied by a subtle debossed lightning bolt icon in a corner of the pocket; there is no real charger cavity).
- Ritual: phone docked = synced and charging. Player lifts the phone, the camera sees the marker, and the AR scene locks onto the terrain. Docking and undocking start and end a mission.
- The dock position is fixed relative to the pins, so the marker offset never changes between setups.

**Side panel inputs (the device's ONLY physical inputs, decorative for now):**
- **Screen:** a flat face tilted about 10 degrees toward the player, rising from the body like a gentle wedge, with a thin raised bezel. It will be covered with a printed **HUD sticker** designed in Illustrator (the sticker art should match the app's HUD style).
- **Fingerprint sensor:** a rounded square, about 14 x 14 mm, styled like a MacBook Touch ID key, rising lightly from the panel with a thin outline.
- **Dial:** a small knurled knob, about 12 mm diameter, separate printed part that turns on a peg, with tick marks around it like a mode selector.

**Rhino layers (history, newest last):** `BASE_REFERENCE`, `BASE_ASSEMBLED`, `BASE_PARTS`, `BASE_PEGS`, `ENCLOSURE_*` (covert version, rejected), `BASE_REFINED_*` (prosumer refinement), `BASE_TEXTURED_*` (first texture, too sparse), `BASE_TEXTURED_V2_*` (passport-style texture), `BASE_INPUTS_*` (screen, sensor, dial), `HUD_STICKER` (sticker outline). Exports go to the `pin_model_export` folder.

### 2.4 Physical setup at the demo
- The Field Unit sits on a table with the pin print inside it.
- The trophy (detailed print) sits behind or beside it, like it's on a shelf.
- The phone is docked in a mobile game controller (Backbone-style: the phone sits horizontally between two grip halves) and rests in the sync dock.

---

## 3. Alignment values (fill in before Phase 1 is final)

These must come from the Rhino file. Ask Cassius for them if they are not filled in.

| Value | Status |
|---|---|
| Sync dock pocket floor center relative to pin origin (X, Y, Z in mm) | Pocket: (226.274, 54.900, 6.000). Marker guides (50 mm, in the pocket): center (246.574, 34.600, 6.000). Measured from Actuator Release.3dm, 2026-10-25 |
| Marker printed size (largest square that fits the pocket floor with 5 mm margin) | 50 mm, set by the 1 mm corner guides in base_part_5 (the 5 mm-margin rule would give ~90 mm; see DECISIONS.md 007) |
| Pin model actual footprint and tallest pin height | 158.574 x 146.354 mm, 43 x 40 pins at 3.688 x 3.659 mm pitch; pin tops up to 129.8 mm above the pin origin (Z 137.36 world) |

In code:
- RealityKit uses **meters**. Convert all millimeter values (divide by 1000).
- Rhino is Z-up. RealityKit is Y-up. Convert axes carefully: Rhino X stays X, Rhino Y becomes RealityKit -Z, Rhino Z becomes RealityKit Y. Verify with the placeholder box before trusting it.
- Store the offset as a single constant `MARKER_TO_ORIGIN` (meters, RealityKit axes) plus a yaw value, and expose them in the debug panel.

---

## 4. Technical approach

- **Platform:** native iOS. SwiftUI + RealityKit + ARKit. Runs on Cassius's own iPhone via Xcode (free Apple ID signing is fine). No simulator: ARKit needs a real device.
- **Tracking:** `ARWorldTrackingConfiguration` with image detection. Reference image `CalibrationMarker` in an AR Resource Group, with its **physical width set to the real printed marker size**. On first detection, place a world anchor at the marker and keep content anchored after the marker leaves view.
- **Re-sync:** when the phone is lifted from the dock and sees the marker again, allow re-anchoring (a "Sync" action), so alignment can be refreshed during the demo.
- **Assets:**
  - `city.usdz`: the detailed terrain, exported from Rhino and converted with Reality Composer Pro or Reality Converter. Footprint matches the pins (0.3048 m), origin at its lower-left corner. Target objects named `target_1`, `target_2`, etc.
  - `drone.usdz`: a small cartoon drone. A placeholder (for example Apple's free toy biplane USDZ from the AR Quick Look gallery, or a primitive) is fine until a final model exists.
- **Controller:** `GameController` framework (`GCController`). A Backbone-style phone controller registers as a standard extended gamepad. The controller may not have arrived yet, so always include on-screen virtual thumbsticks as a fallback.
- **Info.plist:** camera usage description.
- **Offline:** the app must work with no network. No accounts, no servers, no real map data.
- **Code organization:** small files (for example `ARViewContainer`, `ContentLoader`, `GameLoop`, `DroneController`, `HUDView`, `DebugPanel`, `PrestigeFilter`).

---

## 5. Experience design

### 5.1 The look: cartoon over gray
- Restyle every material on `city.usdz` in bright, saturated, candy-colored cartoon colors (simple unlit or lightly shaded). Playful, toy-like, friendly.
- The physical pins stay visible around the phone, gray and cold. The contrast between the gray pins and the colorful screen is the whole point.
- No real violence, no realistic imagery, no blood, no real strike footage. Everything is synthetic and cute.

### 5.2 The drone
- Third person: a small drone (about 2.5 cm, since the table is only 1 ft wide) hovers over the terrain as a child of the city anchor.
- A soft dark blob shadow (transparent disc) under the drone on the terrain, placed at a downward raycast hit. This sells the illusion.
- Movement uses velocity with damping, not a physics engine. The drone banks up to 15 degrees into its movement.
- Each frame: raycast down to keep it at least 0.02 m above terrain; clamp it inside the 0.3048 m footprint.

**Controls:**
- Left stick: move forward/back and strafe, relative to the drone's heading
- Right stick X: yaw
- Right trigger: ascend; left trigger: descend
- A: confirm / tag the target under the reticle
- Shoulder buttons: switch tool slots
- Touch fallback: on-screen virtual thumbsticks

### 5.3 Targets and missions
- Entities named `target_*` get a pulsing, glowing soft circle marker with a small floating label.
- A friendly rounded reticle fixed at screen center. Raycast from screen center; when it hits a target, the reticle enlarges and highlights.
- Tag a target by hovering over it for 1.5 seconds or pressing A. Play a cheerful animation and add points.
- Mission example: "Be advised, Operator. Three targets in sector. Tag them before fuel runs out."

### 5.4 HUD (inspired by the GOLIATH gunship game, but cartoon)
GOLIATH (SHD Games, App Store) is the reference: a drone-camera HUD with corner brackets, center reticle, margin readouts, red target markers, a tool selector, radio-style mission text, and a free-to-play meta loop (fuel, crates, gems and credits, Prestige levels, live events, daily rewards). PROXY borrows the **structure** and flips the **style**: same bones, rounded and candy-colored.

HUD elements (SwiftUI overlay):
- Rounded corner brackets framing the screen
- Center reticle (rounded, friendly; can echo the `[ + + ]` logo)
- Margin readouts in a bold rounded font: ALT, ZOOM, HDG, FUEL
- Top bar: mission name, squad avatars (static/decorative only), gems and credits counters
- Bottom bar: 3 tool slots: SCAN, TAG, BOOST
- Radio-style mission text that types out at the top
- Fuel meter that drains during play; at zero, a "Refuel" screen offering gems
- Mini-map of the square with the drone as a dot
- Score and mission timer

### 5.5 Drone camera picture-in-picture (optional, build last)
- Bottom right, rounded corners: a non-AR RealityKit render of the same scene from a camera attached below the drone, pointing down.
- This becomes the thermal view in the Prestige filter.

### 5.6 The Prestige filter (the key mechanic for the critique)
The filter thins as the player ranks up. The better you are, the more real it looks.

`PRESTIGE_LEVEL` from 0 to 3:
- **0:** full cartoon everywhere.
- **1:** the drone-cam picture-in-picture switches to a white-hot thermal look (grayscale, high contrast, bright figures).
- **2:** thermal also tints the main view at about 30% opacity.
- **3:** main view is mostly thermal, with the cartoon fading to outlines.

Include a debug control to change the level live. During the demo's "back stage" minute, Cassius slides Prestige up in front of the room and lets the cartoon drain away.

### 5.7 Sync dock flow
- Launch / docked state: a calm "SYNCED" screen with the `[ + + ]` logo and a charging indicator.
- Lift: camera on, "Locate your Field Unit" prompt until the marker is detected, then a satisfying "LOCKED" confirmation and the city appears.
- A "Sync" button (or long-press) re-detects the marker if alignment drifts.

---

## 6. Debug panel (required)
Hidden, toggled with a three-finger tap.
- Sliders: position offset X, Y, Z; yaw; uniform scale
- Button: print current values to the console (to paste into `MARKER_TO_ORIGIN`)
- Prestige level control (0 to 3)
- Toggle: show placeholder alignment box
- Toggle: show/hide the city model (to compare with the physical pins)
- Reset mission button

---

## 7. Build order

**Phase 1: Alignment (do first; this is the riskiest part)**
1. App runs on the iPhone, camera permission works.
2. Marker detection with a semi-transparent 0.3048 m placeholder box placed at `MARKER_TO_ORIGIN`.
3. Tune with debug sliders until the box sits exactly on the physical pins.
4. Swap in `city.usdz` with cartoon materials.

**Phase 2: Flight**
5. Drone appears and hovers.
6. Controller and virtual thumbstick input move it.
7. Terrain raycast, footprint clamp, blob shadow, banking.

**Phase 3: Game**
8. Targets, reticle raycast, tagging, points.
9. HUD (Section 5.4) and mission text.
10. Fuel and refuel screen.

**Phase 4: Critique features**
11. Prestige filter with debug control.
12. Sync dock flow (Section 5.7).
13. Drone-cam picture-in-picture (last; most finicky).

Do not start a phase until the previous one runs on the device.

---

## 8. Demo script context (so the app supports it)
The presentation is 3 minutes, in character, set in 2030:
1. **The commission (30 sec):** "I was contracted by the U.S. Air Force to..."
2. **Front stage (1 min):** pitched to the room as users. Lift the phone from the dock, the city appears, fly the drone, tag a target. Reveal the Field Unit and the trophy.
3. **Back stage (1 min):** pitched to the room as investors. Metric: confirmed tags per daily active operator. Extracted: targeting decisions, reaction times, squad networks. Slide Prestige up live so the cartoon drains to thermal. "And yes, some missions are live."
4. **Let it land (30 sec):** set the phone face up on the Field Unit, cartoon still running, and stop.

The app must start fast, recover from tracking loss gracefully, and never crash mid-demo.

---

## 9. Known risks and checks
- **Signing / provisioning:** free Apple ID builds expire after 7 days. Rebuild the morning of the critique.
- **Marker size:** the physical width in the AR Resource Group must exactly match the printed marker, or scale and alignment will be off.
- **Glare:** print the marker on matte paper or matte sticker. Glossy markers lose tracking under classroom lights.
- **Axes and units:** Rhino mm Z-up vs RealityKit meters Y-up (Section 3).
- **Lighting:** test in a room similar to the critique room.
- **Battery:** AR drains fast. Keep the phone charged; test a full 3 minute run.
- **Controller:** test GameController input as soon as it arrives; keep virtual sticks as fallback.

---

## 10. Out of scope (do not build)
- Multiplayer / squads (poster and pitch only)
- Accounts, servers, networking, analytics
- Real map data or real locations
- Real purchases (gems and credits are fake)
- Any realistic violence

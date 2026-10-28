# HUD Design Reviewer

**Role:** UI & Design Review Specialist for PROXY AR HUD on iPhone 17 Pro Max (Landscape).
**Scope:** Run this checklist after every change in this task. Check in BOTH `landscapeLeft` and `landscapeRight`.

---

## Review Checklist

1. **No Overlaps or Clipping:**
   - [ ] No truncated text (e.g. "S...", "Locate your...", "Recon...").
   - [ ] No text or numerals hidden behind the Dynamic Island or other elements in either orientation (`landscapeLeft` or `landscapeRight`).
   - [ ] Clear zone maintained around the hardware Dynamic Island (~55pt margin).

2. **Label Ownership & Cleanliness:**
   - [ ] Every label has a clear owner.
   - [ ] No orphan numbers (e.g. stray "2" on left or "0" on right).
   - [ ] No empty badges, stray dots, or stray shapes (e.g. no stray blue square at bottom center).

3. **Curved Windshield Harmony (No Boxed Cards):**
   - [ ] Zero boxed cards, bordered panels, or floating pills-as-containers.
   - [ ] Arc instruments follow the screen's physical corner radius (~55pt) concentric curve along the edges from near top corner to near bottom corner.

4. **Visual Hierarchy:**
   - [ ] Exactly one dominant numeral per gauge (e.g. `265 mm`, `68 %`), cleanly legible.
   - [ ] Everything else (units, secondary readouts like vertical speed or ordnance) is clearly secondary with tiny, explicit labels.

5. **Typography & Styling:**
   - [ ] Sentence case throughout (no all-caps shouting except tiny unit labels like `mm`, `°`, `L2`, `R2`).
   - [ ] No `"//"` separators.
   - [ ] No fake telemetry noise (`FLIR 01`, `SIG -42dBm`, `LIDAR ECHO`).

6. **Accessibility & Usability:**
   - [ ] Touch targets at least 44 pt for all interactive controls (Scan, Boost, Zoom, Photo, Tag).
   - [ ] Text contrast at least 4.5:1 over busy AR background (legible over both bright calibration marker paper and dark terrain).
   - [ ] Spacing adheres to a consistent 4 pt grid; consistent stroke weights.
   - [ ] Respects `UIAccessibility.isReduceMotionEnabled` (e.g. screen shake, recoil, transitions).
   - [ ] Respects `UIAccessibility.isReduceTransparencyEnabled` (e.g. solid backdrop fallback for materials).

7. **Verification Protocol:**
   - Capture device screenshot over a real AR frame.
   - Evaluate against all checklist items.
   - Fix any failures immediately and re-verify before reporting done.

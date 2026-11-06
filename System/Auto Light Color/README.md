# Auto Light Color (REAPER 7)

Random light colors for newly inserted tracks, with separation from adjacent colors. No fixed palette and no persistent settings window.

## Files

- **jiachen_Auto Light Color Monitor.lua**: silent deferred background monitor. Its REAPER Action List state is ON while running.
- **jiachen_Auto Light Color Settings.lua**: optional ReaImGui settings window. This action is stateless; closing the window does not stop the monitor.
- **jiachen_Auto Light Color Core.lua**: OKLCH generation, sRGB gamut adjustment, and perceptual distance comparison.
- **jiachen_Auto Light Color Startup.lua**: action registration, SWS conflict handling, and monitor startup.

The existing `../jiachen_Global Setup Action.lua` calls the startup script using one `dofile(...)` statement. This keeps the global startup action small.

## Behavior

1. On each project’s first encounter, record existing track GUIDs without changing their colors.
2. For a new uncolored track, generate 128 random OKLCH candidates within the selected lightness and vibrancy ranges.
3. Convert each candidate to sRGB; preserve hue and lightness by reducing chroma when necessary.
4. Compare OKLab distance to the colored tracks immediately above and below. Choose randomly among candidates meeting the separation threshold, or choose the best-distance candidate if none pass.
5. Preserve manually assigned colors and avoid recoloring existing tracks on moves or renames. On Undo/Redo of an insertion, restore the original generated color when the same GUID returns.

Two adjacent tracks can become similar after a later reorder because existing track colors are intentionally stable.

## Settings

Open **Actions > Show action list**, search for **Auto Light Color Settings**, and run it.

Defaults:
- Lightness: 79-90%
- Vibrancy: 48%
- Vibrancy variation: 40%
- Minimum neighbor separation: 12% (OKLab distance 0.12)
- Auto-color new tracks: enabled

Settings persist in REAPER ExtState and are picked up without restarting the monitor. A 16-swatch preview is illustrative, not a fixed 16-color palette.

## Startup and conflicts

The existing JiaChen global startup action registers and starts the monitor on REAPER startup. It disables SWS automatic track coloring so SWS cannot apply colors first. If CHROMA is installed, disable CHROMA's **Autocolor new tracks** feature or stop its coloring script.

Only the **Monitor** action has an Action List ON/OFF state. **Settings** is stateless. Disabling automatic coloring in the GUI does not stop the monitor, and tracks created while disabled are not retroactively colored when the setting is re-enabled.

## Undo/Redo

The monitor never calls REAPER's Undo/Redo operations or creates standalone Undo blocks. Generated colors are auxiliary project changes. Verify REAPER's behavior in normal insert / Undo / Redo workflows before depending on any specific Undo-history grouping.

The monitor uses REAPER `defer()` and scans at most about eight times per second. The GUI requires ReaImGui 0.10 or newer; the monitor/core do not. Both scripts use the current REAPER project and do not require editing project files.

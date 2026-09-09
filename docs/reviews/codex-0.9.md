# Codex bug check before 0.9.0 (2026-09-09)

Run with `codex exec --sandbox read-only` at commit 3019198. Every finding below was fixed in the following commit; see CHANGELOG.md.

Reviewed every repository file at `3019198`, including the new `--boot` installer. No files changed. `node --test tests/` and Bash syntax checks passed.

1. **High — Dragging the tray erases saved tray-icon pins.** [BarModel.js:463](/home/pi/Projects/menu.bar.overload/nixfred.menubar-overload/BarModel.js:463)  
   **Trigger:** Reorder a tray whose entry contains `pinned: ["steam", …]`, or pin it through the CLI.  
   **Failure:** Carousel pinning overwrites or deletes the same `pinned` property that the tray uses for its icon list. Even moving the tray between unpinned positions deletes that array, and the result is persisted.  
   **Fix:** Store carousel placement under a separate key, such as `carouselPin`, and update the CLI and drag handlers accordingly. Preserve existing tray arrays during migration.

2. **Medium — Pin-only changes do not move widgets between zones.** [Bar.qml:636](/home/pi/Projects/menu.bar.overload/nixfred.menubar-overload/Bar.qml:636)  
   **Trigger:** Run `menubar-overload pin <id> inner`, or make a drop that changes pinning without changing entry order.  
   **Failure:** `inlineSettingsDelta` accepts the change, but `applySettingsDelta` only mutates the nested layout array and widget settings. The zone bindings receive no notification, so the widget stays in its previous zone until a structural rebuild. This follows Qt’s documented [notification behavior for JavaScript objects](https://doc.qt.io/QT-6/qml-var.html).  
   **Fix:** Treat changes in `pinKind` as structural and rebuild the affected zone models.

3. **Medium — Live settings revert when overflow state changes.** [Bar.qml:642](/home/pi/Projects/menu.bar.overload/nixfred.menubar-overload/Bar.qml:642)  
   **Trigger:** Change a widget setting, then resize the available space until its strip starts or stops overflowing.  
   **Failure:** The update changes `activeItem.settings` but leaves `slot.entry` stale. Changing `stripScrolling` recomputes `moduleSettings` from that old entry and reinjects the previous settings. Directly assigning settings also bypasses the scrolling-specific `stretch: false` override.  
   **Fix:** Update the matching slot’s `entry` and let `moduleSettings` perform the settings injection.

4. **Medium — Scrolling on a smaller monitor depends on the first monitor.** [Bar.qml:255](/home/pi/Projects/menu.bar.overload/nixfred.menubar-overload/Bar.qml:255)  
   **Trigger:** The first registered monitor’s strip fits, while another monitor’s equivalent strip overflows.  
   **Failure:** `scrollWheel` checks `deckFor(region)`, which always returns the first built deck. It rejects scrolling on the overflowing monitor. Home calculations likewise use the first deck’s geometry.  
   **Fix:** Pass the originating deck into pointer-driven operations; resolve IPC operations against the focused monitor and calculate home using that monitor’s viewport.

5. **Medium — Widgets wrap while still inside the visible viewport.** [BarModel.js:293](/home/pi/Projects/menu.bar.overload/nixfred.menubar-overload/BarModel.js:293)  
   **Trigger:** A strip barely overflows, so `ring - widgetWidth < viewport`.  
   **Failure:** Recycling a single widget between ring positions causes visible jumps. With widths `[100,100,100]`, viewport `280`, and ring `314`, scrolling from offset `100` to `101` moves the first widget from `x=-100` to `x=213`: it suddenly appears well inside the opposite edge.  
   **Fix:** Ensure recycling occurs outside the viewport—for unscaled widgets, require `ring >= viewport + max(widths)`—or provide a visual seam copy without duplicating widget services.

6. **Medium — Explicitly fixed-width widgets can prevent overflow detection.** [Bar.qml:2286](/home/pi/Projects/menu.bar.overload/nixfred.menubar-overload/Bar.qml:2286)  
   **Trigger:** Configure a widget such as Beatdeck with `stretch: false`, width `220`, minimum width `96`, and only `150` pixels available.  
   **Failure:** The presence of `stretchedWidth` still classifies it as shrinkable. The overflow decision uses `96`, although the widget remains `220` pixels wide, leaving the strip flat and overlapping neighboring content.  
   **Fix:** Respect explicitly disabled stretching when calculating minimum width. Distinguish the saved setting from the temporary override applied during scrolling.

7. **Medium — Magnification leaves visibility flags incorrect.** [BarModel.js:342](/home/pi/Projects/menu.bar.overload/nixfred.menubar-overload/BarModel.js:342)  
   **Trigger:** Magnification pushes initially visible widgets beyond a viewport edge.  
   **Failure:** `on` and `shown` are calculated before scaling and repacking and never updated. A reproduced case with twenty 10-pixel slots reports the first slot fully shown even though its right edge is approximately `-2.87`. Panel navigation, summon routing, and drop targeting consequently treat hidden widgets as visible.  
   **Fix:** Recompute both flags from the final transformed bounds after repacking.

8. **Medium — A pending summon survives a hide request.** [Bar.qml:792](/home/pi/Projects/menu.bar.overload/nixfred.menubar-overload/Bar.qml:792)  
   **Trigger:** Summon an off-screen panel, then hide it before the scroll animation finishes.  
   **Failure:** `hideBarWidget` closes the widget but leaves `pendingSummon` and `summonTimer` armed. The timer subsequently opens it again. Summoning an already-visible second panel can similarly leave the first request pending.  
   **Fix:** Cancel matching pending requests on hide, supersede them on every new summon, and invalidate them when their slot is destroyed.

9. **Medium — Offline installation reports success after a failed configuration edit.** [install.sh:51](/home/pi/Projects/menu.bar.overload/install.sh:51)  
   **Trigger:** Run `--use`, `--boot`, or `--ensure` without a reachable shell when `shell.json` is absent or invalid.  
   **Failure:** The failing `jq` is the left side of `&&`, so `set -e` does not stop execution. The installer prints that the bar is active and exits successfully without selecting it. Reproduced with an absent configuration file.  
   **Fix:** Explicitly propagate edit failures, clean up the temporary file, and initialize an absent configuration from Omarchy’s defaults.

10. **Low — Width animation moves neighbors without resizing the widget.** [Bar.qml:2116](/home/pi/Projects/menu.bar.overload/nixfred.menubar-overload/Bar.qml:2116)  
    **Trigger:** A carousel widget grows dynamically.  
    **Failure:** `reportedWidth` animates, but the actual slot width immediately follows `implicitWidth`. If a widget grows from 40 to 80 pixels, its neighbor initially remains at `x=40`, producing overlap during the animation.  
    **Fix:** Use the same animated width for rendered slot geometry and layout measurements, or reserve the full new width immediately.

11. **Low — The boot service breaks for checkout paths containing spaces.** [install.sh:79](/home/pi/Projects/menu.bar.overload/install.sh:79)  
    **Trigger:** Run `--boot` from a checkout such as `/home/pi/Projects/MenuBar Overload`.  
    **Failure:** The generated `ExecStart` splits the executable path at whitespace, so the service cannot launch the installer.  
    **Fix:** Quote and escape the executable path according to [systemd command-line syntax](https://github.com/systemd/systemd/blob/main/man/systemd.service.xml), including literal `%` characters.

I would hold the 0.9 release. The passing model tests miss persistent tray-setting loss, broken live pinning, monitor-dependent scrolling, and several geometry and timing failures. Fix those paths and validate them inside omarchy-shell before release; this review did not exercise the complete live UI.

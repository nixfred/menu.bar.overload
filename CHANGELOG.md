# Changelog

## 0.9.0 — 2026-09-09

First packaged release.

- Left and right sections become carousel strips when their widgets no
  longer fit; a strip that fits stays flat and dormant.
- Endless ring scrolled by mouse wheel or trackpad, with easing; the
  widgets under the pointer swell and tilt like a macOS dock.
- Fading edges and breathing chevrons mark that there is more each way.
- A click holds a scrolled strip where it is; otherwise it drifts home after
  six idle seconds.
- Two pinned zones per side, off the carousel: the corner and the inner edge
  beside the center. Drag into a zone to pin, out to unpin, or use
  `menubar-overload pin`.
- Stretch widgets (Burn Bar, Beatdeck) shrink before a strip scrolls and
  hold their width while it does; width changes ease.
- Drops are zone-aware; drag and drop addresses entries by id and
  occurrence.
- Hotkey-summoned panels scroll their widget into view first.
- `menubar-overload` CLI, `install.sh --use` / `--boot`, node tests for the
  layout model.
- Pre-release bug check by Codex (docs/reviews/codex-0.9.md), all findings
  fixed: zones are stored under `zone`, not `pinned` (the tray's icon list
  lives there); zone changes apply live; settings deltas keep the slot's
  entry honest; wheel and home use the deck on the pointer's monitor; the
  ring is long enough that recycling happens off screen; explicit
  `stretch: false` counts as fixed width; visibility follows the magnified
  bounds; a hidden panel cancels its pending summon; the installer fails
  loudly and initialises a missing config; the boot unit quotes its path.
- Pre-release bug check by Grok (docs/reviews/grok-0.9.md), all findings
  fixed: the shared scroll state is a distance from home, so monitors with
  different viewports agree on home and each takes the short way round its
  own ring; a strip shrinks at once and only grows with easing, so it never
  paints over a center that just grew; the installer compares real paths
  and quotes them; the CLI cleans up its temp files on failure.

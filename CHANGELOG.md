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

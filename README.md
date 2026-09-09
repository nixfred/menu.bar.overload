# MenuBar Overload

The Omarchy bar with an endless carousel on each side, so the bar can hold
more plugins than fit on the screen.

The left and right sections become strips that scroll inside the room the
center section leaves. A strip whose widgets fit is laid out exactly as
before and stays dormant. One that overflows becomes a ring: every widget
stays mounted, so timers, IPC handlers and services keep running, and the
ones that do not fit sit past the edge of a clipped viewport until you scroll
them in. The center section never scrolls.

- Scroll with the mouse wheel or a two-finger trackpad swipe anywhere over a
  strip. Wheel down or swipe right moves the widgets right to left; wheel up
  or swipe left brings them back. The motion eases, and the ring loops
  forever in both directions.
- The widgets under the pointer swell and tilt in 3D like a macOS dock as
  they pass, and spread apart so they never overlap.
- The fading edges and breathing chevrons at both ends say there is more
  that way. Click a chevron to scroll a notch, right-click it to go home.
- A scrolled strip drifts back home after 6 idle seconds. Click any widget on
  it and it stays where you left it until you scroll again.
- Pinned widgets never join the carousel. They hold the bar's outer edges in
  layout order: the launcher and workspaces on the far left, the bell, power
  and control center on the far right. Drag a widget into a corner zone to
  pin it (the zones light up while you drag; an empty corner shows a well to
  drop into), drag it back onto a strip to unpin it, or use
  `menubar-overload pin <id>` / `omarchy bar set <id> pinned true`.
- Widgets that stretch to fill free room (Burn Bar, Beatdeck) keep doing so
  on a flat strip. The strip only starts scrolling when even their minimum
  widths do not fit, and while it scrolls they sit at their configured width
  instead of chasing a moving edge. Width changes ease rather than jump.
- Drag and drop reordering still works, and a panel summoned by hotkey
  (`omarchy-shell shell summon <id>`) scrolls its widget into view first.

The right strip is home showing its tail, so the widgets in the corner stay
in the corner and scrolling reveals the ones nearer the center. The left
strip is home showing its head. New plugins land in the hidden part of either
strip, which is exactly where `omarchy plugin enable` puts them on the right;
`menubar-overload add <id> left` does the same for the left.

## Install

```bash
git clone https://github.com/nixfred/menu.bar.overload ~/Projects/menu.bar.overload
~/Projects/menu.bar.overload/install.sh --use
```

`install.sh` symlinks `nixfred.menubar-overload` into
`~/.config/omarchy/plugins/` and, with `--use`, makes it the active bar. To go
back to the previous bar: `omarchy bar use pi.bar` (or `omarchy bar reset`
for the stock one).

The bar is a clone of Omarchy's `omarchy.bar` engine as it stands in
`~/.config/omarchy/plugins/pi.bar` (the "Locked Bar": fixed to the top edge,
no transparency toggle, no drag-to-move gestures, no wheel-to-volume on the
microphone). Everything else in this repo is the carousel.

## Driving it

`bin/menubar-overload` wraps the bar's IPC target and settings:

```
menubar-overload                          state of both strips
menubar-overload scroll left|right [PX]   scroll PX pixels (negative = back)
menubar-overload home [left|right]        scroll home
menubar-overload hold left|right on|off   keep a strip where it is / let it drift
menubar-overload pin <plugin> [on|off]    pin a widget to the outer edge, out of the carousel
menubar-overload pinned                   list pinned widgets
menubar-overload add <plugin> [left|right]
menubar-overload set wheel on|off
menubar-overload set invert-wheel on|off
menubar-overload set step <px>            pixels per wheel notch (64)
menubar-overload set animation <ms>       easing per scroll (240, 0 = instant)
menubar-overload set return <seconds>     drift home after N idle seconds (6, 0 = never)
menubar-overload set magnify <factor>     dock magnification (0.35, 0 = off)
menubar-overload set radius <px>          reach of the magnification (84)
menubar-overload set tilt <degrees>       3D tilt at the edge of the reach (16)
menubar-overload set edge-hints on|off    fading edges and chevrons
```

The raw IPC surface, for keybindings:

```
omarchy-shell menubar-overload scroll right 64
omarchy-shell menubar-overload scroll right -64
omarchy-shell menubar-overload home all
omarchy-shell menubar-overload status
```

Settings live in the `bar.carousel` block of `~/.config/omarchy/shell.json`:

```json
"carousel": { "wheel": true, "invertWheel": false, "step": 64, "animation": 240,
              "returnAfter": 6, "magnify": 0.35, "radius": 84, "tilt": 16,
              "edgeHints": true }
```

On a strip that overflows, the wheel scrolls the strip even over a widget
that normally takes the wheel (volume, brightness); hold Ctrl to reach the
widget. When everything fits, widgets keep the wheel as before.

## How it works

`Bar.qml` replaces the bar's `ModuleList` for the side sections with a
`ScrollDeck`. Each slot reports its width; `BarModel.ringView` turns the
widths, the viewport, the scroll offset and the pointer position into an x,
scale and tilt for every entry. The offset is a plain number the deck eases
toward a target the bar shares across monitors, so a scroll is a translation
and the ring wraps by arithmetic. Magnified widgets are re-packed outward from
the one nearest the pointer at their scaled widths, which is what keeps them
from overlapping.

Drag and drop addresses entries as `{id, occurrence}` references rather than
names, so layouts with repeated ids (spacers) stay unambiguous.

Bar plugin code is not hot-reloaded by the shell the way widget plugins are;
after editing `Bar.qml` run `omarchy restart shell`.

Tests for the pure layout model: `node --test tests/`.

# Grok bug check before 0.9.0 (2026-09-09)

Run with `grok --always-approve` on a scratch copy at commit 65708c8. Every finding below was fixed in the following commit; see CHANGELOG.md.

`node --test tests/` passed 16/16. The defects below are from reading the QML, model, CLI, and installer, plus extra Node probes of `BarModel` edge cases that the tests do not cover. I did not run any Qt GUI binary.

**High — shared right-strip home is per-monitor, the offset is not**
`nixfred.menubar-overload/Bar.qml:125`, `203`, `232`, `2060`, `2069`

Scroll offsets live on the bar root so every monitor shows the same run (`offsets.left` / `offsets.right`). Home for a right strip is `total - viewport`, and `viewport` is the room that monitor’s center section leaves. `isHome`, `scrollHome`, IPC `home`, `carouselStatus`, and the idle-return timer all call `deckFor(region)` with no window, so they use whichever deck registered first.

What goes wrong:
- Two screens of different widths (laptop plus a monitor) get different right `homeOffset` values. Each deck’s `onHomeOffsetChanged` writes its own home into the shared offset whenever the strip is considered home (center peek, widgets finishing their first measure, overflow flipping on). They overwrite each other; the last handler wins.
- If the first-registered screen’s right strip still fits, `isHome` is always true. The other screen’s overflowing strip never drifts home.
- The advertised behavior — right-corner widgets stay in the corner — holds only on the monitor whose home last won.

Fix: store a shared delta from home (0 means home on every screen), and have each deck apply `homeOffset + delta` locally. Drive `isHome` / idle return / IPC `home` from that delta, not from one deck’s pixel home. Do not have every monitor write `setOffset` from its own `homeOffset`.

**Medium — overflowing strip width eases, so a shrinking center overlaps the carousel**
`nixfred.menubar-overload/Bar.qml:2016` and `2100`

When a strip overflows, `width` is the live `budget` (room beside the center). A `Behavior` on `width` always eases that to the new value over `scrollAnimationMs` (240 by default).

Trigger: hover the center indicators so they peek, or anything else that suddenly shrinks `contentLeft` / `contentRight` (clock format, a stretch widget, a resolution change).

What goes wrong: budget drops immediately, strip width catches up 240 ms later. During that window the strip is wider than the gap and paints over the center. The widget-level `reportedWidth` behavior already refuses to ease growth so neighbors are never covered; the strip itself does the opposite.

Fix: apply budget immediately while overflowing. Keep width easing only for the flat-to-ring (or ring-to-flat) transition, the way `reportedWidth` eases shrinks but not growth.

**Low — `install.sh` re-run can refuse a correct link**
`install.sh:23`

The first run does `ln -s "$here/$id"`. A later run compares `readlink -f "$target"` (physical) to `"$here/$id"` where `here` is `pwd` without `-P` (logical).

Trigger: the clone lives behind a symlink, or you invoke `install.sh` through one. First install succeeds; the next `--use` / `--boot` / `--ensure` prints `refusing: ... links elsewhere`.

Fix: compare `readlink -f "$target"` to `readlink -f "$here/$id"`. Quote `$target` and `$config` in the `[[ -L ]]` / `[[ -e ]]` / `[[ -s ]]` tests while you are there (`HOME` with spaces currently splits).

**Low — `menubar-overload set` leaks temp files on failure**
`bin/menubar-overload:43`

`write_config` makes two `mktemp` files, then `jq` / `omarchy-shell-config-edit apply` under `set -e`, with `rm` only on the success path. A failed snapshot, jq, or apply leaves the files in `/tmp`. `install.sh` already deletes them in the failure branch; the CLI does not.

Fix: `trap 'rm -f "$base" "$edited"' EXIT` after the `mktemp` calls, matching `install.sh`.

**Inspected and not listed**
`ringView` wrap, seam shift, `ringLength` off-screen recycle, and magnification packing match the tests and extra probes. `moveEntryByRef` / `setEntryPinned` keep spacer occurrences straight, leave the tray’s `pinned` icon array alone, and promote string entries only when a zone is actually written. CLI `pin` passes `'"outer"'` because `setBarWidget` JSON-parses the value; that is correct. `jq -e` on `.bar.carousel.wheel = false` returns the whole object, not `false`. `offsetToReveal` will snap an already-fully-visible middle widget to an edge, but the only caller (`summonBarWidget`) runs it when `shown` is false, which is the case you want. Left-strip home is 0 on every monitor, so the shared-offset bug is a right-strip / mismatched-viewport problem.

**Verdict**

On one display the carousel model, pinning, and CLI are in good shape for 0.9: the Node tests pass, drop/pin persistence is coherent, and I did not find a binding loop or a jq quoting hole. Do not ship that as 0.9 until the shared right-strip home is per-monitor. Dual-width setups are normal on this desktop, and the bug breaks the main right-strip promise (corner widgets stay put, idle return works). The width-easing overlap is worth fixing in the same pass; it shows up on a single monitor as soon as the center indicators peek.


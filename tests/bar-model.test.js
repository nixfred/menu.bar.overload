// Run: node --test tests/
const test = require("node:test")
const assert = require("node:assert/strict")
const M = require("../nixfred.menubar-overload/BarModel.js")

const e = (id, extra) => Object.assign({ id }, extra || {})

test("cumulativeWidths ignores junk and negative widths", () => {
  assert.deepEqual(M.cumulativeWidths([10, 20, undefined, -5, 5]), [0, 10, 30, 30, 30, 35])
  assert.deepEqual(M.cumulativeWidths(null), [0])
  assert.equal(M.countNonZero([0, 5, 0, 7], 0, 4), 2)
})

test("wrapOffset, homeOffset and nearestHome", () => {
  assert.equal(M.wrapOffset(-10, 100), 90)
  assert.equal(M.wrapOffset(250, 100), 50)
  assert.equal(M.wrapOffset(5, 0), 0)
  assert.equal(M.homeOffset(500, 300, false), 0)
  assert.equal(M.homeOffset(500, 300, true), 200)
  assert.equal(M.homeOffset(200, 300, true), 0)
  assert.equal(M.nearestHome(1010, 0, 1000), 1000)
  assert.equal(M.nearestHome(-490, 0, 1000), 0)
  assert.equal(M.nearestHome(1400, 200, 1000), 1200)
})

test("flat strip when everything fits: no wrap, no magnification", () => {
  const v = M.ringView([40, 40, 40], 200, 212, 0, false, 60, 0.35, 90, 14)
  assert.deepEqual(v.x, [0, 40, 80])
  assert.deepEqual(v.s, [1, 1, 1])
  assert.deepEqual(v.shown, [true, true, true])
})

test("ring positions wrap and the seam item enters from the left", () => {
  const w = [50, 50, 50, 50]          // total 200, ring 212 with a 12px seam
  let v = M.ringView(w, 120, 212, 0, true, null, 0, 0, 0)
  assert.deepEqual(v.x, [0, 50, 100, 150])
  assert.deepEqual(v.on, [true, true, true, false])
  assert.deepEqual(v.shown, [true, true, false, false])
  v = M.ringView(w, 120, 212, 30, true, null, 0, 0, 0)
  assert.deepEqual(v.x, [-30, 20, 70, 120])
  assert.deepEqual(v.on, [true, true, true, false])
  // Item 0 has gone round: at offset 190 it sits at ring - 190 = 22
  v = M.ringView(w, 120, 212, 190, true, null, 0, 0, 0)
  assert.equal(v.x[0], 22)
  // Item 3 straddles the seam at offset 165: 150 - 165 = -15
  v = M.ringView(w, 120, 212, 165, true, null, 0, 0, 0)
  assert.equal(v.x[3], -15)
  assert.equal(v.on[3], true)
})

test("magnification peaks under the pointer, falls off and spreads neighbours", () => {
  const w = [40, 40, 40, 40, 40]
  const v = M.ringView(w, 200, 212, 0, true, 100, 0.5, 60, 20)
  // item 2 is centred at 100: full magnification, no tilt
  assert.ok(Math.abs(v.s[2] - 1.5) < 1e-9)
  assert.ok(Math.abs(v.a[2]) < 1e-9)
  // neighbours at 40px: partial, tilted opposite ways
  assert.ok(v.s[1] > 1 && v.s[1] < 1.5)
  assert.ok(Math.abs(v.s[1] - v.s[3]) < 1e-9)
  assert.ok(v.a[1] < 0 && v.a[3] > 0)
  // outside the radius: untouched
  assert.equal(v.s[0], 1)
  assert.equal(v.s[4], 1)
  // anchor stays put, neighbours pushed apart so scaled boxes do not overlap
  assert.ok(Math.abs((v.x[2] + 20) - 100) < 1e-9)
  for (let i = 1; i < 5; i++) {
    const rightEdgePrev = v.x[i - 1] + 20 + 20 * v.s[i - 1]
    const leftEdge = v.x[i] + 20 - 20 * v.s[i]
    assert.ok(leftEdge >= rightEdgePrev - 1e-9, `overlap between ${i - 1} and ${i}`)
  }
})

test("no magnification without a pointer or when not overflowing", () => {
  const w = [40, 40, 40]
  assert.deepEqual(M.ringView(w, 80, 132, 0, true, null, 0.5, 60, 20).s, [1, 1, 1])
  assert.deepEqual(M.ringView(w, 200, 132, 0, false, 40, 0.5, 60, 20).s, [1, 1, 1])
})

test("offsetToReveal picks the shorter way round", () => {
  const w = [50, 50, 50, 50]          // ring 212, viewport 120
  // at home (0), item 3 at 150: flush right needs +80, but coming round the
  // seam so it lands flush left needs only -62
  assert.equal(M.offsetToReveal(w, 120, 212, 0, 3), -62)
  // already visible item 0 at home: leading edge flush left is 0
  assert.equal(M.offsetToReveal(w, 120, 212, 0, 0), 0)
  // from offset 200, item 0 (cum 0): nearest equivalent is 212
  assert.equal(M.offsetToReveal(w, 120, 212, 200, 0), 212)
})

test("entry references count same-id occurrences", () => {
  const S = e("omarchy.spacer")
  const list = [e("a"), S, e("b"), S, e("a")]
  assert.deepEqual(M.entryRef(list, 0), { id: "a", occurrence: 0 })
  assert.deepEqual(M.entryRef(list, 3), { id: "omarchy.spacer", occurrence: 1 })
  assert.deepEqual(M.entryRef(list, 4), { id: "a", occurrence: 1 })
  assert.equal(M.entryRef(list, 5), null)
  assert.equal(M.indexOfRef(list, { id: "omarchy.spacer", occurrence: 1 }), 3)
  assert.equal(M.indexOfRef(list, { id: "zzz", occurrence: 0 }), -1)
})

test("references survive tray pinning", () => {
  const S = e("omarchy.spacer")
  const raw = [e("x"), e("omarchy.tray"), S, e("y"), S]
  const live = M.pinTrayToInner(raw, "right")
  assert.equal(live[0].id, "omarchy.tray")
  const ref = M.entryRef(live, live.findIndex(x => x.id === "y"))
  assert.equal(M.indexOfRef(raw, ref), 3)
  assert.equal(M.indexOfRef(raw, M.entryRef(live, 4)), 4)
})

const ids = list => list.map(x => (typeof x === "string" ? x : x.id))
function layout(left, right) { return { left, center: [], right } }

test("moveEntryByRef moves before a target and appends on null", () => {
  const l = layout([e("a"), e("b"), e("c")], [e("r")])
  assert.deepEqual(M.moveEntryByRef(l, "left", { id: "c", occurrence: 0 }, "left", { id: "a", occurrence: 0 }), { index: 0, moved: true })
  assert.deepEqual(ids(l.left), ["c", "a", "b"])
  assert.deepEqual(M.moveEntryByRef(l, "left", { id: "a", occurrence: 0 }, "right", null), { index: 1, moved: true })
  assert.deepEqual(ids(l.left), ["c", "b"])
  assert.deepEqual(ids(l.right), ["r", "a"])
})

test("moveEntryByRef reports no-ops for the same gap but still says where", () => {
  const l = layout([e("a"), e("b"), e("c")], [])
  assert.deepEqual(M.moveEntryByRef(l, "left", { id: "b", occurrence: 0 }, "left", { id: "b", occurrence: 0 }), { index: 1, moved: false })
  assert.deepEqual(M.moveEntryByRef(l, "left", { id: "b", occurrence: 0 }, "left", { id: "c", occurrence: 0 }), { index: 1, moved: false })
  assert.deepEqual(ids(l.left), ["a", "b", "c"])
})

test("moveEntryByRef handles duplicates and missing regions", () => {
  const S = e("omarchy.spacer")
  const l = { left: [e("a"), S, e("b"), S, e("c")] }
  assert.equal(M.moveEntryByRef(l, "left", { id: "a", occurrence: 0 }, "left", { id: "omarchy.spacer", occurrence: 1 }).moved, true)
  assert.deepEqual(ids(l.left), ["omarchy.spacer", "b", "a", "omarchy.spacer", "c"])
  assert.equal(M.moveEntryByRef(l, "left", { id: "nope", occurrence: 0 }, "right", null).index, -1)
  assert.equal(M.moveEntryByRef(l, "left", { id: "c", occurrence: 0 }, "right", null).moved, true)
  assert.deepEqual(ids(l.right), ["c"])
})

test("pinKind reads outer, inner and none", () => {
  assert.equal(M.pinKind(e("a", { pinned: true })), "outer")
  assert.equal(M.pinKind(e("a", { pinned: "outer" })), "outer")
  assert.equal(M.pinKind(e("a", { pinned: "inner" })), "inner")
  assert.equal(M.pinKind(e("a")), "")
  assert.equal(M.pinKind("a"), "")
})

test("setEntryPinned sets zones, clears and promotes string entries", () => {
  const l = { left: ["a", e("b"), e("c", { pinned: true }), e("d", { pinned: "inner" })] }
  assert.equal(M.setEntryPinned(l, "left", 0, "outer"), true)
  assert.deepEqual(l.left[0], { id: "a", pinned: true })
  assert.equal(M.setEntryPinned(l, "left", 1, ""), false)          // already on the carousel
  assert.equal(M.setEntryPinned(l, "left", 1, "inner"), true)
  assert.deepEqual(l.left[1], { id: "b", pinned: "inner" })
  assert.equal(M.setEntryPinned(l, "left", 2, ""), true)
  assert.deepEqual(l.left[2], { id: "c" })
  assert.equal(M.setEntryPinned(l, "left", 3, "inner"), false)     // unchanged
  assert.equal(M.setEntryPinned(l, "left", 7, true), false)
  assert.equal(M.setEntryPinned(l, "nope", 0, true), false)
})

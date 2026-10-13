function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function normalizePosition(value) {
  var next = String(value || "").trim()
  return /^(top|bottom|left|right)$/.test(next) ? next : "top"
}

function entrySettings(entry) {
  if (!isPlainObject(entry)) return {}
  var copy = {}
  for (var key in entry) {
    if (key === "id") continue
    copy[key] = entry[key]
  }
  return copy
}

function entryId(entry) {
  if (typeof entry === "string") return entry
  if (isPlainObject(entry)) {
    var id = entry["id"]
    if (id !== undefined && id !== null && String(id) !== "") return String(id)
  }
  return ""
}

function pinTrayToInner(entries, section) {
  var trayEntry = null
  var result = []
  var values = Array.isArray(entries) ? entries : []
  for (var i = 0; i < values.length; i++) {
    if (entryId(values[i]) === "omarchy.tray") trayEntry = values[i]
    else result.push(values[i])
  }
  if (trayEntry) {
    if (section === "right") result.unshift(trayEntry)
    else result.push(trayEntry)
  }
  return result
}

function moduleString(entry, key, fallback) {
  var settings = entrySettings(entry)
  var value = settings[key]
  return value === undefined || value === null ? fallback : String(value)
}

function entryIndex(entries, name) {
  if (!Array.isArray(entries)) return -1
  for (var i = 0; i < entries.length; i++) {
    if (entryId(entries[i]) === name) return i
  }
  return -1
}

function entriesBefore(entries, name) {
  var index = entryIndex(entries, name)
  return index <= 0 ? [] : entries.slice(0, index)
}

function entriesAfter(entries, name) {
  var index = entryIndex(entries, name)
  return index === -1 ? [] : entries.slice(index + 1)
}

// A shell.json write that only changes inline widget settings (the battery
// percentage toggle, a clock format change) must not rebuild the bar.
// Compare two normalized layouts: when the structure is unchanged — same
// entry ids in the same order per region — return the settings-only changes
// as {region, index, entry}. Return null when the change is structural, or
// touches an entry a live settings push cannot safely reach: custom modules
// read their entry directly rather than an injected settings property, and
// a duplicated id makes the push ambiguous.
function inlineSettingsDelta(current, next) {
  if (!isPlainObject(current) || !isPlainObject(next)) return null
  var regions = ["left", "center", "right"]
  var counts = {}
  for (var r = 0; r < regions.length; r++) {
    var entries = Array.isArray(next[regions[r]]) ? next[regions[r]] : []
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      counts[id] = (counts[id] || 0) + 1
    }
  }
  var changes = []
  for (var s = 0; s < regions.length; s++) {
    var region = regions[s]
    var a = Array.isArray(current[region]) ? current[region] : []
    var b = Array.isArray(next[region]) ? next[region] : []
    if (a.length !== b.length) return null
    for (var j = 0; j < a.length; j++) {
      if (entryId(a[j]) !== entryId(b[j])) return null
      if (JSON.stringify(a[j]) === JSON.stringify(b[j])) continue
      if (customModuleType(a[j]) || customModuleType(b[j])) return null
      if (counts[entryId(b[j])] > 1) return null
      changes.push({ region: region, index: j, entry: b[j] })
    }
  }
  return changes
}

function expandPath(value, home) {
  var path = String(value || "")
  if (path === "") return ""
  if (path.indexOf("~/") === 0) return home + path.substring(1)
  if (path.indexOf("$HOME/") === 0) return home + path.substring(5)
  return path
}

function customModuleSafeName(name) {
  var value = String(name || "")
  return value !== "" && value.indexOf("..") === -1 && value[0] !== "/"
}

function customModuleType(entry) {
  var settings = entrySettings(entry)
  var type = String(settings.type || "")
  if (type) return type
  if (settings.exec) return "command"
  if (settings.source) return "qml"
  return ""
}

function customModulePath(entry, home, configDir) {
  var settings = entrySettings(entry)
  var name = entryId(entry)
  var source = settings.source ? expandPath(settings.source, home) : ""
  if (!source && customModuleSafeName(name))
    source = String(configDir || "") + "/bar/modules/" + String(name) + ".qml"
  return source
}

// A center module is mounted twice once an anchor is set: the copy that is
// actually drawn, and a zero-size placeholder holding its place in the flow
// beside the anchor. Panel routing has to pick the drawn one — it is the only
// one that can anchor a popup, carry the open-panel mark, or be found again
// by switchPanelFrom — and fall back to the placeholder only when nothing is
// on screen. The order the two are registered in is not stable across a live
// bar reconfiguration, so picking the first match is not good enough.
function isDrawnSlot(slot) {
  return !!slot && slot.visible === true && slot.width > 0 && slot.height > 0
}

function pickDrawnSlot(slots) {
  var placeholder = null
  var list = slots || []
  for (var i = 0; i < list.length; i++) {
    if (!list[i]) continue
    if (isDrawnSlot(list[i])) return list[i]
    if (!placeholder) placeholder = list[i]
  }
  return placeholder
}

// A bar surface is built per monitor, so a panel hotkey has several live
// copies of the same widget to route to, and the panel opens on whichever
// monitor's copy answers. Candidates are `{ slot, screenName, opened }`.
//
// An open copy wins first: hide and toggle have to reach the panel the user
// can actually see, wherever it was opened from. Otherwise the focused
// monitor's copy wins, so a summon lands where the user is working instead of
// on whichever output registered its slot first. Neither narrowing applies on
// a single monitor, or when the focused output has no bar of its own.
function pickPanelSlot(candidates, focusedScreen) {
  var rows = Array.isArray(candidates) ? candidates : []
  var pool = rows.filter(function(row) { return row && row.opened === true })
  if (pool.length === 0) pool = rows.filter(function(row) { return !!row })

  var focused = String(focusedScreen || "")
  if (focused) {
    var onFocused = pool.filter(function(row) { return row.screenName === focused })
    if (onFocused.length > 0) pool = onFocused
  }

  return pickDrawnSlot(pool.map(function(row) { return row.slot }))
}

// Resolve a pointer anywhere along the bar to the closest insertion edge.
// Requiring the pointer to sit inside another widget makes the empty space
// around a centered group a dead zone, even though it visually reads as the
// most natural place to drop.
function nearestDropTarget(candidates, point, vertical) {
  var rows = Array.isArray(candidates) ? candidates : []
  var axis = vertical ? Number(point && point.y) : Number(point && point.x)
  if (!isFinite(axis)) return null

  var best = null
  var bestDistance = Infinity
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (!row || !row.slot) continue

    var start = Number(vertical ? row.y : row.x)
    var size = Number(vertical ? row.height : row.width)
    if (!isFinite(start) || !isFinite(size) || size <= 0) continue

    var beforeDistance = Math.abs(axis - start)
    var afterDistance = Math.abs(axis - (start + size))
    var after = afterDistance < beforeDistance
    var distance = after ? afterDistance : beforeDistance
    if (distance < bestDistance) {
      best = { slot: row.slot, after: after }
      bestDistance = distance
    }
  }
  return best
}

// ------------------------------------------------------------- carousel
//
// MenuBar Overload lays each side section out as an endless ring of widgets
// that scrolls inside a viewport: the room the center section leaves. Widths
// are measured from the live slots. `ringView` turns widths, viewport, scroll
// offset and pointer position into an x, scale and tilt for every entry, so a
// scroll is a pure translation and the dock-style magnification is a
// function of where the pointer is. Zero-width entries (widgets that hide
// themselves) cost nothing.

function cumulativeWidths(widths) {
  var list = Array.isArray(widths) ? widths : []
  var cum = [0]
  for (var i = 0; i < list.length; i++) {
    var w = Number(list[i])
    cum.push(cum[i] + (isFinite(w) && w > 0 ? w : 0))
  }
  return cum
}

function countNonZero(widths, from, to) {
  var list = Array.isArray(widths) ? widths : []
  var count = 0
  for (var i = Math.max(0, from); i < Math.min(to, list.length); i++) {
    if (Number(list[i]) > 0) count++
  }
  return count
}

// Wrap an offset onto [0, ring).
function wrapOffset(offset, ring) {
  var r = Number(ring) || 0
  if (r <= 0) return 0
  var v = Number(offset) || 0
  return ((v % r) + r) % r
}

// The scroll offset that is home: the head flush left, or the tail flush
// right for a deck that is home showing its end.
function homeOffset(total, viewport, fromEnd) {
  if (!fromEnd) return 0
  return Math.max(0, (Number(total) || 0) - (Number(viewport) || 0))
}

// The offset equivalent to `home` that is nearest to `offset` on the ring,
// so drifting home takes the short way round.
function nearestHome(offset, home, ring) {
  var r = Number(ring) || 0
  if (r <= 0) return home
  var k = Math.round(((Number(offset) || 0) - home) / r)
  return home + k * r
}

// The ring circumference. At least the seam gap past the total, and never
// so short that a widget wraps from one edge to the other while both
// positions are inside the viewport: recycling must happen off screen.
function ringLength(total, viewport, loopGap, widths) {
  var list = Array.isArray(widths) ? widths : []
  var widest = 0
  for (var i = 0; i < list.length; i++) if (Number(list[i]) > widest) widest = Number(list[i])
  var t = Number(total) || 0
  var port = Number(viewport) || 0
  var gap = Number(loopGap) || 0
  return Math.max(t + gap, port + widest + gap)
}

// Everything the strip needs to draw one frame.
//   widths      measured slot widths, in entry order
//   viewport    visible width of the strip
//   ring        circumference: total width plus the seam gap
//   offset      scroll offset; entry i's leading edge sits at cum[i] - offset
//   overflowing false lays the strip out flat with no wrap and no magnification
//   focal       pointer x inside the strip, or null when not hovering
//   magnify     extra scale at the focal point (0.35 = 35% bigger)
//   radius      distance over which magnification falls to nothing
//   tilt        degrees of 3D tilt at the edge of the radius
// Returns { x, s, a, on, shown }: position, scale, tilt angle, "any part
// visible", "fully visible" per entry. Magnified widgets spread apart so they
// never overlap, anchored on the one closest to the pointer.
function ringView(widths, viewport, ring, offset, overflowing, focal, magnify, radius, tilt) {
  var list = Array.isArray(widths) ? widths : []
  var n = list.length
  var cum = cumulativeWidths(list)
  var view = { x: [], s: [], a: [], on: [], shown: [] }
  var visible = []
  var port = Math.max(0, Number(viewport) || 0)

  for (var i = 0; i < n; i++) {
    var w = Number(list[i]) > 0 ? Number(list[i]) : 0
    var p
    if (!overflowing) {
      p = cum[i]
    } else {
      p = wrapOffset(cum[i] - offset, ring)
      // Straddling the seam: draw it entering from the left instead.
      if (w > 0 && p > ring - w - 0.5) p -= ring
    }
    view.x.push(p)
    view.s.push(1)
    view.a.push(0)
    var on = w > 0 && p + w > 0.5 && p < port - 0.5
    view.on.push(on)
    view.shown.push(w > 0 && p >= -0.5 && p + w <= port + 0.5)
    if (on) visible.push(i)
  }

  var mag = Number(magnify) || 0
  var rad = Number(radius) || 0
  var hasFocal = focal !== null && focal !== undefined && isFinite(Number(focal))
  if (!overflowing || !hasFocal || mag <= 0 || rad <= 0 || visible.length === 0) return view

  var f = Number(focal)
  var anchor = -1
  var best = 1
  for (var v = 0; v < visible.length; v++) {
    var idx = visible[v]
    var center = view.x[idx] + list[idx] / 2
    var d = Math.abs(center - f) / rad
    if (d >= 1) continue
    var fall = 0.5 + 0.5 * Math.cos(Math.PI * d)
    view.s[idx] = 1 + mag * fall
    view.a[idx] = (Number(tilt) || 0) * Math.max(-1, Math.min(1, (center - f) / rad)) * fall
    if (view.s[idx] > best) { best = view.s[idx]; anchor = v }
  }
  if (anchor === -1) return view

  // Spread: keep the anchor's center, then pack neighbours outward at their
  // scaled widths so nothing overlaps.
  visible.sort(function(p, q) { return view.x[p] - view.x[q] })
  for (var k = 0; k < visible.length; k++) if (visible[k] === visibleAnchor(visible, view, list, f)) { anchor = k; break }
  var ai = visible[anchor]
  var c = view.x[ai] + list[ai] / 2
  var prev = c
  for (var r = anchor + 1; r < visible.length; r++) {
    var ir = visible[r], il = visible[r - 1]
    prev = prev + (list[il] * view.s[il] + list[ir] * view.s[ir]) / 2
    view.x[ir] = prev - list[ir] / 2
  }
  prev = c
  for (var l = anchor - 1; l >= 0; l--) {
    var jl = visible[l], jr = visible[l + 1]
    prev = prev - (list[jr] * view.s[jr] + list[jl] * view.s[jl]) / 2
    view.x[jl] = prev - list[jl] / 2
  }
  // Repacking can push a widget past an edge; judge visibility on the
  // final, scaled bounds so panel routing and drops see what is drawn.
  for (var q = 0; q < visible.length; q++) {
    var iq = visible[q]
    var half = list[iq] * view.s[iq] / 2
    var cq = view.x[iq] + list[iq] / 2
    view.on[iq] = cq + half > 0.5 && cq - half < port - 0.5
    view.shown[iq] = cq - half >= -0.5 && cq + half <= port + 0.5
  }
  return view
}

function visibleAnchor(visible, view, list, focal) {
  var bestIdx = visible[0]
  var bestDist = Infinity
  for (var v = 0; v < visible.length; v++) {
    var idx = visible[v]
    var center = view.x[idx] + list[idx] / 2
    var d = Math.abs(center - focal)
    if (d < bestDist) { bestDist = d; bestIdx = idx }
  }
  return bestIdx
}

// The offset that brings entry `index` fully into view with the least
// travel, used when a hotkey summons a panel whose widget is off the strip.
function offsetToReveal(widths, viewport, ring, offset, index) {
  var cum = cumulativeWidths(widths)
  var w = Number(widths[index]) > 0 ? Number(widths[index]) : 0
  var port = Math.max(0, Number(viewport) || 0)
  var current = Number(offset) || 0
  // Leading edge flush left, or trailing edge flush right; pick the nearer.
  var left = cum[index]
  var right = cum[index] + w - port
  var candidates = [left, right]
  var bestTarget = current
  var bestDist = Infinity
  for (var i = 0; i < candidates.length; i++) {
    var target = nearestHome(current, candidates[i], ring)
    var dist = Math.abs(target - current)
    if (dist < bestDist) { bestDist = dist; bestTarget = target }
  }
  return bestTarget
}

// ------------------------------------------------ entry references
//
// The bar and shell.json disagree on positions: normalization drops entries
// without an id and pinTrayToInner relocates the tray, so a live slot index
// is not a config index. Names alone are not enough either once a layout
// holds several entries with one id (spacers). An entry reference
// {id, occurrence} — "the second omarchy.spacer in this region" — survives
// both transformations, because neither changes the relative order of
// same-id entries.
function entryOccurrence(entries, index) {
  var list = Array.isArray(entries) ? entries : []
  if (index < 0 || index >= list.length) return -1
  var id = entryId(list[index])
  var occurrence = 0
  for (var i = 0; i < index; i++) {
    if (entryId(list[i]) === id) occurrence++
  }
  return occurrence
}

function entryRef(entries, index) {
  var list = Array.isArray(entries) ? entries : []
  if (index < 0 || index >= list.length) return null
  return { id: entryId(list[index]), occurrence: entryOccurrence(list, index) }
}

function indexOfRef(entries, ref) {
  if (!ref || !ref.id) return -1
  var list = Array.isArray(entries) ? entries : []
  var seen = 0
  for (var i = 0; i < list.length; i++) {
    if (entryId(list[i]) !== ref.id) continue
    if (seen === (ref.occurrence || 0)) return i
    seen++
  }
  return -1
}

// Move one entry inside a raw shell.json layout. `layout` is config.bar.layout
// (mutated in place). `toRef` names the entry the moved one lands in front of;
// null appends to the region. Returns { index, moved }: where the entry now
// sits in toRegion, and whether anything changed. index is -1 when the source
// was not found.
function moveEntryByRef(layout, fromRegion, fromRef, toRegion, toRef) {
  if (!isPlainObject(layout)) return { index: -1, moved: false }
  if (!Array.isArray(layout[fromRegion]) || !fromRef) return { index: -1, moved: false }
  if (!Array.isArray(layout[toRegion])) layout[toRegion] = []

  var fromEntries = layout[fromRegion]
  var toEntries = layout[toRegion]
  var fromIndex = indexOfRef(fromEntries, fromRef)
  if (fromIndex < 0) return { index: -1, moved: false }

  var toIndex = toRef ? indexOfRef(toEntries, toRef) : toEntries.length
  if (toIndex < 0) toIndex = toEntries.length
  if (fromRegion === toRegion && (toIndex === fromIndex || toIndex === fromIndex + 1)) return { index: fromIndex, moved: false }

  var moved = fromEntries.splice(fromIndex, 1)[0]
  if (fromRegion === toRegion && fromIndex < toIndex) toIndex--
  toEntries.splice(toIndex, 0, moved)
  return { index: toIndex, moved: true }
}

// Which zone an entry belongs to: "outer" (the bar's corner), "inner"
// (beside the center content), or "" for a widget on the carousel. The
// zone lives under its own key, `zone`, because `pinned` already means
// something to the tray widget (its list of pinned icon ids). Early 0.9
// builds wrote `pinned: true|"inner"`; those are still read, but only when
// the value is a boolean or string, never an array.
function pinKind(entry) {
  var settings = entrySettings(entry)
  var zone = settings.zone
  if (zone === "outer" || zone === "corner") return "outer"
  if (zone === "inner") return "inner"
  if (zone !== undefined && zone !== null) return ""
  var legacy = settings.pinned
  if (legacy === true || legacy === "true" || legacy === "outer") return "outer"
  if (legacy === "inner") return "inner"
  return ""
}

// Set one raw layout entry's zone. Returns true when it changed. String
// entries are promoted to objects first. A legacy boolean/string `pinned`
// is removed; an array under `pinned` (the tray's icons) is left alone.
function setEntryPinned(layout, region, index, kind) {
  if (!isPlainObject(layout) || !Array.isArray(layout[region])) return false
  var entries = layout[region]
  if (index < 0 || index >= entries.length) return false
  var entry = entries[index]
  if (typeof entry === "string") entry = { id: entry }
  if (!isPlainObject(entry)) return false
  var want = kind === true ? "outer" : String(kind || "")
  var was = pinKind(entry)
  if (typeof entry.pinned === "boolean" || typeof entry.pinned === "string") delete entry.pinned
  if (want === "outer" || want === "inner") entry.zone = want
  else delete entry.zone
  entries[index] = entry
  return was !== want
}

if (typeof module !== "undefined") {
  module.exports = {
    isDrawnSlot: isDrawnSlot,
    pickDrawnSlot: pickDrawnSlot,
    pickPanelSlot: pickPanelSlot,
    nearestDropTarget: nearestDropTarget,
    normalizePosition: normalizePosition,
    entrySettings: entrySettings,
    entryId: entryId,
    pinTrayToInner: pinTrayToInner,
    moduleString: moduleString,
    entryIndex: entryIndex,
    entriesBefore: entriesBefore,
    entriesAfter: entriesAfter,
    inlineSettingsDelta: inlineSettingsDelta,
    expandPath: expandPath,
    customModuleSafeName: customModuleSafeName,
    customModuleType: customModuleType,
    customModulePath: customModulePath,
    cumulativeWidths: cumulativeWidths,
    countNonZero: countNonZero,
    wrapOffset: wrapOffset,
    homeOffset: homeOffset,
    nearestHome: nearestHome,
    ringLength: ringLength,
    ringView: ringView,
    offsetToReveal: offsetToReveal,
    entryOccurrence: entryOccurrence,
    entryRef: entryRef,
    indexOfRef: indexOfRef,
    moveEntryByRef: moveEntryByRef,
    pinKind: pinKind,
    setEntryPinned: setEntryPinned
  }
}

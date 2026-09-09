import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "BarModel.js" as BarModel

Item {
  id: root

  // MenuBar Overload: the Omarchy bar engine (as cloned into pi.bar, the
  // "Locked Bar") with an endless, dock-magnified carousel on the left and
  // right sections. See the `carousel` block below and README.md.
  //
  // The omarchy-shell host injects omarchyPath from OMARCHY_PATH.
  // Custom bars are instantiated by an asynchronous Loader, then these values
  // are injected from shell.qml's onLoaded handler. They therefore cannot be
  // QML `required` properties in a user-owned bar clone.
  property string omarchyPath: ""
  // Injected by the host shell so bar slots can resolve enabled widgets.
  property var barWidgetRegistry: null
  // Injected by the host shell every time shell.json is reloaded. Holds the
  // `bar:` subtree: position, centerAnchor, layout. The host owns file IO;
  // the bar just renders whatever it's handed. The bar font follows the
  // OS-level fontconfig monospace binding — it is not stored in shell.json.
  property var barConfig: ({})
  // Injected by the host shell. Used for shell-wide actions such as opening
  // settings and persisting inline widget state.
  property var shell: null
  // Manifest for the active bar option. Present for custom bars and useful for
  // diagnostics; the built-in bar does not otherwise need it.
  property var manifest: null
  // Mirrors the on-disk `bar-off` flag so the user can hide the bar without
  // killing the entire shell. Hidden panels stay mapped but park off-screen
  // without an exclusion zone; updated by the FileView watcher further down.
  property bool barHidden: false
  property string home: Quickshell.env("HOME")
  property string stateHome: home + "/.local/state"
  property string omarchyConfigDir: home + "/.config/omarchy"
  property var fallbackBarConfig: ({
    position: "top",
    transparent: false,
    centerAnchor: "omarchy.clock",
    layout: { left: [], center: [], right: [] }
  })
  property var layoutConfig: fallbackBarConfig.layout
  property string centerAnchor: ""
  property bool requestedTransparent: false
  property bool useTransparentForeground: false
  property bool transparent: false
  property bool centerSectionHovered: false
  // One bar surface exists per monitor and each reports into this count, so a
  // pointer crossing from one monitor's bar to another's stays counted however
  // the enter and leave interleave. A single shared bool would be left false by
  // whichever event landed last.
  property int barHoverCount: 0
  // True while the pointer is over any bar, widgets included.
  readonly property bool barHovered: barHoverCount > 0
  property bool centerSectionRevealHeld: false
  property bool centerHoverRevealSuppressed: false
  property int barConfigSerial: 0
  property string position: "top"
  // Resolves through fontconfig at paint time (Style.font.family defaults
  // to "monospace"), so changing the system font (via `omarchy-font-set`)
  // updates the bar without a reload.
  property string fontFamily: Style.font.family
  // Bound to the central Color singleton so the bar tracks shell.toml's
  // [bar] section. Property names kept for the rest of this file's bindings.
  property color themeForeground: Color.bar.text
  property color themeContrastForeground: Color.background
  property color transparentForeground: Color.bar.text
  property color foreground: themeForeground
  property color barForeground: useTransparentForeground ? transparentForeground : themeForeground
  property bool foregroundAnimationEnabled: true
  property color background: Color.bar.background
  property color urgent: Color.bar.active

  Behavior on barForeground { enabled: root.foregroundAnimationEnabled; ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on background { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on urgent { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  property var tooltipTarget: null
  property var pendingTooltipTarget: null
  property string tooltipText: ""
  property string pendingTooltipText: ""
  property bool tooltipShown: false
  property int tooltipRequest: 0
  property var activePopout: null
  property var barDragSource: null
  property var barDragTarget: null
  property var barDragTargetGeometry: null
  property bool barDragAfter: false
  property var barDragWindow: null
  property var barDragScreen: null
  property url barDragImageUrl: ""
  property real barDragSceneX: 0
  property real barDragSceneY: 0
  property real barDragScreenX: 0
  property real barDragScreenY: 0
  property real barDragOffsetX: 0
  property real barDragOffsetY: 0
  property bool barMoveActive: false
  property string barMoveCandidate: ""
  property var barMoveWindow: null
  property var barMoveScreen: null
  property var clickTargets: []
  property var moduleSlots: []

  // ------------------------------------------------------------- carousel
  //
  // The left and right sections are strips that scroll inside the room the
  // center section leaves. A strip whose widgets fit is laid out flat and
  // stays dormant. One that overflows becomes an endless ring: widgets that
  // do not fit stay mounted (timers, IPC and services keep running) and sit
  // past the edge of a clipped viewport until the ring scrolls them in, and
  // the widgets under the pointer swell and tilt like a dock. The center
  // never scrolls.
  //
  // Scroll offsets live here so every monitor's copy of a section shows the
  // same run; each deck animates toward the shared target on its own.
  property var decks: []
  property var offsets: ({ left: 0, right: 0 })
  // A strip a click has held in place (it will not drift home).
  property var holds: ({ left: false, right: false })
  property var lastScrollAt: ({ left: 0, right: 0 })
  readonly property var carouselConfig: Util.isPlainObject(barConfig) && Util.isPlainObject(barConfig.carousel) ? barConfig.carousel : ({})
  readonly property bool wheelScrolling: carouselConfig.wheel !== false
  readonly property bool invertWheel: carouselConfig.invertWheel === true
  // Pixels one wheel notch scrolls.
  readonly property real scrollStep: carouselConfig.step === undefined ? Style.space(64) : Math.max(4, Number(carouselConfig.step) || 0)
  readonly property int scrollAnimationMs: carouselConfig.animation === undefined ? 240 : Math.max(0, Number(carouselConfig.animation) || 0)
  readonly property int returnAfter: carouselConfig.returnAfter === undefined ? 6 : Math.max(0, Number(carouselConfig.returnAfter) || 0)
  // Dock magnification: extra scale under the pointer, its reach, and the
  // 3D tilt at the edge of that reach.
  readonly property real magnify: carouselConfig.magnify === undefined ? 0.35 : Math.max(0, Number(carouselConfig.magnify) || 0)
  readonly property real magnifyRadius: carouselConfig.radius === undefined ? Style.space(84) : Math.max(1, Number(carouselConfig.radius) || 1)
  readonly property real tilt: carouselConfig.tilt === undefined ? 16 : Math.max(0, Number(carouselConfig.tilt) || 0)
  readonly property bool edgeHints: carouselConfig.edgeHints !== false
  readonly property int carouselGap: Style.space(8)
  readonly property int fitTolerance: Style.space(5)
  readonly property int loopGap: Style.space(14)
  readonly property int edgeHintWidth: Style.space(26)
  property var pendingSummon: null

  function isScrollingRegion(region) { return region === "left" || region === "right" }
  function offsetOf(region) { return Number(offsets[region]) || 0 }
  function isHeld(region) { return holds[region] === true }

  // Entries flagged `"pinned": true` sit fixed at the bar's outer edge and
  // never join the carousel: the launcher and workspaces on the left, the
  // bell and power on the right. `omarchy bar set <id> pinned true` flags one.
  function isPinnedEntry(entry) {
    var settings = entrySettings(entry)
    return settings.pinned === true || settings.pinned === "true"
  }

  // Indices (into the region list) of the pinned and the scrolling entries.
  function splitIndices(entries, pinned) {
    var out = []
    var list = Array.isArray(entries) ? entries : []
    for (var i = 0; i < list.length; i++) {
      if (isPinnedEntry(list[i]) === pinned) out.push(i)
    }
    return out
  }

  function pickEntries(entries, indices) {
    var out = []
    for (var i = 0; i < indices.length; i++) out.push(entries[indices[i]])
    return out
  }

  function registerDeck(deck) {
    if (!deck || decks.indexOf(deck) !== -1) return
    var next = decks.slice()
    next.push(deck)
    decks = next
  }

  function unregisterDeck(deck) {
    decks = decks.filter(function(item) { return item !== deck })
  }

  function deckFor(region) {
    for (var i = 0; i < decks.length; i++) {
      if (decks[i] && decks[i].region === region && decks[i].built) return decks[i]
    }
    return null
  }

  function setOffset(region, value, byUser) {
    if (!isScrollingRegion(region)) return false
    var next = Number(value)
    if (!isFinite(next)) return false
    var stamp = Util.cloneJson(lastScrollAt)
    stamp[region] = Date.now()
    lastScrollAt = stamp
    // Scrolling again releases a click's hold; the strip drifts home once idle.
    if (byUser) setHeld(region, false)
    if (Math.abs(next - offsetOf(region)) < 0.01) return false
    var copy = Util.cloneJson(offsets)
    copy[region] = next
    offsets = copy
    return true
  }

  function scrollBy(region, pixels) { return setOffset(region, offsetOf(region) + (Number(pixels) || 0), true) }

  function isHome(region) {
    var deck = deckFor(region)
    if (!deck || !deck.overflowing) return true
    var distance = Math.abs(offsetOf(region) - BarModel.nearestHome(offsetOf(region), deck.homeOffset, deck.ring))
    return distance < 0.5
  }

  function scrollHome(region, byUser) {
    var deck = deckFor(region)
    if (!deck) return false
    return setOffset(region, BarModel.nearestHome(offsetOf(region), deck.homeOffset, deck.ring), byUser === true)
  }

  function setHeld(region, value) {
    if (!isScrollingRegion(region) || isHeld(region) === (value === true)) return
    var copy = Util.cloneJson(holds)
    copy[region] = value === true
    holds = copy
  }

  // A click on a scrolled strip keeps it where you left it.
  function holdFromClick(region) {
    if (isScrollingRegion(region) && !isHome(region)) setHeld(region, true)
  }

  // Wheel down or swipe right moves the widgets right to left, wheel up or
  // swipe left moves them back. Touchpads report pixel deltas and scroll by
  // exactly that; a mouse wheel notch scrolls `scrollStep` pixels.
  function scrollWheel(region, wheel) {
    if (!wheelScrolling || !isScrollingRegion(region)) return false
    var deck = deckFor(region)
    if (!deck || !deck.overflowing) return false
    var pixels = 0
    if (wheel.pixelDelta && (wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0)) {
      pixels = -(wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.pixelDelta.x)
    } else {
      var delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
      pixels = -delta / 120 * scrollStep
    }
    if (invertWheel) pixels = -pixels
    if (pixels === 0) return true
    scrollBy(region, pixels)
    return true
  }

  function slotForItem(item) {
    if (!item) return null
    for (var i = 0; i < moduleSlots.length; i++) {
      if (moduleSlots[i] && moduleSlots[i].activeItem === item) return moduleSlots[i]
    }
    return null
  }

  function carouselStatus() {
    var out = {}
    var regions = ["left", "right"]
    for (var i = 0; i < regions.length; i++) {
      var region = regions[i]
      var deck = deckFor(region)
      out[region] = {
        overflowing: deck ? deck.overflowing : false,
        offset: Math.round(offsetOf(region)),
        home: isHome(region),
        held: isHeld(region),
        hidden: deck ? deck.hiddenCount : 0,
        pinned: deck ? deck.pinnedIds : [],
        viewport: deck ? Math.round(deck.viewport) : 0,
        total: deck ? Math.round(deck.total) : 0
      }
    }
    out.wheel = wheelScrolling
    out.invertWheel = invertWheel
    out.step = Math.round(scrollStep)
    out.animation = scrollAnimationMs
    out.returnAfter = returnAfter
    out.magnify = magnify
    out.radius = Math.round(magnifyRadius)
    out.tilt = tilt
    out.edgeHints = edgeHints
    return out
  }

  // Drift home after `returnAfter` idle seconds unless the strip was pinned
  // by a click, the pointer is on the bar, a drag is live or a panel is open.
  Timer {
    interval: 1000
    repeat: true
    running: root.returnAfter > 0
    onTriggered: {
      if (root.barHovered || root.barDragSource || root.activePopout) return
      var now = Date.now()
      var regions = ["left", "right"]
      for (var i = 0; i < regions.length; i++) {
        var region = regions[i]
        if (root.isHome(region) || root.isHeld(region)) continue
        if (now - Number(root.lastScrollAt[region] || 0) >= root.returnAfter * 1000) root.scrollHome(region, false)
      }
    }
  }

  // A summoned panel whose widget is off the strip opens once the scroll has
  // landed, so its popup anchors to where the widget ends up.
  Timer {
    id: summonTimer
    interval: root.scrollAnimationMs + 60
    onTriggered: {
      var item = root.pendingSummon
      root.pendingSummon = null
      if (item && typeof item.open === "function") item.open()
    }
  }

  IpcHandler {
    target: "menubar-overload"

    function scroll(region: string, pixels: real): string {
      root.scrollBy(region, pixels)
      return String(Math.round(root.offsetOf(region)))
    }
    function home(region: string): string {
      if (region === "" || region === "all") { root.scrollHome("left", true); root.scrollHome("right", true) }
      else root.scrollHome(region, true)
      return "ok"
    }
    function hold(region: string, value: string): string {
      root.setHeld(region, value === "true" || value === "on" || value === "1")
      return root.isHeld(region) ? "held" : "released"
    }
    function status(): string { return JSON.stringify(root.carouselStatus()) }
  }

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    var next = clickTargets.filter(function(item) { return item !== target })
    clickTargets = next
  }

  function registerModuleSlot(slot) {
    if (!slot || moduleSlots.indexOf(slot) !== -1) return
    var next = moduleSlots.slice()
    next.push(slot)
    moduleSlots = next
  }

  function unregisterModuleSlot(slot) {
    var next = moduleSlots.filter(function(item) { return item !== slot })
    moduleSlots = next
  }

  function debugBarGeometry() {
    var out = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      var point = { x: slot.x, y: slot.y }
      try {
        point = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }
      out.push({
        id: slot.moduleName,
        section: slot.region,
        x: Math.round(point.x),
        y: Math.round(point.y),
        width: Math.round(slot.width),
        height: Math.round(slot.height),
        visible: slot.visible === true && slot.width > 0 && slot.height > 0,
        shown: slot.shown === true,
        regionIndex: slot.regionIndex,
        scrolling: slot.deck !== null,
        itemVisible: slot.activeItem.visible === true,
        itemWidth: Math.round(slot.activeItem.implicitWidth || 0),
        itemHeight: Math.round(slot.activeItem.implicitHeight || 0)
      })
    }
    return out
  }

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && targetWindow(target) === window
  }

  function slotWindow(slot) {
    if (!slot) return null
    return targetWindow(slot.activeItem) || targetWindow(slot)
  }

  function sameWindow(left, right) {
    if (!left || !right) return false
    if (left === right) return true
    return !!left.screen && !!right.screen && !!left.screen.name && !!right.screen.name && left.screen.name === right.screen.name
  }

  function targetTooltipHovered(target) {
    return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered === true
  }

  function clearTooltip() {
    tooltipTimer.stop()
    pendingTooltipTarget = null
    pendingTooltipText = ""
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  function clearBarDrag() {
    barDragSource = null
    barDragWindow = null
    barDragScreen = null
    barDragImageUrl = ""
    barDragTarget = null
    barDragTargetGeometry = null
    barDragAfter = false
    barDragSceneX = 0
    barDragSceneY = 0
    barDragScreenX = 0
    barDragScreenY = 0
    barDragOffsetX = 0
    barDragOffsetY = 0
  }

  function windowScreenPoint(scenePoint, window) {
    var x = scenePoint ? scenePoint.x : 0
    var y = scenePoint ? scenePoint.y : 0
    if (!window || !window.screen) return { x: x, y: y }

    if (root.position === "bottom")
      y += Math.max(0, window.screen.height - window.height)
    else if (root.position === "right")
      x += Math.max(0, window.screen.width - window.width)

    return { x: x, y: y }
  }

  function barDragScreenPoint(scenePoint) {
    return windowScreenPoint(scenePoint, barDragWindow)
  }

  function dropMarkerRect(slot, after) {
    if (!slot) return null

    try {
      var slotPoint = slot.mapToItem(null, 0, 0)
      var screenPoint = barDragScreenPoint(slotPoint)
      var thickness = Style.spacing.xs
      if (vertical) {
        return {
          x: screenPoint.x,
          y: screenPoint.y + (after ? slot.height : 0) - thickness / 2,
          width: slot.width,
          height: thickness
        }
      }

      return {
        x: screenPoint.x + (after ? slot.width : 0) - thickness / 2,
        y: screenPoint.y,
        width: thickness,
        height: slot.height
      }
    } catch (e) {
      return null
    }
  }

  // Split the screen along its diagonals (in normalized space, so widescreens
  // don't bias toward left/right): whichever triangle holds the cursor names
  // the candidate edge.
  function nearestScreenEdge(point, screen) {
    var nx = screen.width > 0 ? Util.clamp(point.x / screen.width, 0, 1) : 0.5
    var ny = screen.height > 0 ? Util.clamp(point.y / screen.height, 0, 1) : 0.5

    var edge = "top"
    var best = ny
    if (1 - ny < best) { edge = "bottom"; best = 1 - ny }
    if (nx < best) { edge = "left"; best = nx }
    if (1 - nx < best) { edge = "right"; best = 1 - nx }
    return edge
  }

  function beginBarMove(window) {
    barMoveWindow = window
    barMoveScreen = window ? window.screen : null
    barMoveCandidate = position
    barMoveActive = true
  }

  function updateBarMove(screenPoint) {
    if (!barMoveActive || !barMoveScreen) return
    barMoveCandidate = nearestScreenEdge(screenPoint, barMoveScreen)
  }

  function clearBarMove() {
    barMoveActive = false
    barMoveCandidate = ""
    barMoveWindow = null
    barMoveScreen = null
  }

  function finishBarMove() {
    var edge = barMoveCandidate
    if (!barMoveActive || !edge || edge === position) {
      clearBarMove()
      return
    }

    clearBarMove()
    setBarPosition(edge)
  }

  function setBarPosition(value) {
    var next = normalizePosition(value)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.position = next
      })
    } else {
      root.position = next
    }
  }

  function captureBarDragGhost(slot) {
    var item = slot && slot.activeItem ? slot.activeItem : null
    barDragImageUrl = ""
    if (!item || typeof item.grabToImage !== "function") return

    var grabWidth = Math.max(1, Math.ceil(item.width || item.implicitWidth || slot.width || 1))
    var grabHeight = Math.max(1, Math.ceil(item.height || item.implicitHeight || slot.height || 1))
    item.grabToImage(function(result) {
      if (root.barDragSource !== slot || !result || !result.url) return
      root.barDragImageUrl = result.url
    }, Qt.size(grabWidth, grabHeight))
  }

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout) activePopout.close()
    }
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  readonly property bool vertical: position === "left" || position === "right"
  readonly property int barSize: vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

  function normalizePosition(value) {
    return BarModel.normalizePosition(value)
  }

  // Apply tray-pinning on top of the shared layout normalization so the
  // bar host and scriptable config helpers can't drift on entry shape.
  function normalizeLayout(layout) {
    var normalized = Util.normalizeLayout(Util.isPlainObject(layout) ? layout : fallbackBarConfig.layout)
    return {
      left:   pinTrayToInner(normalized.left,   "left"),
      center: pinTrayToInner(normalized.center, "center"),
      right:  pinTrayToInner(normalized.right,  "right")
    }
  }

  // The tray drawer reveals inward (away from the bar edge). Place it at the
  // section's inner edge: start of the right section, end of the left/center
  // sections. The drawer's reserved space then sits next to the bar center,
  // not stranded mid-section.
  function pinTrayToInner(entries, section) {
    return BarModel.pinTrayToInner(entries, section)
  }

  function applyBarConfig() {
    var config = Util.isPlainObject(barConfig) ? barConfig : fallbackBarConfig

    // This is a deliberately locked, macOS-style desktop bar. Keep its edge
    // and opacity invariant even if another helper writes conflicting values.
    position = "top"
    setRequestedTransparency(false)
    centerAnchor = Util.canonicalWidgetId(config.centerAnchor || "")

    // layoutEntries feeds plain JS arrays to the module Repeaters, and QML
    // cannot diff those: reassigning layoutConfig rebuilds every widget on
    // every monitor. When a shell.json write only changed inline widget
    // settings, patch the live layout and running widgets in place instead.
    var next = normalizeLayout(config.layout)
    var delta = BarModel.inlineSettingsDelta(layoutConfig, next)
    if (delta) {
      applySettingsDelta(delta)
      return
    }
    layoutConfig = next
    barConfigSerial++
  }

  function applySettingsDelta(delta) {
    for (var i = 0; i < delta.length; i++) {
      var change = delta[i]
      layoutConfig[change.region][change.index] = change.entry
      var settings = entrySettings(change.entry)
      for (var s = 0; s < moduleSlots.length; s++) {
        var slot = moduleSlots[s]
        if (!slot || slot.region !== change.region || slot.moduleName !== entryId(change.entry)) continue
        var item = slot.activeItem
        if (item && "settings" in item) item.settings = settings
      }
    }
  }

  onBarConfigChanged: applyBarConfig()

  function layoutEntries(region) {
    var serial = barConfigSerial
    var entries = layoutConfig ? layoutConfig[region] : null
    return Array.isArray(entries) ? entries : []
  }

  // Tab order for the panels in one bar region. Scoped to a single bar surface
  // so tabbing walks the bar the open panel belongs to instead of hopping the
  // panel to another monitor's copy of the same widget.
  function panelNavigationSlots(region, window) {
    var entries = layoutEntries(region)
    var slots = []
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      for (var j = 0; j < moduleSlots.length; j++) {
        var slot = moduleSlots[j]
        if (!slot || slot.region !== region || slot.moduleName !== id) continue
        if (!slot.shown) continue
        if (window && !sameWindow(slotWindow(slot), window)) continue
        var item = slot.activeItem
        if (!item || item.visible !== true || slot.visible !== true || slot.width <= 0 || slot.height <= 0) continue
        if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
        slots.push(slot)
        break
      }
    }
    return slots
  }

  // The Nth panel in a bar region, counted the way the bar reads: layout order,
  // and only the panels actually on screen. A widget with no panel (the tray)
  // and one that is hiding itself are passed over, so the number lands on the
  // Nth panel icon the user can see rather than the Nth layout entry.
  // One-based, because it exists for hotkeys; anything else lands on no slot.
  //
  // Counting any bar surface is enough: every monitor lays its bar out from the
  // one layout, and summoning the id routes through pickPanelSlot, which opens
  // the focused monitor's copy whichever surface was counted.
  function panelWidgetIdAt(region, index) {
    var slots = panelNavigationSlots(String(region || ""), null)
    var slot = slots[Math.round(Number(index)) - 1]
    return slot ? String(slot.moduleName || "") : ""
  }

  function switchPanelFrom(owner, direction) {
    if (!owner) return false

    var currentSlot = null
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.activeItem === owner) {
        currentSlot = slot
        break
      }
    }
    if (!currentSlot) return false

    var slots = panelNavigationSlots(currentSlot.region, slotWindow(currentSlot))
    if (slots.length < 2) return false

    var currentIndex = -1
    for (var j = 0; j < slots.length; j++) {
      if (slots[j] === currentSlot) {
        currentIndex = j
        break
      }
    }
    if (currentIndex < 0) return false

    var step = direction < 0 ? -1 : 1
    var nextSlot = slots[(currentIndex + step + slots.length) % slots.length]
    if (!nextSlot || !nextSlot.activeItem || nextSlot.activeItem === owner) return false

    nextSlot.activeItem.open()
    return true
  }

  // Every live instance of a widget id. A bar surface is built per monitor, so
  // a widget that appears once in the layout is still live once per screen.
  function moduleWidgets(pluginId) {
    var id = String(pluginId || "")
    var items = []
    if (!id) return items
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem || slot.moduleName !== id) continue
      items.push(slot.activeItem)
    }
    return items
  }

  function slotScreenName(slot) {
    var window = slotWindow(slot)
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  // The output Hyprland has focused, which is where a keyboard-summoned panel
  // belongs. Empty until Hyprland reports one, which leaves panel routing on
  // its per-monitor fallback rather than guessing at an output.
  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  // Resolve the live bar-widget instance for a plugin id (e.g. "omarchy.bluetooth").
  // Only widgets that expose popup open/close methods count; plain indicators
  // (clock, workspaces, tray) return null. Used by shell.summon/toggle so
  // panel hotkeys route through the bar instead of a per-target IPC handler
  // that only reaches whichever per-monitor instance claimed the target.
  function findPanelWidget(pluginId) {
    var id = String(pluginId || "")
    if (!id) return null
    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      if (slot.moduleName !== id) continue
      var item = slot.activeItem
      if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
      candidates.push({ slot: slot, screenName: slotScreenName(slot), opened: item.opened === true })
    }
    // One copy per monitor, plus a zero-size placeholder for anchored center
    // modules. See BarModel.pickPanelSlot for which one a hotkey acts on.
    var chosen = BarModel.pickPanelSlot(candidates, focusedScreenName())
    return chosen ? chosen.activeItem : null
  }

  function summonBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.open !== "function") return false
    var slot = slotForItem(item)
    if (slot && slot.deck && slot.deck.overflowing && !slot.shown) {
      var target = slot.deck.offsetToReveal(slot.deckIndex)
      if (setOffset(slot.region, target, false)) {
        pendingSummon = item
        summonTimer.restart()
        return true
      }
    }
    item.open()
    return true
  }

  function hideBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.close !== "function") return false
    item.close()
    return true
  }

  function isBarWidgetOpen(pluginId) {
    var item = findPanelWidget(pluginId)
    return !!item && item.opened === true
  }

  function entrySettings(entry) {
    return BarModel.entrySettings(entry)
  }

  function entryId(entry) {
    return BarModel.entryId(entry)
  }

  function moduleString(entry, key, fallback) {
    return BarModel.moduleString(entry, key, fallback)
  }

  function entryIndex(entries, name) {
    return BarModel.entryIndex(entries, name)
  }

  function entriesBefore(entries, name) {
    return BarModel.entriesBefore(entries, name)
  }

  function entriesAfter(entries, name) {
    return BarModel.entriesAfter(entries, name)
  }

  function canonicalWidgetId(name) {
    return Util.canonicalWidgetId(name)
  }

  function expandPath(path) {
    return BarModel.expandPath(path, home)
  }

  function customModuleSafeName(name) {
    return BarModel.customModuleSafeName(name)
  }

  function customModuleType(entry) {
    return BarModel.customModuleType(entry)
  }

  function customModuleSource(entry) {
    var source = BarModel.customModulePath(entry, home, omarchyConfigDir)
    return source ? Util.fileUrl(source) : ""
  }

  Component.onCompleted: applyBarConfig()

  // Revealing the indicators widens their section, which can slide a neighbour
  // under a stationary pointer. Collapsing on that un-hover would move it back
  // out and re-open the peek, so hold until the pointer leaves the bar.
  function setCenterSectionHovered(hovered) {
    centerSectionHovered = hovered
    if (hovered) {
      centerSectionRevealTimer.stop()
      centerSectionRevealHeld = true
    } else {
      centerSectionRevealTimer.restart()
    }
  }

  function setBarHovered(hovered) {
    barHoverCount = Math.max(0, barHoverCount + (hovered ? 1 : -1))
    if (barHoverCount === 0) centerSectionRevealTimer.restart()
  }

  Timer {
    id: centerSectionRevealTimer
    interval: 120
    // Collapse only. Opening the peek is the center section's own gesture, done
    // in setCenterSectionHovered, so a timer left pending by a pointer that dipped
    // off the bar and came back cannot reveal indicators it never pointed at.
    onTriggered: if (!root.centerSectionHovered && !root.barHovered) root.centerSectionRevealHeld = false
  }

  function run(command) {
    if (!command) return

    Util.execDetached(command)
  }

  function toggleTransparency() {
    var nextTransparent = !(root.requestedTransparent === true)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.transparent = nextTransparent
      })
    } else {
      root.setRequestedTransparency(nextTransparent)
    }
  }

  // Drop targets: only widgets fully on the strip right now. To move a
  // widget onto a hidden part of a strip, scroll it into view first (the
  // wheel works while dragging), then drop.
  function moduleDropAtScene(scenePoint, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    if (sourceWindow && sourceWindow.contentItem) {
      var barPoint = sourceWindow.contentItem.mapFromItem(null, scenePoint.x, scenePoint.y)
      if (barPoint.x < 0 || barPoint.x > sourceWindow.contentItem.width ||
          barPoint.y < 0 || barPoint.y > sourceWindow.contentItem.height)
        return null
    }

    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || !slot.shown || !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue

      var slotPoint = { x: slot.x, y: slot.y }
      try {
        slotPoint = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }

      candidates.push({ slot: slot, x: slotPoint.x, y: slotPoint.y, width: slot.width, height: slot.height })
    }

    return BarModel.nearestDropTarget(candidates, scenePoint, root.vertical)
  }

  // Persist a drop. Entries are addressed as {id, occurrence} references
  // rather than names, so a layout with several spacers stays unambiguous.
  // "After the target" means in front of whatever follows it in the region.
  function dropBarModuleAtTarget(sourceSlot, target, afterTarget) {
    if (!sourceSlot || !target) return false
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return false
    var fromRef = sourceSlot.ref
    if (!fromRef) return false

    var toRegion = target.region
    var entries = layoutEntries(toRegion)
    var index = afterTarget ? target.regionIndex + 1 : target.regionIndex
    var toRef = index < entries.length ? BarModel.entryRef(entries, index) : null

    var changed = false
    root.shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)) config.bar = {}
      if (!Util.isPlainObject(config.bar.layout)) config.bar.layout = {}
      changed = BarModel.moveEntryByRef(config.bar.layout, sourceSlot.region, fromRef, toRegion, toRef)
    })
    return changed
  }

  function moduleTargetClickable(target) {
    return target
      && target.visible !== false
      && target.opacity !== 0
      && target.interactive !== false
      && target.pressable !== false
      && target.concealed !== true
      && typeof target.triggerPress === "function"
  }

  function moduleClickTargetAt(slot, localX, localY) {
    for (var i = clickTargets.length - 1; i >= 0; i--) {
      var target = clickTargets[i]
      if (!moduleTargetClickable(target)) continue

      var targetPoint = { x: localX, y: localY }
      try {
        targetPoint = slot.mapToItem(target, localX, localY)
      } catch (e) {
        continue
      }

      if (targetPoint.x >= 0 && targetPoint.x <= target.width &&
          targetPoint.y >= 0 && targetPoint.y <= target.height) {
        return target
      }
    }

    if (moduleTargetClickable(slot.activeItem)) return slot.activeItem
    return null
  }

  function pressModuleClickTarget(slot, button, localX, localY) {
    var target = moduleClickTargetAt(slot, localX, localY)
    if (!target) return false

    target.triggerPress(button)
    return true
  }

  function colorHex(colorValue) {
    var c = colorValue
    if (typeof c === "string") c = Qt.color(c)
    function hexChannel(value) {
      var s = Math.round(Util.clamp(value, 0, 1) * 255).toString(16)
      return s.length < 2 ? "0" + s : s
    }
    return "#" + hexChannel(c.r) + hexChannel(c.g) + hexChannel(c.b)
  }

  function setRequestedTransparency(value) {
    var nextTransparent = value === true
    requestedTransparent = nextTransparent
    if (!nextTransparent) {
      foregroundAnimationEnabled = false
      useTransparentForeground = false
      transparent = false
      transparentForeground = themeForeground
      restoreForegroundAnimation()
      return
    }
    scheduleTransparentForegroundRefresh()
  }

  function restoreForegroundAnimation() {
    Qt.callLater(function() {
      Qt.callLater(function() { root.foregroundAnimationEnabled = true })
    })
  }

  function scheduleTransparentForegroundRefresh() {
    if (!requestedTransparent) {
      transparentForeground = themeForeground
      return
    }
    transparentForegroundTimer.restart()
  }

  function refreshTransparentForeground() {
    if (!requestedTransparent || transparentForegroundProc.running) return

    transparentForegroundProc.command = [
      "omarchy-bar-text-color",
      root.position,
      String(root.barSize),
      colorHex(root.themeForeground),
      colorHex(root.themeContrastForeground)
    ]
    transparentForegroundProc.running = true
  }

  onRequestedTransparentChanged: scheduleTransparentForegroundRefresh()
  onPositionChanged: scheduleTransparentForegroundRefresh()
  onThemeForegroundChanged: scheduleTransparentForegroundRefresh()
  onThemeContrastForegroundChanged: scheduleTransparentForegroundRefresh()

  Timer {
    id: transparentForegroundTimer
    interval: 120
    repeat: false
    onTriggered: root.refreshTransparentForeground()
  }

  Process {
    id: transparentForegroundProc
    stdout: SplitParser {
      onRead: function(line) {
        var value = String(line || "").trim()
        if (!/^#[0-9A-Fa-f]{6}$/.test(value)) return

        root.foregroundAnimationEnabled = false
        root.transparentForeground = value
        if (root.requestedTransparent) {
          root.useTransparentForeground = true
          root.transparent = true
        }
        root.restoreForegroundAnimation()
      }
    }
  }

  FileView {
    path: root.stateHome + "/omarchy/current"
    watchChanges: true
    printErrors: false
    onFileChanged: root.scheduleTransparentForegroundRefresh()
  }

  function runProcess(process) {
    if (!process.running)
      process.running = true
  }

  function showTooltip(target, text) {
    clearTooltip()

    if (!targetTooltipHovered(target) || !text) {
      tooltipRequest += 1
      return
    }

    var request = tooltipRequest + 1
    tooltipRequest = request
    pendingTooltipTarget = target
    pendingTooltipText = text

    Qt.callLater(function() {
      if (request !== tooltipRequest) return
      if (!targetTooltipHovered(pendingTooltipTarget)) {
        clearTooltip()
        return
      }
      tooltipTarget = pendingTooltipTarget
      tooltipText = pendingTooltipText
      pendingTooltipTarget = null
      pendingTooltipText = ""
      tooltipTimer.restart()
    })
  }

  function hideTooltip(target) {
    if (tooltipTarget !== target && pendingTooltipTarget !== target) return

    tooltipRequest += 1
    clearTooltip()
  }

  Timer {
    id: tooltipTimer
    interval: 400
    onTriggered: {
      if (root.targetTooltipHovered(root.tooltipTarget)) root.tooltipShown = true
      else root.clearTooltip()
    }
  }

  Timer {
    interval: 100
    running: root.tooltipShown
    repeat: true
    onTriggered: if (!root.targetTooltipHovered(root.tooltipTarget)) root.hideTooltip(root.tooltipTarget)
  }

  // Presence of the `bar-off` flag = bar hidden. Watching the parent toggles
  // directory because FileView can't observe a file that doesn't exist yet,
  // and the flag is created/removed by `omarchy-toggle-bar`.
  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser { onRead: function(line) { root.barHidden = String(line).trim() === "yes" } }
  }
  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  // The directory watch can permanently stop delivering events after flag
  // changes land in quick succession, stranding the bar off screen until the
  // shell restarts. `omarchy-toggle-bar` nudges this after flipping the flag
  // so the probe re-reads it even when the watch has gone quiet.
  IpcHandler {
    target: "omarchy.bar"

    // Start rather than restart: a probe already in flight was launched by the
    // directory watch after the flag flipped, so its answer is current, and
    // killing it here can swallow the result entirely.
    function syncHidden(): void {
      barHiddenProbe.running = true
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarPanel {
        required property var modelData

        screen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      DragGhostPanel {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarMoveGhostPanel {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  component BarPanel: PanelWindow {
    id: barWindow

    // Hiding parks the bar just past its screen edge instead of unmapping it.
    // Unmapping frees the layer surface and the whole scene graph, so every
    // reveal has to rebuild them — new surface, re-shaped glyphs, re-uploaded
    // textures — which measures ~150ms against ~20ms to tear down. Parking
    // keeps the surface alive, so showing is only a margin change.
    visible: !remapGuard.remapping
    exclusionMode: root.barHidden ? ExclusionMode.Ignore : ExclusionMode.Auto

    ScreenMoveRemap {
      id: remapGuard
      window: barWindow
    }

    margins {
      top: root.barHidden && root.position === "top" ? -root.barSize : 0
      bottom: root.barHidden && root.position === "bottom" ? -root.barSize : 0
      left: root.barHidden && root.position === "left" ? -root.barSize : 0
      right: root.barHidden && root.position === "right" ? -root.barSize : 0
    }

    anchors {
      top: root.position === "top" || root.vertical
      bottom: root.position === "bottom" || root.vertical
      left: root.position === "left" || !root.vertical
      right: root.position === "right" || !root.vertical
    }

    implicitWidth: root.vertical ? root.barSize : 0
    implicitHeight: root.vertical ? 0 : root.barSize
    color: root.transparent ? "transparent" : root.background
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "omarchy-bar"
    WlrLayershell.layer: WlrLayer.Top

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalBar : horizontalBar

      // A child of the loader, not a sibling of the sections: an ancestor stays
      // hovered while the pointer is over a widget, where a sibling would lose
      // hover to the section the pointer entered.
      HoverHandler {
        onHoveredChanged: root.setBarHovered(hovered)
        // Unplugging a monitor destroys its bar without a leave event, which
        // would strand this surface's tally and hold the peek open for good.
        Component.onDestruction: if (hovered) root.setBarHovered(false)
      }
    }

    PopupWindow {
      id: tooltipWindow

      visible: root.tooltipShown && root.tooltipTarget !== null && root.tooltipText !== "" && root.targetBelongsToWindow(root.tooltipTarget, barWindow)
      color: "transparent"
      implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
      implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

      anchor {
        id: tooltipAnchor
        window: barWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          var target = root.tooltipTarget
          if (!root.targetBelongsToWindow(target, barWindow)) return

          var popupWidth = tooltipWindow.implicitWidth
          var popupHeight = tooltipWindow.implicitHeight
          var localX = target.width / 2 - popupWidth / 2
          var localY = target.height + 6

          if (root.position === "bottom") {
            localY = -popupHeight - 6
          } else if (root.position === "left") {
            localX = target.width + 6
            localY = target.height / 2 - popupHeight / 2
          } else if (root.position === "right") {
            localX = -popupWidth - 6
            localY = target.height / 2 - popupHeight / 2
          }

          var point = barWindow.contentItem.mapFromItem(target, localX, localY)
          tooltipAnchor.rect.x = Math.round(point.x)
          tooltipAnchor.rect.y = Math.round(point.y)
        }
      }

      BorderSurface {
        id: tooltipBubble
        implicitWidth: tooltipLabel.implicitWidth + 20
        implicitHeight: tooltipLabel.implicitHeight + 14
        color: Color.tooltip.background
        borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
        radius: Style.cornerRadius

        Text {
          id: tooltipLabel
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: root.tooltipText
          color: Color.tooltip.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    Component {
      id: horizontalBar

      Item {
        anchors.fill: parent

        CenterModules { id: centerModules; anchors.fill: parent }

        // Each side strip gets the room between the bar edge and the center
        // content, minus a gap.
        // Pinned widgets hold the corners; the strips take what is left
        // between them and the center.
        ModuleList {
          id: leftPinned
          readonly property var pinnedIndices: root.splitIndices(root.layoutEntries("left"), true)
          entries: root.pickEntries(root.layoutEntries("left"), pinnedIndices)
          indices: pinnedIndices
          region: "left"
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
        }

        LeftModules {
          id: leftDeck
          anchors.left: leftPinned.right
          anchors.verticalCenter: parent.verticalCenter
          budget: Math.max(0, centerModules.contentLeft - leftPinned.x - leftPinned.width - root.carouselGap)
        }

        ModuleList {
          id: rightPinned
          readonly property var pinnedIndices: root.splitIndices(root.layoutEntries("right"), true)
          entries: root.pickEntries(root.layoutEntries("right"), pinnedIndices)
          indices: pinnedIndices
          region: "right"
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
        }

        RightModules {
          id: rightDeck
          anchors.right: rightPinned.left
          anchors.verticalCenter: parent.verticalCenter
          budget: Math.max(0, rightPinned.x - centerModules.contentRight - root.carouselGap)
        }

        // "There is more this way" at both ends of a scrolling strip: the
        // widgets fade under a wash of bar colour and a chevron breathes.
        EdgeHint { deck: leftDeck; atEnd: false }
        EdgeHint { deck: leftDeck; atEnd: true }
        EdgeHint { deck: rightDeck; atEnd: false }
        EdgeHint { deck: rightDeck; atEnd: true }
      }
    }

    Component {
      id: verticalBar

      Item {
        anchors.fill: parent

        CenterModules { anchors.fill: parent }

        LeftModules {
          anchors.top: parent.top
          anchors.topMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }

        RightModules {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }

  Component { id: emptyModuleComponent; Item { implicitWidth: 0; implicitHeight: 0; visible: false } }

  component DragGhostPanel: PanelWindow {
    id: ghostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barDragScreen === ghostScreen ||
      (root.barDragScreen && ghostScreen && root.barDragScreen.name && ghostScreen.name && root.barDragScreen.name === ghostScreen.name)
    readonly property bool active: root.barDragSource && root.barDragScreen && screenMatches
    readonly property var sourceItem: root.barDragSource ? root.barDragSource.activeItem : null
    readonly property int ghostPadding: Style.space(1)
    readonly property int ghostWidth: sourceItem ? Math.max(1, Math.ceil(sourceItem.width)) : 1
    readonly property int ghostHeight: sourceItem ? Math.max(1, Math.ceil(sourceItem.height)) : 1

    visible: active && sourceItem !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-drag-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only drag feedback. Keep the input region empty so the ghost can
    // sit under the cursor without stealing the MouseArea's active pointer grab.
    mask: Region {}

    Item {
      visible: ghostWindow.visible
      x: Math.round(root.barDragScreenX - root.barDragOffsetX - ghostWindow.ghostPadding)
      y: Math.round(root.barDragScreenY - root.barDragOffsetY - ghostWindow.ghostPadding)
      width: ghostWindow.ghostWidth + ghostWindow.ghostPadding * 2
      height: ghostWindow.ghostHeight + ghostWindow.ghostPadding * 2

      BorderSurface {
        anchors.fill: parent
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        radius: Math.min(Style.cornerRadius, height / 2)
        opacity: root.transparent ? 0.45 : 0.94
      }

      Image {
        anchors.fill: parent
        anchors.margins: ghostWindow.ghostPadding
        source: root.barDragImageUrl
        fillMode: Image.Stretch
        smooth: true
        opacity: 0.84
      }
    }

    Rectangle {
      readonly property var targetRect: root.barDragTargetGeometry

      visible: ghostWindow.active && targetRect !== null
      x: targetRect ? Math.round(targetRect.x) : 0
      y: targetRect ? Math.round(targetRect.y) : 0
      width: targetRect ? targetRect.width : 0
      height: targetRect ? targetRect.height : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
    }
  }

  component BarMoveGhostPanel: PanelWindow {
    id: moveGhostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barMoveScreen === ghostScreen ||
      (root.barMoveScreen && ghostScreen && root.barMoveScreen.name && ghostScreen.name && root.barMoveScreen.name === ghostScreen.name)
    visible: root.barMoveActive && screenMatches
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-move-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only preview of the candidate edge. Keep the input region empty
    // so the overlay never steals the gesture area's active pointer grab.
    mask: Region {}

    // One fixed-geometry slab per edge, crossfaded on candidate changes.
    // Resizing a single slab between edges repaints mid-transition and
    // flickers; fading between static ones does not.
    Repeater {
      model: ["top", "bottom", "left", "right"]

      BorderSurface {
        id: edgeSlab

        required property string modelData
        readonly property bool edgeVertical: modelData === "left" || modelData === "right"
        readonly property int edgeSize: edgeVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

        x: modelData === "right" ? parent.width - edgeSize : 0
        y: modelData === "bottom" ? parent.height - edgeSize : 0
        width: edgeVertical ? edgeSize : parent.width
        height: edgeVertical ? parent.height : edgeSize
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        visible: opacity > 0
        opacity: root.barMoveCandidate === modelData ? (root.transparent ? 0.45 : 0.7) : 0

        Behavior on opacity {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
      }
    }
  }

  function findCenterAnchorEntry() {
    var entries = root.layoutEntries("center")
    var idx = root.entryIndex(entries, root.centerAnchor)
    return idx === -1 ? null : entries[idx]
  }

  component CenterModules: Item {
    id: centerRoot

    property var entries: root.layoutEntries("center")
    readonly property int anchorIndex: root.entryIndex(entries, root.centerAnchor)
    readonly property bool hasAnchor: anchorIndex !== -1
    readonly property var anchorEntry: root.findCenterAnchorEntry()
    // Where the center content starts and ends along the bar; the side strips
    // size themselves to the room outside these.
    readonly property real contentLeft: centerLoader.item && centerLoader.item.contentLeft !== undefined ? centerLoader.item.contentLeft : width / 2
    readonly property real contentRight: centerLoader.item && centerLoader.item.contentRight !== undefined ? centerLoader.item.contentRight : width / 2

    Loader {
      id: centerLoader
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalCenterModules : horizontalCenterModules
    }

    Component {
      id: horizontalCenterModules

      Item {
        id: horizontalCenter
        anchors.fill: parent

        readonly property real contentLeft: centerRoot.hasAnchor
          ? centerAnchorModule.x - beforeList.width
          : (unanchoredList.visible ? unanchoredList.x : width / 2)
        readonly property real contentRight: centerRoot.hasAnchor
          ? centerAnchorModule.x + centerAnchorModule.width + afterList.width
          : (unanchoredList.visible ? unanchoredList.x + unanchoredList.width : width / 2)

        CenterGestureArea {
          anchors.fill: parent
          contentLeft: horizontalCenter.contentLeft
          contentRight: horizontalCenter.contentRight
        }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          id: unanchoredList
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          id: beforeList
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.right: centerAnchorModule.left
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          regionIndex: centerRoot.anchorIndex
          anchors.centerIn: parent
        }

        ModuleList {
          id: afterList
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          offset: centerRoot.anchorIndex + 1
          anchors.left: centerAnchorModule.right
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }
      }
    }

    Component {
      id: verticalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.bottom: centerAnchorModule.top
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.top: centerAnchorModule.bottom
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }
      }
    }
  }

  component CenterGestureArea: MouseArea {
    id: gestureArea

    property real contentLeft: width / 2
    property real contentRight: width / 2
    property bool dragging: false
    property bool suppressClick: false
    property real pressedX: 0
    property real pressedY: 0
    readonly property real dragThreshold: Style.space(4)

    // Keep the desktop bar fixed like a macOS menu bar. The stock bar accepts
    // left-button gestures here to drag it between edges and double-click to
    // toggle transparency; accepting no buttons makes both settings immutable
    // from accidental pointer gestures while preserving widget interactions.
    acceptedButtons: Qt.NoButton
    cursorShape: Qt.ArrowCursor
    pressAndHoldInterval: 200

    function startDrag(x, y) {
      if (dragging) return
      dragging = true
      root.beginBarMove(root.targetWindow(gestureArea))
      var scenePoint = gestureArea.mapToItem(null, x, y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onPressed: function(mouse) {
      dragging = false
      suppressClick = false
      pressedX = mouse.x
      pressedY = mouse.y
    }

    onPressAndHold: function(mouse) {
      // A widget above us propagates its composed press-and-hold down here without
      // ever handing over the grab, so we'd get no release or cancel to end the move.
      if (!gestureArea.pressed) return
      startDrag(mouse.x, mouse.y)
    }

    onPositionChanged: function(mouse) {
      if (!(mouse.buttons & Qt.LeftButton)) return

      if (!dragging) {
        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance < dragThreshold) return
        startDrag(mouse.x, mouse.y)
        return
      }

      var scenePoint = gestureArea.mapToItem(null, mouse.x, mouse.y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onReleased: function(mouse) {
      if (!dragging) return
      dragging = false
      suppressClick = true
      root.finishBarMove()
      mouse.accepted = true
    }

    onCanceled: {
      dragging = false
      suppressClick = false
      root.clearBarMove()
    }

    onClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        mouse.accepted = true
      }
    }

    onDoubleClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        return
      }
      if (mouse.button === Qt.LeftButton) {
        root.toggleTransparency()
        mouse.accepted = true
      }
    }

    // Empty bar space beside a strip scrolls that strip; over the center
    // nothing scrolls.
    onWheel: function(wheel) {
      var region = ""
      if (wheel.x < gestureArea.contentLeft) region = "left"
      else if (wheel.x > gestureArea.contentRight) region = "right"
      wheel.accepted = region !== "" && root.scrollWheel(region, wheel)
    }
  }

  component LeftModules: ScrollDeck {
    readonly property var stripIndices: root.splitIndices(root.layoutEntries("left"), false)
    entries: root.pickEntries(root.layoutEntries("left"), stripIndices)
    indices: stripIndices
    region: "left"
    fromEnd: false
  }

  component RightModules: ScrollDeck {
    readonly property var stripIndices: root.splitIndices(root.layoutEntries("right"), false)
    entries: root.pickEntries(root.layoutEntries("right"), stripIndices)
    indices: stripIndices
    region: "right"
    fromEnd: true
  }

  // A plain run of widgets, used by the center section. It never scrolls.
  component ModuleList: Item {
    id: moduleListRoot

    property var entries: []
    property string region: ""
    // Index of entries[0] inside the whole region list; the anchored center
    // section hands each side of the anchor a slice. When the entries are not
    // contiguous (a pinned run), `indices` gives each one's region index.
    property int offset: 0
    property var indices: []
    function regionIndexOf(index) { return indices.length > 0 ? indices[index] : offset + index }
    // A hidden list must not build its modules. The center section declares
    // both an anchored and an unanchored arrangement and shows whichever
    // fits, so building both would mount every center module twice — two
    // IPC handlers per target, two clocks ticking.
    readonly property bool built: visible && entries.length > 0

    visible: entries.length > 0
    implicitWidth: listRow.implicitWidth
    implicitHeight: listRow.implicitHeight
    width: implicitWidth
    height: implicitHeight

    Row {
      id: listRow
      spacing: 0

      Repeater {
        model: moduleListRoot.built ? moduleListRoot.entries : []

        ModuleSlot {
          required property int index
          required property var modelData
          entry: modelData
          region: moduleListRoot.region
          regionIndex: moduleListRoot.regionIndexOf(index)
        }
      }
    }
  }

  // A side section as a carousel strip. Every entry is mounted and given an
  // x from BarModel.ringView: flat when everything fits, otherwise on an
  // endless ring scrolled by `offset`, with the widgets under the pointer
  // magnified and tilted like a dock.
  component ScrollDeck: Item {
    id: strip

    property var entries: []
    property string region: ""
    // Region index of each entry (the pinned ones are not on the strip).
    property var indices: []
    // Right-side decks are home showing their tail, so the corner widgets
    // keep their corner and scrolling reveals the ones nearer the center.
    property bool fromEnd: false
    property real budget: 0
    readonly property var pinnedIds: {
      var all = root.layoutEntries(region)
      var out = []
      for (var i = 0; i < all.length; i++) if (root.isPinnedEntry(all[i])) out.push(root.entryId(all[i]))
      return out
    }

    readonly property bool built: visible && entries.length > 0
    property var widths: []
    readonly property var measured: widths.slice(0, entries.length)
    readonly property real total: BarModel.cumulativeWidths(measured)[measured.length] || 0
    // Whether the strip scrolls at all. A few pixels over the budget still
    // count as fitting (they eat into the gap), and the decision has
    // hysteresis so a strip whose widgets breathe around the threshold does
    // not flip between flat and ring.
    property bool overflowing: false
    function decideOverflow() {
      // Fitting always wins; the band only delays turning the ring on, so a
      // strip that momentarily overflowed while the bar was still measuring
      // itself at startup settles back to flat.
      if (overflowing) { if (total <= budget + 0.5) overflowing = false }
      else if (total > budget + root.fitTolerance) overflowing = true
    }
    onTotalChanged: decideOverflow()
    onBudgetChanged: decideOverflow()
    readonly property real viewport: overflowing ? Math.max(0, budget) : total
    readonly property real ring: total + (overflowing ? root.loopGap : 0)
    readonly property real homeOffset: BarModel.homeOffset(total, viewport, fromEnd)
    // The shared target from the bar; `offset` follows it with easing.
    readonly property real targetOffset: overflowing ? root.offsetOf(region) : 0
    property real offset: 0
    property bool easing: true
    property bool hovering: false
    property real focalX: 0
    // 0 → 1 as the pointer arrives, so magnification fades in and out.
    property real magnifyLevel: 0

    readonly property var view: BarModel.ringView(measured, viewport, ring, offset, overflowing,
      hovering ? focalX : null, root.magnify * magnifyLevel, root.magnifyRadius, root.tilt)
    readonly property int hiddenCount: {
      var count = 0
      for (var i = 0; i < view.shown.length; i++) if (measured[i] > 0 && !view.shown[i]) count++
      return count
    }

    function setWidth(index, value) {
      var w = Math.max(0, Number(value) || 0)
      if (widths[index] === w) return
      var next = widths.slice()
      next[index] = w
      widths = next
    }

    function offsetToReveal(index) {
      return BarModel.offsetToReveal(measured, viewport, ring, offset, index)
    }

    // Home moves when the center section breathes (the tail must stay flush
    // right). A strip that is home follows it at once instead of drifting
    // there seconds later.
    property real lastHome: homeOffset
    onHomeOffsetChanged: {
      // Judge by the shared target, not the eased offset: widths arrive one
      // by one at startup and home moves faster than the easing settles.
      var target = root.offsetOf(region)
      if (overflowing && Math.abs(target - BarModel.nearestHome(target, lastHome, ring)) < 0.5)
        root.setOffset(region, BarModel.nearestHome(target, homeOffset, ring), false)
      lastHome = homeOffset
    }
    // The moment a strip starts scrolling it should be home, not at offset 0.
    onOverflowingChanged: if (overflowing && root.isHome(region) === false && Math.abs(root.offsetOf(region)) < 0.5) root.setOffset(region, homeOffset, false)

    // A change by a whole number of rings draws identically, so take it
    // without easing: that is how the bar folds an offset back onto [0, ring).
    onTargetOffsetChanged: {
      var delta = targetOffset - offset
      var turns = ring > 0 ? Math.round(Math.abs(delta) / ring) : 0
      if (turns > 0 && Math.abs(Math.abs(delta) - turns * ring) < 0.5) {
        easing = false
        offset = targetOffset
        easing = true
      } else {
        offset = targetOffset
      }
    }

    Behavior on offset {
      enabled: strip.easing && root.scrollAnimationMs > 0
      NumberAnimation { duration: root.scrollAnimationMs; easing.type: Easing.OutCubic }
    }
    Behavior on magnifyLevel {
      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    visible: entries.length > 0
    implicitWidth: viewport
    implicitHeight: root.barSize
    width: implicitWidth
    height: implicitHeight
    clip: overflowing

    Behavior on width {
      enabled: root.scrollAnimationMs > 0
      NumberAnimation { duration: root.scrollAnimationMs; easing.type: Easing.OutCubic }
    }

    Component.onCompleted: root.registerDeck(strip)
    Component.onDestruction: root.unregisterDeck(strip)

    HoverHandler {
      id: stripHover
      enabled: strip.overflowing && root.magnify > 0
      onPointChanged: strip.focalX = point.position.x
      onHoveredChanged: {
        strip.hovering = hovered
        strip.magnifyLevel = hovered ? 1 : 0
      }
    }

    Repeater {
      model: strip.built ? strip.entries : []

      ModuleSlot {
        required property int index
        required property var modelData

        entry: modelData
        region: strip.region
        regionIndex: strip.indices.length > 0 ? strip.indices[index] : index
        deck: strip
        deckIndex: index
        shown: strip.view.shown[index] === true
        x: strip.view.x[index] || 0
        anchors.verticalCenter: parent.verticalCenter
        magnifyScale: strip.view.s[index] || 1
        tiltAngle: strip.view.a[index] || 0

        onImplicitWidthChanged: strip.setWidth(index, implicitWidth)
        Component.onCompleted: strip.setWidth(index, implicitWidth)
      }
    }
  }

  // One end of a scrolling strip. The widgets fade under a wash of bar
  // colour and a chevron breathes, saying there is more this way. Clicking it
  // scrolls a notch that way; the wheel scrolls too.
  component EdgeHint: Item {
    id: hint

    property var deck: null
    property bool atEnd: false
    readonly property bool active: root.edgeHints && deck !== null && deck.built && deck.overflowing
    readonly property bool tooltipHovered: false

    visible: active
    width: root.edgeHintWidth
    height: root.barSize
    x: deck ? (atEnd ? deck.x + deck.width - width : deck.x) : 0
    y: deck ? deck.y : 0
    z: 20

    Rectangle {
      anchors.fill: parent
      visible: !root.transparent
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: hint.atEnd ? 0.0 : 0.0; color: hint.atEnd ? "transparent" : root.background }
        GradientStop { position: 1.0; color: hint.atEnd ? root.background : "transparent" }
      }
    }

    Text {
      id: chevron
      anchors.verticalCenter: parent.verticalCenter
      x: hint.atEnd ? parent.width - implicitWidth - Style.space(3) : Style.space(3)
      textFormat: Text.PlainText
      text: hint.atEnd ? "\u203a" : "\u2039"
      color: Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.body + 6
      font.bold: true
      renderType: Text.NativeRendering

      SequentialAnimation on opacity {
        running: hint.visible
        loops: Animation.Infinite
        NumberAnimation { from: 0.35; to: 1; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0.35; duration: 900; easing.type: Easing.InOutSine }
      }
      SequentialAnimation on anchors.verticalCenterOffset {
        running: hint.visible
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 0; duration: 1800 }
      }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor

      onClicked: function(mouse) {
        if (!hint.deck) return
        if (mouse.button === Qt.RightButton) { root.scrollHome(hint.deck.region, true); return }
        root.scrollBy(hint.deck.region, hint.atEnd ? root.scrollStep : -root.scrollStep)
      }

      onWheel: function(wheel) {
        if (hint.deck) root.scrollWheel(hint.deck.region, wheel)
      }
    }
  }

  component ModuleSlot: Item {
    id: slot

    required property var entry
    property string region: ""
    // Set by the list or deck that owns the slot. regionIndex is the entry's
    // index in the whole region list; deck/deckIndex are set only on a side
    // strip, where `shown` is false while the slot is scrolled past the edge
    // and magnifyScale/tiltAngle carry the dock effect.
    property int regionIndex: -1
    property var deck: null
    property int deckIndex: -1
    property bool shown: true
    property real magnifyScale: 1
    property real tiltAngle: 0
    readonly property var ref: BarModel.entryRef(root.layoutEntries(region), regionIndex)
    readonly property string moduleName: root.entryId(entry)
    readonly property var moduleSettings: root.entrySettings(entry)
    readonly property string customType: root.customModuleType(entry)
    // Re-evaluate when the registry mutates (Component reference changes,
    // plugin enabled/disabled, etc.). Reading the `widgets` property creates
    // the binding dependency — the wrapped function call alone wouldn't.
    readonly property var registryComponent: {
      var w = root.barWidgetRegistry.widgets
      if (customType) return null
      var registryName = root.canonicalWidgetId(moduleName)
      return w[registryName] ? w[registryName].component : null
    }
    readonly property bool qmlCustom: customType === "qml"
    readonly property bool commandCustom: customType === "command"
    readonly property bool registered: registryComponent !== null
    readonly property var activeItem: {
      if (registered) return registryLoader.item
      if (qmlCustom) return qmlLoader.item
      return componentLoader.item
    }
    readonly property bool hovered: moduleHover.hovered
    readonly property bool dragSource: root.barDragSource === slot
    readonly property bool panelOpen: root.activePopout === slot.activeItem
    // Modules bigger than the mark they want (a text label in a padded slot,
    // a multi-line stack on a vertical bar) can say how long the open-panel
    // dot should be along the bar, so it tracks what the module paints
    // instead of a fraction of whatever slot it happens to fill.
    readonly property real panelIndicatorExtent: {
      var key = root.vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth"
      var hint = activeItem && key in activeItem ? activeItem[key] : undefined
      if (hint !== undefined && hint !== null && hint > 0) return Math.round(hint)
      return Math.max(Style.space(10), Math.round((root.vertical ? slot.height : slot.width) * 0.55))
    }
    implicitWidth: activeItem && activeItem.visible ? (root.vertical ? root.barSize : activeItem.implicitWidth) : 0
    implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight
    z: modulePointer.dragging ? 100 : (magnifyScale > 1.001 ? 1 + magnifyScale : 0)

    // The dock effect: swell toward the pointer and tilt away from it around
    // the vertical axis, so the strip reads as a ring curving into the bar.
    transform: [
      Rotation {
        origin.x: slot.width / 2
        origin.y: slot.height / 2
        axis { x: 0; y: 1; z: 0 }
        angle: slot.tiltAngle
      },
      Scale {
        origin.x: slot.width / 2
        origin.y: slot.height / 2
        xScale: slot.magnifyScale
        yScale: slot.magnifyScale
      }
    ]

    Component.onCompleted: root.registerModuleSlot(slot)
    Component.onDestruction: {
      if (root.barDragSource === slot) root.clearBarDrag()
      root.unregisterModuleSlot(slot)
    }

    HoverHandler { id: moduleHover }

    BorderSurface {
      visible: slot.dragSource
      anchors.fill: parent
      anchors.margins: Style.space(1)
      color: root.transparent ? "transparent" : root.background
      borderSpec: Border.flat(root.barForeground, 1)
      radius: Math.min(Style.cornerRadius, height / 2)
      opacity: root.transparent ? 0.22 : 0.32
    }

    Loader {
      id: componentLoader
      active: !slot.qmlCustom && !slot.registered
      sourceComponent: slot.commandCustom ? customCommandModuleComponent : emptyModuleComponent
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: registryLoader
      active: slot.registered
      sourceComponent: slot.registered ? slot.registryComponent : null
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: qmlLoader
      active: slot.qmlCustom
      source: slot.qmlCustom ? root.customModuleSource(slot.entry) : ""
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Rectangle {
      id: openPanelIndicator

      readonly property int inset: Style.space(2)

      visible: opacity > 0
      opacity: slot.panelOpen && !slot.dragSource ? 0.9 : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
      width: root.vertical ? Style.space(2) : slot.panelIndicatorExtent
      height: root.vertical ? slot.panelIndicatorExtent : Style.space(2)
      // The mark sits on the module's inner edge — the one facing the
      // desktop — so it underlines a top bar, overlines a bottom one, and
      // points inward from a left or right one. It reads as pointing at the
      // panel that opens on that side.
      x: root.vertical
        ? (root.position === "left" ? parent.width - width - inset : inset)
        : Math.round((parent.width - width) / 2)
      y: root.vertical
        ? Math.round((parent.height - height) / 2)
        : (root.position === "top" ? parent.height - height - inset : inset)
      z: 50

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
    }

    MouseArea {
      id: modulePointer

      property bool dragging: false
      property bool suppressClick: false
      property real pressedX: 0
      property real pressedY: 0
      readonly property bool canReorder: root.shell && typeof root.shell.mutateShellConfig === "function"
      readonly property real dragThreshold: Style.space(4)

      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      // A drag must survive its own strip scrolling under it (wheel while
      // pressed), so the area only follows `shown` when idle.
      enabled: slot.visible && slot.width > 0 && slot.height > 0 && (slot.shown || slot.deck === null || dragging || slot.deck.view.on[slot.deckIndex] === true)
      propagateComposedEvents: true
      cursorShape: root.moduleClickTargetAt(slot, mouseX, mouseY) ? Qt.PointingHandCursor : Qt.ArrowCursor
      // Do not assign drag.target here: ModuleSlot is owned by Row/Column
      // positioners, and mutating slot.x/slot.y can leave stale offsets that
      // make neighboring modules overlap after a small aborted drag.

      onPressed: function(mouse) {
        dragging = false
        suppressClick = false
        pressedX = mouse.x
        pressedY = mouse.y
        root.clearBarDrag()
        root.holdFromClick(slot.region)
      }

      onPositionChanged: function(mouse) {
        if (!canReorder || !(mouse.buttons & Qt.LeftButton)) return

        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance >= dragThreshold) {
          if (!dragging) {
            root.barDragWindow = root.targetWindow(slot.activeItem) || root.targetWindow(slot)
            root.barDragScreen = root.barDragWindow ? root.barDragWindow.screen : null
            root.barDragOffsetX = pressedX
            root.barDragOffsetY = pressedY
            root.captureBarDragGhost(slot)
            root.barDragSource = slot
          }
          dragging = true
          root.hideTooltip(slot.activeItem)
        }

        if (dragging) {
          var scenePoint = slot.mapToItem(null, mouse.x, mouse.y)
          var screenPoint = root.barDragScreenPoint(scenePoint)
          root.barDragSceneX = scenePoint.x
          root.barDragSceneY = scenePoint.y
          root.barDragScreenX = screenPoint.x
          root.barDragScreenY = screenPoint.y

          var drop = root.moduleDropAtScene(scenePoint, slot)
          root.barDragTarget = drop ? drop.slot : null
          root.barDragAfter = drop ? drop.after : false
          root.barDragTargetGeometry = drop ? root.dropMarkerRect(drop.slot, drop.after) : null
        }
      }

      onReleased: function(mouse) {
        var wasDragging = dragging
        var targetSlot = root.barDragTarget
        var afterTarget = root.barDragAfter

        if (wasDragging) suppressClick = true

        dragging = false
        root.clearBarDrag()

        if (wasDragging && targetSlot) {
          root.dropBarModuleAtTarget(slot, targetSlot, afterTarget)
          mouse.accepted = true
        } else if (!wasDragging) {
          mouse.accepted = false
        }
      }

      onCanceled: {
        dragging = false
        suppressClick = false
        root.clearBarDrag()
      }

      onClicked: function(mouse) {
        if (suppressClick) {
          suppressClick = false
          mouse.accepted = true
          return
        }

        if (!root.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y)) mouse.accepted = false
      }

      // On a strip that overflows, the wheel scrolls the strip even over a
      // widget that would otherwise take it (volume, brightness). Hold Ctrl
      // to reach the widget instead. When everything fits, the widget keeps
      // the wheel as before.
      onWheel: function(wheel) {
        var strip = slot.deck
        if (!strip || !strip.overflowing || !root.wheelScrolling || (wheel.modifiers & Qt.ControlModifier)) {
          wheel.accepted = false
          return
        }
        wheel.accepted = root.scrollWheel(strip.region, wheel)
      }
    }

    onActiveItemChanged: Qt.callLater(injectProps)
    onModuleSettingsChanged: injectProps()

    function injectProps() {
      var target = activeItem
      if (!target) return
      if ("bar" in target) target.bar = root
      if ("moduleName" in target) target.moduleName = moduleName
      if ("settings" in target) target.settings = moduleSettings
    }

    Component {
      id: customCommandModuleComponent
      CustomCommandModule { entry: slot.entry }
    }
  }

  component CustomCommandModule: WidgetButton {
    id: customRoot

    required property var entry
    readonly property string moduleName: root.entryId(entry)
    readonly property var settings: root.entrySettings(entry)
    property string outputText: ""
    property string outputTooltip: ""
    property bool outputActive: false

    function setting(name, fallback) {
      var value = settings ? settings[name] : undefined
      return value === undefined || value === null ? fallback : value
    }

    function update(raw) {
      var data = Util.parseModuleJson(raw)
      var klass = data.class || data.alt || ""

      outputText = data.text || String(raw || "").trim()
      outputTooltip = data.tooltip || String(setting("tooltip", ""))
      outputActive = klass === "active" || (Array.isArray(klass) && klass.indexOf("active") !== -1)
    }

    bar: root
    text: outputText || String(setting("text", ""))
    tooltipText: outputTooltip || String(setting("tooltip", ""))
    active: outputActive
    keepSpace: setting("keepSpace", false) === true
    horizontalMargin: Number(setting("horizontalMargin", 7.5))
    verticalPadding: Number(setting("verticalPadding", 6))
    fontSize: Number(setting("fontSize", 12))

    onPressed: function(button) {
      var command = ""
      if (button === Qt.RightButton)
        command = String(setting("onRightClick", ""))
      else if (button === Qt.MiddleButton)
        command = String(setting("onMiddleClick", ""))
      else
        command = String(setting("onClick", ""))

      if (command) root.run(command)
    }

    Process {
      id: customProc
      command: ["bash", "-lc", String(customRoot.setting("exec", ""))]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: customRoot.update(text)
      }
    }

    Timer {
      interval: Math.max(1, Number(customRoot.setting("interval", 5))) * 1000
      running: String(customRoot.setting("exec", "")) !== ""
      repeat: true
      triggeredOnStart: true
      onTriggered: root.runProcess(customProc)
    }
  }
}

// Which outputs carry the bar and the notification popups, and on which edge.
// Bar.qml, Panel.qml, MonitorLayoutPicker.qml and Service.qml all read
// placements through here.

function normalizeBarEdge(edge) {
  var value = String(edge || "top").toLowerCase()
  if (value === "bottom" || value === "left" || value === "right") return value
  return "top"
}

function normalizeVertical(position) {
  return String(position || "top") === "bottom" ? "bottom" : "top"
}

function normalizeAlign(align) {
  var value = String(align || "right").toLowerCase()
  if (value === "left") return "left"
  if (value === "center" || value === "middle" || value === "centre") return "center"
  return "right"
}

function screenNames(screens) {
  var out = []
  if (!screens) return out
  for (var i = 0; i < screens.length; i++) {
    if (screens[i] && screens[i].name)
      out.push(String(screens[i].name))
  }
  return out
}

function findPlacement(placements, output) {
  var name = String(output || "")
  var list = placements || []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (p && String(p.output) === name)
      return p
  }
  return null
}

// One entry per output; a later entry for the same output wins.
function dedupeByOutput(placements) {
  var seen = {}
  var out = []
  for (var i = placements.length - 1; i >= 0; i--) {
    var p = placements[i]
    if (!p) continue
    var name = String(p.output || "")
    if (!name || seen[name]) continue
    seen[name] = true
    out.unshift(p)
  }
  return out
}

function mapPlacements(list, normalize) {
  var out = []
  if (!Array.isArray(list)) return out
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!entry) continue
    var output = String(entry.output || "").trim()
    if (output) out.push(normalize(output, entry))
  }
  return dedupeByOutput(out)
}

function readBarPlacements(barConfig) {
  return mapPlacements((barConfig || {}).placements, function(output, entry) {
    return { output: output, position: normalizeBarEdge(entry.position) }
  })
}

// Plugins can only persist the bar subtree, so the notification placements
// live in bar.notificationPlacements. notifications.placements is read as a
// fallback for configs written before that.
function readNotificationPlacements(shellConfig) {
  var config = shellConfig || {}
  var bar = config.bar || {}
  var list = Array.isArray(bar.notificationPlacements)
    ? bar.notificationPlacements
    : (config.notifications || {}).placements
  return mapPlacements(list, function(output, entry) {
    return {
      output: output,
      position: normalizeVertical(entry.position),
      align: normalizeAlign(entry.align)
    }
  })
}

// The connected screens that should carry something placed per output. No
// placements means every screen. When none of the placed outputs is
// connected, the first screen stands in so the bar or popups never vanish.
function screensForPlacements(placements, screens) {
  var list = screens || []
  if (!Array.isArray(placements) || placements.length === 0)
    return list

  var out = []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && findPlacement(placements, list[i].name))
      out.push(list[i])
  }
  if (out.length === 0 && list.length > 0) out.push(list[0])
  return out
}

function hasBarEdge(placements, output, edge) {
  var entry = findPlacement(placements, output)
  if (!entry) return false
  return normalizeBarEdge(entry.position) === normalizeBarEdge(edge)
}

function hasNotificationAlign(placements, output, edge, align) {
  var entry = findPlacement(placements, output)
  if (!entry) return false
  return normalizeVertical(entry.position) === normalizeVertical(edge)
    && normalizeAlign(entry.align) === normalizeAlign(align)
}

// The bar is one object shared by every widget, so it has one edge. Choosing
// an edge on any output moves every bar placement to it.
function toggleBarPlacementForOutput(placements, output, edge) {
  var name = String(output || "")
  var next = normalizeBarEdge(edge)
  if (!name) return placements || []

  var list = Array.isArray(placements) ? placements : []
  var current = findPlacement(list, name)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p || String(p.output) === name) continue
    out.push({ output: String(p.output), position: next })
  }

  if (current && normalizeBarEdge(current.position) === next)
    return out

  out.push({ output: name, position: next })
  return out
}

function toggleNotificationPlacement(placements, output, edge, align) {
  var name = String(output || "")
  var vertical = normalizeVertical(edge)
  var horizontal = normalizeAlign(align)
  if (!name) return placements || []

  var list = Array.isArray(placements) ? placements : []
  var current = findPlacement(list, name)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p || String(p.output) === name) continue
    out.push({
      output: String(p.output),
      position: normalizeVertical(p.position),
      align: normalizeAlign(p.align)
    })
  }

  if (current
      && normalizeVertical(current.position) === vertical
      && normalizeAlign(current.align) === horizontal)
    return out

  out.push({ output: name, position: vertical, align: horizontal })
  return out
}

function applyBarPlacements(mutator, placements) {
  mutator(function(config) {
    if (!config.bar || typeof config.bar !== "object") config.bar = {}
    config.bar.placements = dedupeByOutput(placements)
    delete config.bar.output
    if (!config.bar.id) config.bar.id = "evo.monitors"
    if (config.bar.placements.length > 0)
      config.bar.position = config.bar.placements[0].position
  })
}

function applyNotificationsPlacements(mutator, placements) {
  mutator(function(config) {
    if (!config.bar || typeof config.bar !== "object") config.bar = {}
    config.bar.notificationPlacements = placements
  })
}

function resetOmarchyLayout(mutator, screens) {
  var names = screenNames(screens)
  var layout = { barPlacements: [], notificationsPlacements: [] }
  for (var i = 0; i < names.length; i++) {
    layout.barPlacements.push({ output: names[i], position: "top" })
    layout.notificationsPlacements.push({ output: names[i], position: "top", align: "right" })
  }
  applyBarPlacements(mutator, layout.barPlacements)
  applyNotificationsPlacements(mutator, layout.notificationsPlacements)
  return layout
}

// Where a screen's popup column sits. The bar's own edge gets the bar's
// clearance instead of the plain gap.
function popupPlacementForScreen(notificationPlacement, barEdge, barClearance, gapsOut) {
  var placement = notificationPlacement || {}
  var vertical = normalizeVertical(placement.position)
  var align = normalizeAlign(placement.align)
  var edge = barEdge ? normalizeBarEdge(barEdge) : ""
  var clearance = Number(barClearance)
  var gap = Number(gapsOut)
  if (!isFinite(clearance)) clearance = 0
  if (!isFinite(gap)) gap = 0

  var margins = { top: gap, bottom: gap, left: gap, right: gap }
  if (vertical === "top" && edge === "top") margins.top = clearance
  if (vertical === "bottom" && edge === "bottom") margins.bottom = clearance
  if (align === "right" && edge === "right") margins.right = clearance
  if (align === "left" && edge === "left") margins.left = clearance

  return { vertical: vertical, align: align, margins: margins }
}

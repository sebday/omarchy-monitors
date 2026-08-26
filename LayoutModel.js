function normalizeBarEdge(edge) {
  var value = String(edge || "top").toLowerCase()
  if (value === "bottom" || value === "left" || value === "right") return value
  return "top"
}

function normalizeAlign(align) {
  var value = String(align || "right").toLowerCase()
  if (value === "left" || value === "center" || value === "middle" || value === "centre")
    return value === "left" ? "left" : "center"
  return "right"
}

function normalizePlacements(placements, legacyOutput, legacyPosition, options) {
  options = options || {}
  var preserveAlign = !!options.preserveAlign
  var out = []
  if (Array.isArray(placements)) {
    for (var i = 0; i < placements.length; i++) {
      var entry = placements[i]
      if (!entry) continue
      var output = String(entry.output || "").trim()
      if (!output) continue
      var normalized = {
        output: output,
        position: options.barEdges
          ? normalizeBarEdge(entry.position)
          : String(entry.position || "top")
      }
      if (preserveAlign)
        normalized.align = normalizeAlign(entry.align)
      out.push(normalized)
    }
  }
  if (out.length === 0 && legacyOutput) {
    var legacy = {
      output: String(legacyOutput).trim(),
      position: String(legacyPosition || "top")
    }
    if (preserveAlign)
      legacy.align = "right"
    out.push(legacy)
  }
  return out
}

function findBarPlacement(placements, output) {
  var name = String(output || "")
  for (var i = 0; i < placements.length; i++) {
    var p = placements[i]
    if (p && String(p.output) === name)
      return p
  }
  return null
}

function hasBarEdge(placements, output, edge) {
  var entry = findBarPlacement(placements, output)
  if (!entry) return false
  return normalizeBarEdge(entry.position) === normalizeBarEdge(edge)
}

function hasPlacement(placements, output, position) {
  var name = String(output || "")
  var edge = String(position || "")
  if (!name || !edge) return false
  for (var i = 0; i < placements.length; i++) {
    var p = placements[i]
    if (p && String(p.output) === name && String(p.position) === edge)
      return true
  }
  return false
}

function findNotificationPlacement(placements, output) {
  var name = String(output || "")
  for (var i = 0; i < placements.length; i++) {
    var p = placements[i]
    if (p && String(p.output) === name)
      return p
  }
  return null
}

function hasNotificationAlign(placements, output, edge, align) {
  var entry = findNotificationPlacement(placements, output)
  if (!entry) return false
  var vertical = edge === "bottom" ? "bottom" : "top"
  return String(entry.position || "top") === vertical
    && normalizeAlign(entry.align) === normalizeAlign(align)
}

function toggleBarPlacementForOutput(placements, output, edge) {
  var name = String(output || "")
  var next = normalizeBarEdge(edge)
  if (!name) return placements || []

  var out = []
  var current = null
  var list = Array.isArray(placements) ? placements : []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p) continue
    var pOut = String(p.output)
    if (pOut === name) {
      current = { output: pOut, position: normalizeBarEdge(p.position) }
      continue
    }
    out.push({
      output: pOut,
      position: normalizeBarEdge(p.position)
    })
  }

  if (current && current.position === next)
    return out

  out.push({ output: name, position: next })
  return out
}

function togglePlacement(placements, output, position) {
  var name = String(output || "")
  var edge = String(position || "top")
  if (!name) return placements || []

  var out = []
  var removed = false
  var list = Array.isArray(placements) ? placements : []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p) continue
    if (String(p.output) === name && String(p.position) === edge) {
      removed = true
      continue
    }
    out.push({
      output: String(p.output),
      position: String(p.position || "top")
    })
  }
  if (!removed)
    out.push({ output: name, position: edge })
  return out
}

function toggleNotificationPlacement(placements, output, edge, align) {
  var name = String(output || "")
  var vertical = edge === "bottom" ? "bottom" : "top"
  var horizontal = normalizeAlign(align)
  if (!name) return placements || []

  var out = []
  var current = null
  var list = Array.isArray(placements) ? placements : []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p) continue
    var pOut = String(p.output)
    if (pOut === name) {
      current = {
        output: pOut,
        position: String(p.position || "top") === "bottom" ? "bottom" : "top",
        align: normalizeAlign(p.align)
      }
      continue
    }
    out.push({
      output: pOut,
      position: String(p.position || "top") === "bottom" ? "bottom" : "top",
      align: normalizeAlign(p.align)
    })
  }

  if (current
      && current.position === vertical
      && current.align === horizontal)
    return out

  out.push({
    output: name,
    position: vertical,
    align: horizontal
  })
  return out
}

function outputsFromPlacements(placements) {
  var seen = {}
  var out = []
  for (var i = 0; i < placements.length; i++) {
    var name = String(placements[i].output || "")
    if (!name || seen[name]) continue
    seen[name] = true
    out.push(name)
  }
  return out
}

function positionForOutput(placements, output, fallback) {
  var name = String(output || "")
  for (var i = 0; i < placements.length; i++) {
    var p = placements[i]
    if (p && String(p.output) === name)
      return String(p.position || fallback || "top")
  }
  return String(fallback || "top")
}

function alignForOutputEdge(placements, output, edge, fallback) {
  var entry = findNotificationPlacement(placements, output)
  if (!entry) return normalizeAlign(fallback || "right")
  var vertical = String(entry.position || "top") === "bottom" ? "bottom" : "top"
  var requested = edge === "bottom" ? "bottom" : "top"
  if (vertical !== requested)
    return normalizeAlign(fallback || "right")
  return normalizeAlign(entry.align)
}

function dedupeBarPlacements(placements) {
  var seen = {}
  var out = []
  for (var i = placements.length - 1; i >= 0; i--) {
    var p = placements[i]
    if (!p) continue
    var name = String(p.output || "")
    if (!name || seen[name]) continue
    seen[name] = true
    out.unshift({
      output: name,
      position: normalizeBarEdge(p.position)
    })
  }
  return out
}

function dedupeNotificationPlacements(placements) {
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

function screenNames(screens) {
  var out = []
  if (!screens) return out
  for (var i = 0; i < screens.length; i++) {
    if (screens[i] && screens[i].name)
      out.push(String(screens[i].name))
  }
  return out
}

function omarchyDefaultLayout(screens) {
  var names = screenNames(screens)
  var barPlacements = []
  var notificationsPlacements = []
  for (var i = 0; i < names.length; i++) {
    barPlacements.push({ output: names[i], position: "top" })
    notificationsPlacements.push({
      output: names[i],
      position: "top",
      align: "right"
    })
  }
  return {
    barPlacements: barPlacements,
    notificationsPlacements: notificationsPlacements
  }
}

function readLayoutState(shellConfig) {
  var config = shellConfig || {}
  var bar = config.bar || {}
  var notifications = config.notifications || {}
  return {
    barPlacements: dedupeBarPlacements(normalizePlacements(
      bar.placements,
      bar.output,
      bar.position,
      { barEdges: true }
    )),
    notificationsPlacements: dedupeNotificationPlacements(normalizePlacements(
      notifications.placements,
      notifications.output,
      notifications.position,
      { preserveAlign: true }
    ))
  }
}

function applyBarPlacements(mutator, placements) {
  mutator(function(config) {
    if (!config.bar || typeof config.bar !== "object") config.bar = {}
    config.bar.placements = dedupeBarPlacements(placements)
    delete config.bar.output
    if (!config.bar.id) config.bar.id = "evo.monitors"
    if (config.bar.placements.length > 0)
      config.bar.position = config.bar.placements[0].position
  })
}

function applyNotificationsPlacements(mutator, placements) {
  mutator(function(config) {
    if (!config.notifications || typeof config.notifications !== "object")
      config.notifications = {}
    config.notifications.placements = placements
    delete config.notifications.output
    if (placements.length > 0) {
      config.notifications.position = placements[0].position
      config.notifications.align = normalizeAlign(placements[0].align)
    } else {
      delete config.notifications.align
    }
  })
}

function toggleBarPlacement(mutator, placements, output, position) {
  applyBarPlacements(mutator, toggleBarPlacementForOutput(placements, output, position))
}

function toggleNotificationsPlacement(mutator, placements, output, position, align) {
  applyNotificationsPlacements(
    mutator,
    toggleNotificationPlacement(placements, output, position, align)
  )
}

function resetOmarchyLayout(mutator, screens) {
  var layout = omarchyDefaultLayout(screens)
  applyBarPlacements(mutator, layout.barPlacements)
  applyNotificationsPlacements(mutator, layout.notificationsPlacements)
  return layout
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeAlign: normalizeAlign,
    normalizeBarEdge: normalizeBarEdge,
    normalizePlacements: normalizePlacements,
    findBarPlacement: findBarPlacement,
    hasBarEdge: hasBarEdge,
    hasPlacement: hasPlacement,
    findNotificationPlacement: findNotificationPlacement,
    hasNotificationAlign: hasNotificationAlign,
    toggleBarPlacementForOutput: toggleBarPlacementForOutput,
    toggleNotificationPlacement: toggleNotificationPlacement,
    outputsFromPlacements: outputsFromPlacements,
    positionForOutput: positionForOutput,
    alignForOutputEdge: alignForOutputEdge,
    dedupeBarPlacements: dedupeBarPlacements,
    dedupeNotificationPlacements: dedupeNotificationPlacements,
    screenNames: screenNames,
    omarchyDefaultLayout: omarchyDefaultLayout,
    readLayoutState: readLayoutState,
    applyBarPlacements: applyBarPlacements,
    applyNotificationsPlacements: applyNotificationsPlacements,
    toggleBarPlacement: toggleBarPlacement,
    toggleNotificationsPlacement: toggleNotificationsPlacement,
    resetOmarchyLayout: resetOmarchyLayout
  }
}

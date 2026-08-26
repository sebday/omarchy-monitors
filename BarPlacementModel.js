function normalizeBarEdge(edge) {
  var value = String(edge || "top").toLowerCase()
  if (value === "bottom" || value === "left" || value === "right") return value
  return "top"
}

function normalizeBarPlacements(placements, legacyOutput, legacyPosition) {
  var out = []
  if (Array.isArray(placements)) {
    for (var i = 0; i < placements.length; i++) {
      var entry = placements[i]
      if (!entry) continue
      var output = String(entry.output || "").trim()
      if (!output) continue
      out.push({
        output: output,
        position: normalizeBarEdge(entry.position)
      })
    }
  }
  if (out.length === 0 && legacyOutput) {
    out.push({
      output: String(legacyOutput).trim(),
      position: normalizeBarEdge(legacyPosition)
    })
  }
  return out
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
    out.unshift(p)
  }
  return out
}

function readBarPlacements(barConfig) {
  var config = barConfig || {}
  return dedupeBarPlacements(normalizeBarPlacements(
    config.placements,
    config.output,
    config.position
  ))
}

function screenName(screen) {
  if (!screen) return ""
  return String(screen.name || "")
}

function screensForBar(placements, screens) {
  var list = screens || []
  if (!Array.isArray(placements) || placements.length === 0)
    return list

  var allowed = {}
  for (var i = 0; i < placements.length; i++)
    allowed[String(placements[i].output || "")] = true

  var out = []
  for (var j = 0; j < list.length; j++) {
    var name = screenName(list[j])
    if (name && allowed[name])
      out.push(list[j])
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

function positionForScreen(placements, screen, fallback) {
  var placement = findBarPlacement(placements, screenName(screen))
  if (placement) return normalizeBarEdge(placement.position)
  return normalizeBarEdge(fallback)
}

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "LayoutModel.js" as LayoutModel
import "BarPlacementModel.js" as BarPlacementModel

Panel {
  id: root
  moduleName: "omarchy.monitors"
  ipcTarget: "omarchy.monitors"
  manageIpc: false

  property string internalMonitor: ""
  property string externalMonitor: ""
  property string focusedMonitor: ""
  property string scaleTargetMonitor: ""
  property bool internalEnabled: false
  property bool mirrorEnabled: false
  property string monitorScale: ""
  property var displays: []
  property int enabledDisplayCount: 0

  // Cursor model shared by keyboard and mouse. Sections:
  //   "textsize" - slider sentinel at -1
  //   "scale"    - scale preset row
  // Mouse hover on a target updates root state via the components' `hovered`
  // signal so keyboard cursor and pointer share one highlight.
  property var layoutBarPlacements: []
  property var layoutNotificationsPlacements: []
  readonly property var scalePresets: ["1", "1.25", "1.5", "2", "3", "4"]
  readonly property string monitorStateScript: Qt.resolvedUrl("bin/monitor-state").toString().replace("file://", "")
  readonly property string setScaleScript: Qt.resolvedUrl("bin/set-monitor-scale").toString().replace("file://", "")
  readonly property var scaleValues: {
    var display = scaleTargetDisplay()
    if (display)
      return Model.availableScales(scalePresets, display.width, display.height)
    return scalePresets
  }
  property string focusSection: "scale"
  property int selectedIndex: 0
  property bool cursorActive: false

  // Text size slider — curated macOS-style notches (px). The panel snaps to
  // these stops; the CLI (omarchy-display-text-size) accepts any integer in range.
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  // While a change is in flight, the chosen stop index overrides the live
  // base-size so the knob doesn't snap back during the file round-trip. -1 =
  // no pending change; follow Style.font.baseSize.
  property int textSizePreviewIndex: -1

  // A text-size change reflows the whole panel (both font and spacing scale),
  // which slides rows under a stationary pointer and fires synthetic hover.
  // While true, hover is not allowed to hijack the keyboard focus section —
  // otherwise h/l on the text-size slider can jump focus to another row.
  property bool reflowingText: false
  function markReflowing() {
    root.reflowingText = true
    reflowSettle.restart()
  }

  readonly property var visibleSections: ["textsize", "scale"]

  function sectionCount(section) {
    if (section === "textsize") return 0
    if (section === "scale") return Array.isArray(scaleValues) ? scaleValues.length : 0
    return 0
  }

  function sectionIsSingleRow(section) {
    return section === "textsize" || section === "scale"
  }

  function sectionFirstIndex(section) {
    if (section === "textsize") return -1
    return 0
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (!sections || sections.length === 0) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var inSingleRow = sectionIsSingleRow(focusSection)
    var max = inSingleRow ? 0 : sectionCount(focusSection) - 1

    if (delta > 0) {
      if (!inSingleRow && selectedIndex < max) { selectedIndex = selectedIndex + 1; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionFirstIndex(focusSection)
      }
    } else {
      if (!inSingleRow && selectedIndex > 0) { selectedIndex = selectedIndex - 1; return }
      if (sIdx > 0) {
        var prev = sections[sIdx - 1]
        focusSection = prev
        // Coming up from below — land on the last navigable row of the prev
        // section, or its sentinel for single-row sections.
        selectedIndex = sectionIsSingleRow(prev) ? sectionFirstIndex(prev) : sectionCount(prev) - 1
      }
    }
  }

  // h/l: in scale section, walks the preset row.
  function moveCursorH(delta) {
    if (focusSection !== "scale") return
    var next = selectedIndex + delta
    if (next < 0) next = 0
    if (next > scaleValues.length - 1) next = scaleValues.length - 1
    selectedIndex = next
  }


  function activateCursor() {
    if (focusSection === "scale" && selectedIndex >= 0 && selectedIndex < scaleValues.length) {
      setScale(scaleValues[selectedIndex])
    }
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var count = sectionCount(focusSection)
    if (sectionIsSingleRow(focusSection)) {
      if (focusSection === "textsize") selectedIndex = -1
      else if (selectedIndex < 0 || selectedIndex >= count) selectedIndex = 0
      return
    }
    if (count === 0) {
      var sIdx = sections.indexOf(focusSection)
      focusSection = sIdx > 0 ? sections[sIdx - 1] : sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    if (selectedIndex > count - 1) selectedIndex = count - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  // Keep the keyboard-focused row inside the viewport when the panel grows
  // taller than its allotted height (lots of displays). Mirrors audio's
  // ensureCursorVisible helper.
  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 6
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin)
      flick.contentY = bottom + margin - flick.height
  }

  function stateIpc() {
    return JSON.stringify({
      focusedMonitor: root.focusedMonitor,
      scale: root.monitorScale,
      displays: root.displays
    })
  }

  IpcHandler {
    target: "omarchy.monitors"

    function state(): string { return root.stateIpc() }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  function normalizeScale(scale) {
    return Model.normalizeScale(scale)
  }

  function scaleTargetDisplay() {
    var target = scaleTargetMonitor || focusedMonitor
    if (!target) return null
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.name === target)
        return display
    }
    return null
  }

  function scaleForTarget() {
    var display = scaleTargetDisplay()
    if (display && display.scale !== undefined && display.scale !== null && display.scale !== "")
      return normalizeScale(display.scale)
    if (!scaleTargetMonitor || scaleTargetMonitor === focusedMonitor)
      return monitorScale
    return ""
  }

  function ensureScaleTarget() {
    if (scaleTargetDisplay()) return
    scaleTargetMonitor = focusedMonitor
  }

  function selectScaleMonitor(output) {
    if (!output) return
    scaleTargetMonitor = String(output)
    focusSection = "scale"
    cursorActive = true
    var idx = activeScaleIndex()
    selectedIndex = idx >= 0 ? idx : 0
    clampCursor()
  }

  function activeScaleIndex() {
    var display = scaleTargetDisplay()
    if (!display) return -1
    return Model.matchingScaleIndex(scaleValues, scaleForTarget(), display.width, display.height)
  }

  function effectiveScale(scale) {
    var display = scaleTargetDisplay()
    if (display)
      return Model.cleanScale(scale, display.width, display.height)
    return normalizeScale(scale)
  }

  function refreshLayoutState() {
    var shellConfig = bar && bar.shell ? bar.shell.shellConfig : null
    var config = shellConfig || {}
    var state = LayoutModel.readLayoutState(shellConfig)
    root.layoutBarPlacements = BarPlacementModel.readBarPlacements(config.bar)
    root.layoutNotificationsPlacements = state.notificationsPlacements
  }

  function mutateShellConfig(mutator) {
    if (!bar || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return
    bar.shell.mutateShellConfig(mutator)
  }

  function toggleBarLayout(output, position) {
    LayoutModel.toggleBarPlacement(
      function(mutator) { root.mutateShellConfig(mutator) },
      root.layoutBarPlacements,
      output,
      position
    )
    refreshLayoutState()
  }

  function toggleNotificationsLayout(output, position, align) {
    var wasActive = LayoutModel.hasNotificationAlign(
      root.layoutNotificationsPlacements, output, position, align)
    LayoutModel.toggleNotificationsPlacement(
      function(mutator) { root.mutateShellConfig(mutator) },
      root.layoutNotificationsPlacements,
      output,
      position,
      align
    )
    refreshLayoutState()
    if (!wasActive)
      showNotificationsPlacementPreview(output, position, align)
  }

  function resetLayoutDefaults() {
    LayoutModel.resetOmarchyLayout(
      function(mutator) { root.mutateShellConfig(mutator) },
      Quickshell.screens
    )
    refreshLayoutState()
  }

  function notificationService() {
    if (!bar || !bar.shell) return null
    return bar.shell.serviceFor("evo.monitors")
  }

  function showNotificationsPlacementPreview(output, position, align) {
    var svc = notificationService()
    if (!svc || typeof svc.showPlacementPreview !== "function") return
    var edge = position === "bottom" ? "bottom" : "top"
    var slot = LayoutModel.normalizeAlign(align)
    var headline = "Notifications here"
    var detail = String(output) + " · " + edge + " · " + slot
    Qt.callLater(function() {
      svc.showPlacementPreview(output, edge, slot, headline, detail)
    })
  }

  function updateDisplays(displaysJson) {
    var parsed = Model.parseDisplays(displaysJson)
    root.displays = parsed.displays
    root.enabledDisplayCount = parsed.enabledDisplayCount
  }

  function setScale(scale) {
    var monitor = scaleTargetMonitor || focusedMonitor
    if (!monitor) return
    actionProc.command = ["bash", setScaleScript, monitor, scale]
    if (!actionProc.running) actionProc.running = true
  }

  // ---- Text size (shell base font + GTK text-scaling, via one CLI) ----
  function nearestTextStop(px) {
    var best = 0
    var bestDist = 1e9
    for (var i = 0; i < textSizeStops.length; i++) {
      var d = Math.abs(textSizeStops[i] - px)
      if (d < bestDist) { bestDist = d; best = i }
    }
    return best
  }

  // Effective stop index: the pending choice while a change is in flight,
  // otherwise whatever Style's live base-size rounds to.
  function currentTextIndex() {
    return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextStop(Style.font.baseSize)
  }

  // px shown in the header: the pending stop if any, else the true base-size
  // (which may be an off-notch value set from the CLI).
  function displayedTextPx() {
    return textSizePreviewIndex >= 0 ? textSizeStops[textSizePreviewIndex] : Style.font.baseSize
  }

  function setTextSize(px) {
    textScaleProc.command = ["omarchy-display-text-size", String(px)]
    if (!textScaleProc.running) textScaleProc.running = true
  }

  function adjustTextSize(deltaSteps) {
    var idx = currentTextIndex() + deltaSteps
    if (idx < 0) idx = 0
    if (idx > textSizeStops.length - 1) idx = textSizeStops.length - 1
    markReflowing()
    textSizePreviewIndex = idx
    setTextSize(textSizeStops[idx])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  // KeyboardPanel primes focus at open-time, so SUPER-bound IPC summons land
  // with j/k ready to navigate. Keep a default landing point, but don't paint
  // the cursor until hover or the first navigation key.
  onOpenedChanged: {
    if (opened) {
      refresh()
      refreshLayoutState()
      focusSection = "scale"
      selectedIndex = 0
      cursorActive = false
      scaleTargetMonitor = ""
    }
  }

  onFocusedMonitorChanged: if (opened && !scaleTargetMonitor) scaleTargetMonitor = focusedMonitor
  onScaleTargetMonitorChanged: clampCursor()

  onDisplaysChanged: clampCursor()
  onScaleValuesChanged: clampCursor()
  onVisibleSectionsChanged: clampCursor()

  // Only poll while the panel is open.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProc
    command: ["bash", root.monitorStateScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        root.internalMonitor = String(lines[0] || "").trim()
        root.externalMonitor = String(lines[1] || "").trim()
        root.internalEnabled = String(lines[2] || "").trim() !== ""
        root.mirrorEnabled = String(lines[3] || "").trim() === root.externalMonitor && root.externalMonitor !== ""
        root.focusedMonitor = String(lines[4] || "").trim()
        root.monitorScale = root.normalizeScale(String(lines[5] || "").trim())
        root.updateDisplays(String(lines[6] || "[]").trim())
        root.ensureScaleTarget()
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.refresh()
  }

  // Applies text size via the CLI, which rewrites the shell override file;
  // Style picks the new base-size up through its own file watch, so there's
  // nothing to refresh here.
  Process {
    id: textScaleProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // Clears the hover-suppression flag once the reflow triggered by a text-size
  // change has settled.
  Timer {
    id: reflowSettle
    interval: 300
    repeat: false
    onTriggered: root.reflowingText = false
  }

  // Once Style's base-size catches up to the pending choice, drop the preview
  // so the slider tracks the live value again. The change itself reflows the
  // panel, so suppress hover for a beat while it lands.
  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      root.markReflowing()
      if (root.textSizePreviewIndex >= 0
          && root.nearestTextStop(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) {
          if (root.focusSection === "textsize") root.adjustTextSize(dx)
          else if (root.focusSection === "scale") root.moveCursorH(dx)
        }
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero: display icon · title/status ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              text: root.displays.length > 1 ? "󰍺" : "󰍹"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Display"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                id: heroLabel
                text: {
                  var monitor = root.scaleTargetMonitor || root.focusedMonitor
                  if (monitor) return monitor.toUpperCase()
                  return "DISPLAY"
                }
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          // ---------- Text size ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(textSizeHeader.implicitHeight, textSizePx.implicitHeight)

              PanelSectionHeader {
                id: textSizeHeader
                text: "TEXT SIZE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: textSizePx
                text: (textSizeSlider.dragging
                       ? root.textSizeStops[Math.round(textSizeSlider.liveValue)]
                       : root.displayedTextPx()) + "px"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: textSizeRow
              width: parent.width
              height: textSizeSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "textsize" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(textSizeRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: textSizeSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0
                maximum: root.textSizeStops.length - 1
                step: 1
                integer: true
                tickCount: root.textSizeStops.length
                value: root.currentTextIndex()
                onReleased: function(v) { root.setTextSize(root.textSizeStops[Math.round(v)]) }
              }

              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.cursorActive = true
                  root.focusSection = "textsize"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Scale ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: Math.max(scaleHeader.implicitHeight, scaleMonitor.implicitHeight)

              PanelSectionHeader {
                id: scaleHeader
                text: "SCALE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              // Name the monitor SCALE targets, since it only applies to the
              // focused one.
              Text {
                id: scaleMonitor
                text: root.scaleTargetMonitor || root.focusedMonitor
                visible: (root.scaleTargetMonitor || root.focusedMonitor) !== ""
                  && root.enabledDisplayCount > 1
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Grid {
              id: scaleRow
              width: parent.width
              columns: root.scaleValues.length
              spacing: Style.spacing.xs

              readonly property real cellWidth: root.scaleValues.length > 0
                ? (width - spacing * (columns - 1)) / columns
                : 0

              Repeater {
                model: root.scaleValues

                ScalePill {
                  required property string modelData
                  required property int index

                  scaleValue: modelData
                  scaleIndex: index
                  width: scaleRow.cellWidth
                }
              }
            }
          }

          // ---------- Layout ----------
          PanelSeparator {
            visible: Quickshell.screens.length > 1
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: 0
            visible: Quickshell.screens.length > 1

            Item {
              width: parent.width
              implicitHeight: layoutHeaderRow.implicitHeight

              PanelSectionHeader {
                id: layoutHeaderRow
                text: "LAYOUT"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xs

                Button {
                  iconText: "󰑐"
                  tooltipText: "Reset defaults (bar top, notifications top-right on all screens)"
                  fontSize: Style.font.caption
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.spacing.sm
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: root.resetLayoutDefaults()
                }
              }
            }

            MonitorLayoutPicker {
              width: parent.width
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              barPlacements: root.layoutBarPlacements
              notificationsPlacements: root.layoutNotificationsPlacements
              selectedMonitor: root.scaleTargetMonitor
              enabled: root.opened
              showWorkspaces: true
              workspaceClickable: false
              onBarChosen: function(output, position) { root.toggleBarLayout(output, position) }
              onNotificationsChosen: function(output, position, align) {
                root.toggleNotificationsLayout(output, position, align)
              }
              onMonitorChosen: function(output) { root.selectScaleMonitor(output) }
            }
          }

          Item {
            width: parent.width
            height: Style.space(4)
          }
        }
      }
    }
  }

  component ScalePill: Button {
    id: pill
    required property string scaleValue
    required property int scaleIndex

    text: root.effectiveScale(scaleValue) + "x"
    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true

    active: root.activeScaleIndex() === scaleIndex
    hasCursor: root.cursorActive && root.focusSection === "scale" && root.selectedIndex === scaleIndex

    onClicked: root.setScale(scaleValue)
    onHovered: function(isHovered) {
      if (!isHovered || root.reflowingText) return
      root.cursorActive = true
      root.focusSection = "scale"
      root.selectedIndex = pill.scaleIndex
    }
  }
}

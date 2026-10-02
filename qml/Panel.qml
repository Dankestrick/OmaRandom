import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Logic.js" as Logic

// The big OmaRandom window. Wheels tab: up to six wheels, centered in rows of
// three. Click a wheel to spin it large; Spin all spins every wheel at once.
// Results tab: the newest round revealed card by card, then the history.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool closingFromHost: false

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "io.github.dankestrick.omarandom"
  readonly property color fg: Color.foreground
  readonly property color dim: Qt.darker(Color.foreground, 1.4)
  readonly property string fontFamily: Style.font.family

  // ---------- Saved data ----------
  readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME")
    || ((Quickshell.env("HOME") || "") + "/.local/share")) + "/omarandom"
  readonly property string dataFile: dataDir + "/omarandom.json"
  property var store: ({ version: 1, wheels: [], results: [] })
  // "loading", "ok" or "unreadable". Nothing is saved unless it's "ok".
  property string loadState: "loading"
  property string loadError: ""

  readonly property var wheels: store.wheels
  readonly property var results: store.results
  readonly property var split: Logic.splitShown(results, store.shown || "")
  property var theme: Logic.CLASSIC.slice()

  // ---------- UI state ----------
  property string tab: "Wheels"
  // Resting angle per wheel id, so a wheel stays where it landed.
  property var angles: ({})

  // Spin view: the wheel shown large.
  property string focusId: ""
  readonly property var focusWheel: wheelById(focusId)
  property var landing: null          // { wheelId, index, saved }
  property bool focusSpinning: false

  // Spin all
  property string spinAllBatch: ""
  property int spinAllPending: 0
  property bool showViewResults: false
  property string revealBatch: ""
  property int revealRun: 0

  property string deleteId: ""
  property string confirmMode: ""     // "delete" or "history"

  function wheelById(id) {
    for (var i = 0; i < wheels.length; i++) if (wheels[i].id === id) return wheels[i]
    return null
  }

  function update(fn) {
    if (loadState !== "ok") return
    var d = JSON.parse(JSON.stringify(store))
    fn(d)
    store = d
    saveTimer.restart()
  }

  function addWheel() {
    if (wheels.length >= Logic.MAX_WHEELS) return
    var w = Logic.makeWheel(Logic.nextWheelName(wheels))
    update(function(d) { d.wheels.push(w) })
  }

  function replaceWheel(w) {
    var clean = Logic.cleanWheel(w)
    if (!clean) return
    update(function(d) {
      for (var i = 0; i < d.wheels.length; i++) if (d.wheels[i].id === clean.id) d.wheels[i] = clean
    })
  }

  function editWheel(id) {
    var w = wheelById(id)
    if (w && spinAllPending === 0) editor.openFor(w)
  }

  function deleteWheel(id) {
    if (focusId === id) closeFocus(true)
    update(function(d) {
      d.wheels = d.wheels.filter(function(w) { return w.id !== id })
    })
  }

  function addResult(wheel, index, batch) {
    var opt = wheel.options[index]
    if (!opt) return
    var r = {
      id: Logic.newId(), batch: batch, wheelId: wheel.id, wheel: wheel.name,
      label: opt.label || ("Option " + (index + 1)),
      color: Logic.sliceColor(wheel, index, theme), image: opt.image || "", time: Date.now()
    }
    update(function(d) {
      d.shown = ""
      d.results.unshift(r)
      if (d.results.length > Logic.MAX_RESULTS) d.results.length = Logic.MAX_RESULTS
    })
  }

  function setAngle(id, a) {
    var copy = {}
    for (var k in angles) copy[k] = angles[k]
    copy[id] = Logic.norm(a)
    angles = copy
  }

  // ---------- Spin view ----------
  function openFocus(id, card) {
    if (anySpinning()) return
    var w = wheelById(id)
    if (!w) return
    focusId = id
    landing = null
    var from = card ? card.mapToItem(focusLayer, 0, 0) : null
    focusLayer.showFrom(from ? Qt.rect(from.x, from.y, card.width, card.height) : null)
  }

  function closeFocus(instant) {
    if (!focusId) return
    if (bigWheel.spinning) bigWheel.finishNow()
    focusLayer.hide(instant === true)
  }

  function spinFocus() {
    if (!focusWheel || bigWheel.spinning) return
    landing = null
    bigWheel.spin(Logic.pickIndex(focusWheel.options.length))
  }

  function saveLanding() {
    if (!landing || landing.saved || !focusWheel) return
    addResult(focusWheel, landing.index, Logic.newId())
    landing = { wheelId: landing.wheelId, index: landing.index, saved: true }
  }

  // ---------- Spin all ----------
  function anySpinning() {
    if (bigWheel.spinning || spinAllPending > 0) return true
    return false
  }

  function spinAll() {
    if (anySpinning() || wheels.length === 0 || loadState !== "ok") return
    showViewResults = false
    spinAllBatch = Logic.newId()
    var started = 0
    for (var i = 0; i < cardRepeater.count; i++) {
      var card = cardRepeater.itemAt(i)
      if (card && card.spinRandom()) started++
    }
    spinAllPending = started
  }

  function cardLanded(wheel, index) {
    addResult(wheel, index, spinAllBatch)
    spinAllPending = Math.max(0, spinAllPending - 1)
    if (spinAllPending === 0) showViewResults = true
  }

  function viewResults() {
    showViewResults = false
    tab = "Results"
  }

  // Empty the top of the Results tab. The round stays in the history.
  function clearTop() {
    update(function(d) { d.shown = "none" })
  }

  // Delete every result except the round shown at the top.
  function clearHistory() {
    var key = split.key
    update(function(d) {
      d.results = d.results.filter(function(r) { return key !== "" && Logic.roundOf(r) === key })
      d.shown = key ? d.shown : ""
    })
  }

  // Bring a round from the history back to the top, revealed again.
  function showRound(key) {
    update(function(d) { d.shown = key })
    revealBatch = key
    revealRun++
  }

  function finishAllSpins() {
    if (bigWheel.spinning) bigWheel.finishNow()
    for (var i = 0; i < cardRepeater.count; i++) {
      var card = cardRepeater.itemAt(i)
      if (card) card.finishNow()
    }
  }

  onTabChanged: {
    if (tab === "Results" && split.top.length && split.key === spinAllBatch
        && spinAllBatch !== "" && revealBatch !== spinAllBatch) {
      revealBatch = spinAllBatch
      revealRun++
    }
  }

  // ---------- Open / close ----------
  function open(payloadJson) {
    closingFromHost = false
    var monitor = Hyprland.focusedMonitor
    var scr = null
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (monitor && Quickshell.screens[i].name === monitor.name) scr = Quickshell.screens[i]
    if (scr) {
      if (!window.visible) window.screen = scr
      window.fitTo(scr)
    }
    themeFile.reload()
    if (loadState === "unreadable") {
      loadState = "loading"
      dataView.reload()
    }
    opened = true
    Qt.callLater(function() { root.takeKeys() })
  }

  function close() {
    closingFromHost = true
    finishAllSpins()
    editor.close()
    confirmMode = ""
    closeFocus(true)
    if (saveTimer.running) { saveTimer.stop(); flush() }
    opened = false
    closingFromHost = false
  }

  // Give keys back to the window (a FocusScope alone would hand them to the
  // last focused text field, even a hidden one).
  function takeKeys() {
    keySink.forceActiveFocus()
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  // ---------- Files ----------
  function flush() {
    if (loadState !== "ok") return
    dataView.setText(Logic.serialize(store))
  }

  Timer { id: saveTimer; interval: 400; onTriggered: root.flush() }

  FileView {
    id: dataView
    path: root.dataFile
    printErrors: false
    atomicWrites: true
    watchChanges: false
    blockLoading: false
    onLoaded: {
      if (root.loadState === "ok") return
      var parsed = Logic.parse(text())
      if (parsed.ok) {
        root.store = parsed.data
        root.loadState = "ok"
      } else {
        root.loadError = parsed.error
        root.loadState = "unreadable"
      }
    }
    onLoadFailed: function(error) {
      if (root.loadState === "ok") return
      if (error === FileViewError.FileNotFound) {
        root.store = Logic.defaults()
        root.loadState = "ok"
      } else {
        root.loadError = "could not be read"
        root.loadState = "unreadable"
      }
    }
  }

  FileView {
    id: themeFile
    path: Color.currentThemePath + "/colors.toml"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.theme = Logic.themePalette(text())
  }

  // ---------- Window ----------
  FloatingWindow {
    id: window
    visible: root.opened
    title: "OmaRandom"
    color: Color.background
    // A fixed size makes Hyprland float and center it with no window rule.
    property size fixed: Qt.size(1440, 900)
    implicitWidth: fixed.width
    implicitHeight: fixed.height
    minimumSize: fixed
    maximumSize: fixed

    function fitTo(scr) {
      var w = Math.max(960, Math.min(1440, scr.width - 120))
      var h = Math.max(640, Math.min(900, scr.height - 120))
      fixed = Qt.size(w, h)
    }

    onVisibleChanged: {
      if (!visible && root.opened && !root.closingFromHost) root.requestClose()
    }

    FocusScope {
      id: keyRoot
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (confirm.handleKey(event)) { event.accepted = true; return }
        if (editor.handleKey(event)) { event.accepted = true; return }
        if (editor.opened || confirm.opened) return
        if (root.focusId !== "") {
          if (event.key === Qt.Key_Escape || event.key === Qt.Key_M) { root.closeFocus(); event.accepted = true }
          else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.spinFocus(); event.accepted = true }
          else if (event.key === Qt.Key_S) { root.saveLanding(); event.accepted = true }
          return
        }
        if (root.showViewResults && root.tab === "Wheels") {
          if (event.key === Qt.Key_Escape) { root.showViewResults = false; event.accepted = true; return }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.viewResults(); event.accepted = true; return }
        }
        if (event.key === Qt.Key_Escape) { root.requestClose(); event.accepted = true }
        else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          root.tab = root.tab === "Wheels" ? "Results" : "Wheels"
          event.accepted = true
        }
      }

      Item {
        id: keySink
        focus: true
      }

      // Faint "OmaRandom" in the font of Omarchy's logo, repeated in rows
      // that run diagonally (top left to bottom right), in the theme's
      // accent color, behind everything.
      Item {
        id: backdrop
        anchors.fill: parent
        clip: true

        readonly property int artColumns: Logic.LOGO.indexOf("\n")
        // Each copy is about a third of the window wide.
        readonly property int artPixelSize: Math.max(5, Math.round(width * 0.3 / (artColumns * 0.6)))
        readonly property real diagonal: Math.sqrt(width * width + height * height)

        Item {
          id: tiles
          width: backdrop.diagonal * 1.2
          height: width
          anchors.centerIn: parent
          rotation: 45
          opacity: 0.09
          // Fade the whole pattern as one image, not each copy separately.
          layer.enabled: true

          Column {
            id: tileRows
            anchors.centerIn: parent
            spacing: backdrop.artPixelSize * 5

            Repeater {
              model: Math.ceil(tiles.height / (backdrop.artPixelSize * 16)) + 1
              delegate: Row {
                required property int index
                spacing: backdrop.artPixelSize * 8
                // Every other row shifts half a copy, like bricks.
                x: index % 2 ? -(backdropArt.width + spacing) / 2 : 0

                Repeater {
                  model: Math.ceil(tiles.width / (backdrop.width * 0.3)) + 2
                  delegate: Text {
                    textFormat: Text.PlainText
                    text: Logic.LOGO
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: backdrop.artPixelSize
                    // Rows exactly one glyph tall, so the block characters touch.
                    lineHeightMode: Text.FixedHeight
                    lineHeight: backdropMetrics.height
                  }
                }
              }
            }
          }
        }

        // Measures one copy for the spacing math above.
        Text {
          id: backdropArt
          visible: false
          textFormat: Text.PlainText
          text: Logic.LOGO
          font.family: root.fontFamily
          font.pixelSize: backdrop.artPixelSize
          lineHeightMode: Text.FixedHeight
          lineHeight: backdropMetrics.height
        }

        FontMetrics {
          id: backdropMetrics
          font.family: root.fontFamily
          font.pixelSize: backdrop.artPixelSize
        }
      }

      Item {
        id: page
        anchors.fill: parent
        anchors.margins: Style.space(24)

        // ---------- Header ----------
        Item {
          id: header
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: Math.max(title.implicitHeight, closeButton.implicitHeight)

          Row {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(12)

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: "\u{F012B}"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              Text {
                textFormat: Text.PlainText
                text: "OmaRandom"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }
              Text {
                textFormat: Text.PlainText
                text: (root.wheels.length === 1 ? "1 wheel" : root.wheels.length + " wheels")
                  + " · " + (root.results.length === 1 ? "1 result" : root.results.length + " results")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                font.capitalization: Font.AllUppercase
              }
            }
          }

          ButtonGroup {
            anchors.left: title.right
            anchors.leftMargin: Style.space(28)
            anchors.verticalCenter: parent.verticalCenter
            options: ["Wheels", "Results"]
            value: root.tab
            focusable: false
            foreground: root.fg
            fontFamily: root.fontFamily
            onChanged: function(v) { root.tab = v }
          }

          Row {
            anchors.right: closeButton.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)
            visible: root.loadState === "ok"

            Button {
              visible: root.tab === "Wheels"
              text: "Spin all"
              iconText: "\u{F0450}"
              bordered: true
              enabled: root.wheels.length > 0 && root.spinAllPending === 0 && root.loadState === "ok"
              tooltipText: "Spin every wheel at once"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.spinAll()
            }
            Button {
              visible: root.tab === "Wheels"
              text: "Add wheel"
              iconText: "\u{F0415}"
              bordered: true
              enabled: root.wheels.length < Logic.MAX_WHEELS && root.spinAllPending === 0 && root.loadState === "ok"
              tooltipText: root.wheels.length >= Logic.MAX_WHEELS ? "Six wheels is the most that fits" : ""
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.addWheel()
            }
            Button {
              visible: root.tab === "Results" && root.split.top.length > 0
              text: "Clear results"
              bordered: true
              tooltipText: "Clear the cards at the top. They stay in the history."
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.clearTop()
            }
            Button {
              visible: root.tab === "Results" && root.split.history.length > 0
              text: "Clear history"
              bordered: true
              tooltipText: "Delete the history list"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.confirmMode = "history"
            }
          }

          PanelActionButton {
            id: closeButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "\u{F0156}"
            tooltipText: "Close"
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.requestClose()
          }
        }

        PanelSeparator {
          id: headerRule
          anchors.top: header.bottom
          anchors.topMargin: Style.space(16)
          anchors.left: parent.left
          anchors.right: parent.right
          foreground: root.fg
        }

        // ---------- Unreadable file ----------
        Text {
          textFormat: Text.PlainText
          visible: root.loadState === "unreadable"
          anchors.centerIn: content
          width: Math.min(content.width, Style.space(560))
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: "OmaRandom couldn't read your saved wheels (" + root.loadError + "), so it left the file alone.\n\n"
            + root.dataFile + "\n\nFix or move that file, then open OmaRandom again."
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Item {
          id: content
          anchors.top: headerRule.bottom
          anchors.topMargin: Style.space(20)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          visible: root.loadState === "ok"

          // ---------- Wheels tab ----------
          Item {
            id: wheelsView
            anchors.fill: parent
            visible: root.tab === "Wheels"

            readonly property var rowCounts: Logic.rows(root.wheels.length)
            readonly property real gap: Style.space(28)
            readonly property real labelSpace: Style.space(64)
            readonly property int rowsUsed: rowCounts.length
            readonly property real cardSize: Math.max(120, Math.min(
              (width - 2 * gap) / 3,
              (height - (rowsUsed - 1) * gap) / rowsUsed - labelSpace))
            readonly property real blockHeight: rowsUsed * (cardSize + labelSpace) + (rowsUsed - 1) * gap

            Column {
              visible: root.wheels.length === 0
              anchors.centerIn: parent
              spacing: Style.space(14)
              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Add a wheel to get started."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }
              Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Add wheel"
                iconText: "\u{F0415}"
                bordered: true
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: root.addWheel()
              }
            }

            Repeater {
              id: cardRepeater
              model: root.wheels
              delegate: Item {
                id: card
                required property var modelData
                required property int index
                readonly property int rowIndex: index < wheelsView.rowCounts[0] ? 0 : 1
                readonly property int colIndex: rowIndex === 0 ? index : index - wheelsView.rowCounts[0]
                readonly property int inRow: wheelsView.rowCounts[rowIndex] || 1
                readonly property real rowWidth: inRow * wheelsView.cardSize + (inRow - 1) * wheelsView.gap

                width: wheelsView.cardSize
                height: wheelsView.cardSize + wheelsView.labelSpace
                x: (wheelsView.width - rowWidth) / 2 + colIndex * (wheelsView.cardSize + wheelsView.gap)
                y: (wheelsView.height - wheelsView.blockHeight) / 2 + rowIndex * (height + wheelsView.gap)
                Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
                Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

                opacity: root.focusId === modelData.id ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 200 } }
                scale: 0.6
                Component.onCompleted: appear.start()
                NumberAnimation on scale { id: appear; running: false; to: 1; duration: 300; easing.type: Easing.OutBack }

                function spinRandom() { return cardWheel.spin(Logic.pickIndex(modelData.options.length)) }
                function finishNow() { cardWheel.finishNow() }

                Wheel {
                  id: cardWheel
                  width: parent.width
                  height: width
                  wheel: card.modelData
                  theme: root.theme
                  angle: root.angles[card.modelData.id] || 0
                  active: root.opened && root.focusId === ""
                  swayPhase: card.index * 1.7
                  interactive: root.spinAllPending === 0
                  fontFamily: root.fontFamily
                  rimColor: root.fg
                  onClicked: root.openFocus(card.modelData.id, cardWheel)
                  onLanded: function(i) {
                    root.setAngle(card.modelData.id, discAngle)
                    root.cardLanded(card.modelData, i)
                  }
                }

                // The wheel's name doubles as its edit button; the trash
                // beside it deletes the wheel (after a confirm).
                Row {
                  anchors.top: cardWheel.bottom
                  anchors.topMargin: Style.space(12)
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.space(6)

                  Button {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, card.width - Style.space(40))
                    text: card.modelData.name
                    iconText: "\u{F03EB}"
                    bordered: true
                    enabled: root.spinAllPending === 0
                    tooltipText: "Edit wheel"
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    fontSize: Style.font.title
                    horizontalPadding: Style.space(16)
                    verticalPadding: Style.space(7)
                    onClicked: root.editWheel(card.modelData.id)
                  }
                  PanelActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "\u{F01B4}"
                    tooltipText: "Delete wheel"
                    enabled: root.spinAllPending === 0
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    onClicked: {
                      root.deleteId = card.modelData.id
                      root.confirmMode = "delete"
                    }
                  }
                }
              }
            }

            // Pops up in the middle when every wheel has landed.
            Item {
              id: roundDone
              anchors.fill: parent
              visible: root.showViewResults || roundPop.running
              property real pop: root.showViewResults ? 1 : 0
              Behavior on pop { NumberAnimation { id: roundPop; duration: 300; easing.type: Easing.OutBack } }

              Rectangle {
                anchors.fill: parent
                color: Color.background
                opacity: 0.55 * Math.min(1, roundDone.pop)
                MouseArea {
                  anchors.fill: parent
                  // Swallow every button so right-clicks never reach fields underneath.
                  acceptedButtons: Qt.AllButtons
                  onClicked: function(mouse) { if (mouse.button === Qt.LeftButton) root.showViewResults = false }
                }
              }

              BorderSurface {
                anchors.centerIn: parent
                width: roundColumn.implicitWidth + Style.space(64)
                height: roundColumn.implicitHeight + Style.space(48)
                scale: 0.6 + 0.4 * roundDone.pop
                opacity: Math.min(1, roundDone.pop)
                color: Color.background
                borderSpec: Border.flat(Color.accent, Math.max(2, Style.normalBorderWidth * 2))
                radius: Style.cornerRadius

                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

                Column {
                  id: roundColumn
                  anchors.centerIn: parent
                  spacing: Style.space(14)

                  Text {
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Every wheel has landed"
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                    font.bold: true
                  }
                  Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.space(10)
                    Button {
                      id: viewResultsButton
                      text: "View results"
                      iconText: "\u{F0E1E}"
                      bordered: true
                      selected: true
                      fontSize: Style.font.title
                      horizontalPadding: Style.space(18)
                      verticalPadding: Style.space(8)
                      foreground: root.fg
                      fontFamily: root.fontFamily
                      onClicked: root.viewResults()

                      SequentialAnimation on scale {
                        running: root.showViewResults
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.06; duration: 600; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
                      }
                    }
                    Button {
                      text: "Later"
                      bordered: true
                      fontSize: Style.font.title
                      horizontalPadding: Style.space(18)
                      verticalPadding: Style.space(8)
                      foreground: root.fg
                      fontFamily: root.fontFamily
                      onClicked: root.showViewResults = false
                    }
                  }
                }
              }
            }
          }

          // ---------- Results tab ----------
          Item {
            id: resultsView
            anchors.fill: parent
            visible: root.tab === "Results"

            Text {
              textFormat: Text.PlainText
              visible: root.results.length === 0
              anchors.centerIn: parent
              text: "Spin a wheel to generate results."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }

            Flickable {
              id: resultsFlick
              visible: root.results.length > 0
              anchors.fill: parent
              clip: true
              contentWidth: width
              contentHeight: resultsColumn.implicitHeight
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              Column {
                id: resultsColumn
                width: resultsFlick.width - Style.space(14)
                spacing: Style.space(14)

                PanelSectionHeader {
                  text: root.split.top.length === 1 ? "RESULT" : root.split.top.length > 1 ? "ROUND" : "RESULTS"
                  foreground: root.fg
                  fontFamily: root.fontFamily
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.split.top.length === 0
                  width: parent.width
                  topPadding: Style.space(30)
                  bottomPadding: Style.space(30)
                  horizontalAlignment: Text.AlignHCenter
                  text: "Spin a wheel, or click a result in the history to view it here."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }

                Flow {
                  id: latestFlow
                  readonly property int perRow: Math.min(3, Math.max(1, root.split.top.length))
                  readonly property real cardWidth: Math.min(Style.space(420),
                    (parent.width - (perRow - 1) * spacing) / perRow)
                  width: perRow * cardWidth + (perRow - 1) * spacing
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.space(16)
                  // Cards in a round share the tallest card's height.
                  readonly property real tallest: {
                    var m = 0
                    for (var i = 0; i < children.length; i++)
                      if (children[i].cardHeight !== undefined) m = Math.max(m, children[i].cardHeight)
                    return m
                  }

                  Repeater {
                    model: root.split.top
                    delegate: ResultCard {
                      required property var modelData
                      required property int index
                      result: modelData
                      order: index
                      width: latestFlow.cardWidth
                      height: Math.max(cardHeight, latestFlow.tallest)
                    }
                  }
                }

                PanelSectionHeader {
                  visible: root.split.history.length > 0
                  topPadding: Style.space(10)
                  text: "HISTORY"
                  foreground: root.fg
                  fontFamily: root.fontFamily
                }

                Repeater {
                  model: root.split.history
                  delegate: Item {
                    id: historyRow
                    required property var modelData
                    width: resultsColumn.width
                    height: Style.space(40)

                    // Click a row to bring its round back to the top.
                    Rectangle {
                      anchors.fill: parent
                      radius: Style.cornerRadius
                      color: Util.alpha(root.fg, historyMouse.containsMouse ? 0.08 : 0)
                      Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    MouseArea {
                      id: historyMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.showRound(Logic.roundOf(historyRow.modelData))
                        resultsFlick.contentY = 0
                      }
                    }

                    Rectangle {
                      id: historyDot
                      width: Style.space(12)
                      height: width
                      radius: width / 2
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      color: historyRow.modelData.color || Color.accent
                    }
                    Image {
                      id: historyThumb
                      visible: !!historyRow.modelData.image && status === Image.Ready
                      anchors.left: historyDot.right
                      anchors.leftMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      width: visible ? Style.space(32) : 0
                      height: Style.space(32)
                      source: Logic.isLocalImage(historyRow.modelData.image) ? historyRow.modelData.image : ""
                      sourceSize.width: 96
                      sourceSize.height: 96
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                    }
                    Text {
                      textFormat: Text.PlainText
                      anchors.left: historyThumb.right
                      anchors.leftMargin: Style.space(10)
                      anchors.right: historyTime.left
                      anchors.rightMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      elide: Text.ElideRight
                      text: historyRow.modelData.label + "  ·  " + historyRow.modelData.wheel
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    Text {
                      id: historyTime
                      textFormat: Text.PlainText
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      text: Logic.timeText(historyRow.modelData.time)
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }
            }
          }
        }
      }

      // ---------- Spin view ----------
      Item {
        id: focusLayer
        anchors.fill: parent
        visible: root.focusId !== "" || growAnim.running
        property real grow: 0
        property rect fromRect: Qt.rect(0, 0, 0, 0)
        property bool hasFrom: false

        function showFrom(r) {
          hasFrom = !!r
          if (r) fromRect = r
          growAnim.stop()
          growAnim.from = 0
          growAnim.to = 1
          growAnim.start()
        }

        function hide(instant) {
          growAnim.stop()
          if (instant) {
            grow = 0
            root.focusId = ""
            root.landing = null
            return
          }
          growAnim.from = grow
          growAnim.to = 0
          growAnim.start()
        }

        NumberAnimation {
          id: growAnim
          target: focusLayer
          property: "grow"
          duration: 300
          easing.type: Easing.InOutQuad
          onFinished: if (focusLayer.grow === 0) { root.focusId = ""; root.landing = null }
        }

        Rectangle {
          anchors.fill: parent
          color: Color.background
          opacity: 0.94 * focusLayer.grow
          MouseArea {
            anchors.fill: parent
            // Swallow every button so right-clicks never reach fields underneath.
            acceptedButtons: Qt.AllButtons
            onClicked: function(mouse) { if (mouse.button === Qt.LeftButton) root.closeFocus() }
          }
        }

        Text {
          id: focusTitle
          textFormat: Text.PlainText
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: Style.space(28)
          opacity: focusLayer.grow
          text: root.focusWheel ? root.focusWheel.name : ""
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.displayLarge
          font.bold: true
        }

        Wheel {
          id: bigWheel
          readonly property real full: Math.min(parent.width - Style.space(80),
            parent.height - focusTitle.height - focusButtons.height - Style.space(120))
          width: full
          height: full
          x: (parent.width - full) / 2
          y: focusTitle.y + focusTitle.height + Style.space(20)
          wheel: root.focusWheel
          theme: root.theme
          angle: root.focusWheel ? (root.angles[root.focusWheel.id] || 0) : 0
          active: root.opened && root.focusId !== ""
          interactive: root.focusId !== "" && !growAnim.running
          fontFamily: root.fontFamily
          rimColor: root.fg
          onClicked: root.spinFocus()
          onSpinningChanged: root.focusSpinning = spinning
          onLanded: function(i) {
            if (!root.focusWheel) return
            root.setAngle(root.focusWheel.id, discAngle)
            root.landing = { wheelId: root.focusWheel.id, index: i, saved: false }
          }

          // Grow out of the card the wheel was clicked on.
          transform: [
            Scale {
              readonly property real s: focusLayer.hasFrom && bigWheel.full > 0
                ? focusLayer.fromRect.width / bigWheel.full : 0.6
              origin.x: focusLayer.hasFrom ? 0 : bigWheel.full / 2
              origin.y: focusLayer.hasFrom ? 0 : bigWheel.full / 2
              xScale: s + (1 - s) * focusLayer.grow
              yScale: xScale
            },
            Translate {
              x: focusLayer.hasFrom ? (focusLayer.fromRect.x - bigWheel.x) * (1 - focusLayer.grow) : 0
              y: focusLayer.hasFrom ? (focusLayer.fromRect.y - bigWheel.y) * (1 - focusLayer.grow) : 0
            }
          ]
          opacity: focusLayer.hasFrom ? 1 : focusLayer.grow
        }

        // Winner card, shown over the wheel when it lands.
        BorderSurface {
          id: winnerCard
          readonly property var option: root.landing && root.focusWheel
            ? root.focusWheel.options[root.landing.index] : null
          readonly property color sliceFill: root.landing && root.focusWheel
            ? Logic.sliceColor(root.focusWheel, root.landing.index, root.theme) : Color.accent
          visible: !!option && focusLayer.grow > 0.99
          anchors.centerIn: bigWheel
          width: option && option.image ? bigWheel.width * 0.62
            : Math.min(bigWheel.width * 0.62, Math.max(Style.space(260), winnerColumn.implicitWidth + Style.space(48)))
          height: winnerColumn.implicitHeight + Style.space(40)
          color: Color.background
          borderSpec: Border.flat(sliceFill, Math.max(3, Style.normalBorderWidth * 2))
          radius: Style.cornerRadius
          scale: visible ? 1 : 0.5
          Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

          Column {
            id: winnerColumn
            anchors.centerIn: parent
            width: parent.width - Style.space(40)
            spacing: Style.space(10)

            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              text: "WINNER"
              color: winnerCard.sliceFill
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 2
            }
            Image {
              id: winnerImage
              visible: !!winnerCard.option && !!winnerCard.option.image && status === Image.Ready
              anchors.horizontalCenter: parent.horizontalCenter
              width: parent.width
              height: visible ? Math.min(width, bigWheel.height * 0.42) : 0
              source: winnerCard.option && Logic.isLocalImage(winnerCard.option.image) ? winnerCard.option.image : ""
              sourceSize.width: 640
              sourceSize.height: 640
              fillMode: Image.PreserveAspectFit
              asynchronous: true
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: winnerCard.option ? (winnerCard.option.label || ("Option " + (root.landing.index + 1))) : ""
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
            }
          }

          MouseArea {
            anchors.fill: parent
            // Swallow every button so right-clicks never reach fields underneath.
            acceptedButtons: Qt.AllButtons
            onClicked: function(mouse) { if (mouse.button === Qt.LeftButton) root.spinFocus() }
          }
        }

        Row {
          id: focusButtons
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(32)
          spacing: Style.space(12)
          opacity: focusLayer.grow

          Button {
            text: root.landing ? "Spin again" : "Spin"
            iconText: "\u{F0450}"
            bordered: true
            enabled: !root.focusSpinning
            tooltipText: "Space"
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.spinFocus()
          }
          Button {
            text: root.landing && root.landing.saved ? "Saved" : "Save"
            iconText: root.landing && root.landing.saved ? "\u{F012C}" : "\u{F0193}"
            bordered: true
            enabled: !!root.landing && !root.landing.saved && !root.focusSpinning
            tooltipText: "S"
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.saveLanding()
          }
          Button {
            text: "Minimize"
            iconText: "\u{F05B0}"
            bordered: true
            tooltipText: "Esc"
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.closeFocus()
          }
        }
      }

      WheelEditor {
        id: editor
        anchors.fill: parent
        theme: root.theme
        fg: root.fg
        dim: root.dim
        fontFamily: root.fontFamily
        onEdited: function(w) { root.replaceWheel(w) }
        onDoneRequested: {
          editor.close()
          root.takeKeys()
        }
        onDeleteRequested: {
          root.deleteId = editor.draft ? editor.draft.id : ""
          root.confirmMode = "delete"
        }
      }

      ConfirmDialog {
        id: confirm
        anchors.fill: parent
        opened: root.confirmMode !== ""
        message: root.confirmMode === "history"
          ? "Delete all " + root.split.history.length + " results in the history?"
          : "Delete the wheel “" + (root.wheelById(root.deleteId) ? root.wheelById(root.deleteId).name : "") + "”?"
        confirmText: "Delete"
        fontFamily: root.fontFamily
        onCanceled: root.confirmMode = ""
        onConfirmed: {
          if (root.confirmMode === "history") {
            root.clearHistory()
          } else if (root.deleteId) {
            editor.close()
            root.deleteWheel(root.deleteId)
          }
          root.confirmMode = ""
          root.deleteId = ""
          root.takeKeys()
        }
      }
    }
  }

  // A result: face down first when it's part of a reveal, then flipped.
  component ResultCard: Item {
    id: rc
    property var result: null
    property int order: 0
    property bool faceUp: true
    readonly property bool hasImage: !!result && !!result.image && rcImage.status === Image.Ready
    readonly property real cardHeight: rcFront.implicitHeight
    // More than three cards make two rows, so each card gets shorter.
    readonly property bool compact: root.split.top.length > 3
    height: cardHeight

    function hideNow() { flip.stop(); faceUp = false; flipAngle = 0; popScale = 0.6; opacity = 0 }
    property real flipAngle: 0
    property real popScale: 1

    Connections {
      target: root
      function onRevealRunChanged() {
        if (!rc.result || rc.result.batch !== root.revealBatch) return
        rc.hideNow()
        revealTimer.interval = 250 + rc.order * 650
        revealTimer.restart()
      }
    }

    Timer {
      id: revealTimer
      onTriggered: flip.start()
    }

    SequentialAnimation {
      id: flip
      ParallelAnimation {
        NumberAnimation { target: rc; property: "opacity"; to: 1; duration: 200 }
        NumberAnimation { target: rc; property: "popScale"; to: 1; duration: 300; easing.type: Easing.OutBack }
      }
      PauseAnimation { duration: 250 }
      NumberAnimation { target: rc; property: "flipAngle"; to: 90; duration: 150; easing.type: Easing.InQuad }
      ScriptAction { script: rc.faceUp = true }
      NumberAnimation { target: rc; property: "flipAngle"; to: 0; duration: 150; easing.type: Easing.OutQuad }
    }

    transform: [
      Rotation {
        origin.x: rc.width / 2
        origin.y: rc.height / 2
        axis { x: 0; y: 1; z: 0 }
        angle: rc.flipAngle
      },
      Scale {
        origin.x: rc.width / 2
        origin.y: rc.height / 2
        xScale: rc.popScale
        yScale: rc.popScale
      }
    ]

    BorderSurface {
      id: rcFront
      anchors.fill: parent
      implicitHeight: Math.max(Style.space(rc.compact ? 120 : 170), rcColumn.implicitHeight + Style.space(rc.compact ? 32 : 44))
      color: Color.background
      borderSpec: Border.flat(rc.result && rc.result.color ? rc.result.color : Color.accent,
        Math.max(2, Style.normalBorderWidth * 2))
      radius: Style.cornerRadius

      Column {
        id: rcColumn
        visible: rc.faceUp
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.space(22)
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          text: rc.result ? rc.result.wheel : ""
          color: rc.result && rc.result.color ? rc.result.color : Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
          font.capitalization: Font.AllUppercase
        }
        Image {
          id: rcImage
          visible: rc.hasImage
          width: parent.width
          height: visible ? Math.min(width * 0.75, Style.space(rc.compact ? 120 : 260)) : 0
          source: rc.result && Logic.isLocalImage(rc.result.image) ? rc.result.image : ""
          sourceSize.width: 840
          sourceSize.height: 840
          fillMode: Image.PreserveAspectFit
          asynchronous: true
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: rc.result ? rc.result.label : ""
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.displayLarge
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: rc.result ? Logic.timeText(rc.result.time) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      // Back face while it waits to be revealed.
      Rectangle {
        visible: !rc.faceUp
        anchors.fill: parent
        anchors.margins: Style.space(6)
        radius: Style.cornerRadius
        color: Util.alpha(rc.result && rc.result.color ? rc.result.color : Color.accent, 0.85)
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: "?"
          color: Logic.textOn(rc.result && rc.result.color ? rc.result.color : "#000000")
          font.family: root.fontFamily
          font.pixelSize: Style.font.displayLarge * 2
          font.bold: true
        }
      }
    }
  }
}

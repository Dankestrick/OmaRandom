import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Bar icon. A click opens or closes the big OmaRandom window (Panel.qml).
BarWidget {
  id: root
  moduleName: "io.github.dankestrick.omarandom"

  readonly property var host: bar ? bar.shell : null
  readonly property bool opened: !!(host && typeof host.isPluginOpen === "function"
    && host.isPluginOpen(moduleName))

  function open() {
    if (host && typeof host.summon === "function" && !opened) host.summon(moduleName, "{}")
  }
  function close() {
    if (host && typeof host.hide === "function" && opened) host.hide(moduleName)
  }
  function toggle() {
    if (opened) close()
    else open()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u{F012B}"
    tooltipText: "OmaRandom"
    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
    }
  }
}

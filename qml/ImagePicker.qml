import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import qs.Commons
import qs.Ui
import "Logic.js" as Logic

// Picture browser drawn by OmaRandom itself. Qt's FileDialog loads the GTK
// file chooser into the shell process, and a GTK failure there takes the
// whole shell down, so pictures are picked here instead.
Item {
  id: root

  property bool opened: false
  property color fg: Color.foreground
  property color dim: Qt.darker(Color.foreground, 1.4)
  property string fontFamily: Style.font.family

  readonly property string home: Quickshell.env("HOME") || "/home"
  // Omarchy's theme folders; each has a backgrounds folder of wallpapers.
  readonly property string wallpapers: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/themes"
  // Remembered for the session, so the next pick starts where the last ended.
  property string folderPath: home + "/Pictures"
  readonly property bool inWallpapers: inside(folderPath, wallpapers)
  readonly property bool canGoUp: folderPath !== home && folderPath !== wallpapers

  // Browsing stays inside your home folder and the Omarchy wallpapers.
  function inside(path, top) {
    return path === top || path.indexOf(top + "/") === 0
  }

  function allowed(path) {
    return path.indexOf("/..") < 0 && (inside(path, home) || inside(path, wallpapers))
  }

  // Where the browser is, in words: ~/Pictures, or Omarchy wallpapers / nord.
  function placeText(path) {
    if (inside(path, wallpapers)) {
      var rest = path.substring(wallpapers.length).replace(/\/backgrounds$/, "")
      return "Omarchy wallpapers" + rest.replace(/\//g, " / ")
    }
    return "~" + path.substring(home.length)
  }

  signal picked(string url)
  signal canceled()

  function open() {
    opened = true
    // Take the keys from whatever text field had them.
    keyCatch.forceActiveFocus()
  }

  function close() {
    opened = false
  }

  function go(path) {
    path = path.length > 1 && path.charAt(path.length - 1) === "/" ? path.substring(0, path.length - 1) : path
    if (!allowed(path)) return
    folderPath = path
    grid.positionViewAtBeginning()
  }

  function goUp() {
    if (!canGoUp) return
    var up = folderPath.substring(0, folderPath.lastIndexOf("/"))
    // A theme's wallpapers sit in <theme>/backgrounds; skip the theme folder.
    if (up !== wallpapers && up.substring(0, up.lastIndexOf("/")) === wallpapers) up = wallpapers
    go(up)
  }

  function openFolder(path) {
    // Opening a theme goes straight to its wallpapers.
    if (path.substring(0, path.lastIndexOf("/")) === wallpapers) go(path + "/backgrounds")
    else go(path)
  }

  function handleKey(event) {
    if (!opened) return false
    if (event.key === Qt.Key_Escape) { root.canceled(); return true }
    if (event.key === Qt.Key_Backspace) { goUp(); return true }
    return false
  }

  visible: opened

  Item {
    id: keyCatch
    Keys.onPressed: function(event) {
      if (root.handleKey(event)) event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Color.background, 0.75)
    MouseArea {
      anchors.fill: parent
      // Swallow every button so right-clicks never reach fields underneath.
      acceptedButtons: Qt.AllButtons
      onClicked: function(mouse) { if (mouse.button === Qt.LeftButton) root.canceled() }
    }
  }

  BorderSurface {
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(64), Style.space(900))
    height: Math.min(parent.height - Style.space(64), Style.space(620))
    color: Color.background
    borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
    radius: Style.cornerRadius

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    Item {
      anchors.fill: parent
      anchors.margins: Style.space(20)

      Item {
        id: header
        width: parent.width
        height: cancelButton.implicitHeight

        Row {
          id: nav
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          PanelActionButton {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "\u{F005D}"
            tooltipText: "Up a folder · Backspace"
            enabled: root.canGoUp
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.goUp()
          }
          Button {
            anchors.verticalCenter: parent.verticalCenter
            text: "Pictures"
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.go(root.home + "/Pictures")
          }
          Button {
            anchors.verticalCenter: parent.verticalCenter
            text: "Home"
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.go(root.home)
          }
          Button {
            anchors.verticalCenter: parent.verticalCenter
            text: "Wallpapers"
            bordered: true
            selected: root.inWallpapers
            tooltipText: "Wallpapers from the Omarchy themes"
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.go(root.wallpapers)
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.left: nav.right
          anchors.leftMargin: Style.space(14)
          anchors.right: cancelButton.left
          anchors.rightMargin: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideMiddle
          text: root.placeText(root.folderPath)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Button {
          id: cancelButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "Cancel"
          bordered: true
          foreground: root.fg
          fontFamily: root.fontFamily
          onClicked: root.canceled()
        }
      }

      FolderListModel {
        id: folderModel
        folder: "file://" + root.folderPath
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.bmp", "*.svg"]
        caseSensitive: false
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Name
      }

      GridView {
        id: grid
        anchors.top: header.bottom
        anchors.topMargin: Style.space(16)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        cellWidth: Math.floor(width / Math.max(1, Math.floor(width / Style.space(150))))
        cellHeight: Style.space(150)
        model: root.opened ? folderModel : null
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Item {
          id: tile
          required property string fileName
          required property url fileUrl
          required property string filePath
          required property bool fileIsDir
          width: grid.cellWidth
          height: grid.cellHeight

          Rectangle {
            anchors.fill: parent
            anchors.margins: Style.space(4)
            radius: Style.cornerRadius
            color: Util.alpha(root.fg, tileMouse.containsMouse ? 0.08 : 0)
            border.width: tileMouse.containsMouse ? 1 : 0
            border.color: Util.alpha(root.fg, 0.3)
          }

          Item {
            id: preview
            anchors.top: parent.top
            anchors.topMargin: Style.space(10)
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - Style.space(24)
            height: parent.height - name.height - Style.space(26)

            Text {
              textFormat: Text.PlainText
              visible: tile.fileIsDir
              anchors.centerIn: parent
              text: "\u{F024B}"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge * 1.6
            }
            Image {
              id: thumb
              visible: !tile.fileIsDir
              anchors.fill: parent
              source: tile.fileIsDir ? "" : tile.fileUrl
              sourceSize.width: 192
              sourceSize.height: 192
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              cache: false
            }
            Text {
              textFormat: Text.PlainText
              visible: !tile.fileIsDir && thumb.status === Image.Error
              anchors.centerIn: parent
              text: "?"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          Text {
            id: name
            textFormat: Text.PlainText
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(10)
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - Style.space(20)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            text: tile.fileName
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (tile.fileIsDir) root.openFolder(tile.filePath)
              else {
                var url = String(tile.fileUrl)
                if (Logic.isLocalImage(url)) root.picked(url)
              }
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.opened && folderModel.status === FolderListModel.Ready && folderModel.count === 0
        anchors.centerIn: grid
        text: "No pictures or folders here."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }
    }
  }
}

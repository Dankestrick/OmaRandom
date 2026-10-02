import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Logic.js" as Logic

// Edit one wheel: its name, colors, options and pictures. Every change goes
// out through edited(wheel) right away, so there is nothing to save.
Item {
  id: root

  property var draft: null
  property var theme: []
  property color fg: Color.foreground
  property color dim: Qt.darker(Color.foreground, 1.4)
  property string fontFamily: Style.font.family
  property bool opened: false

  signal edited(var wheel)
  signal doneRequested()
  signal deleteRequested()

  // Option row whose color picker is open, or -1.
  property int swatchFor: -1
  property real swatchY: 0
  property int imageFor: -1
  readonly property bool popupOpen: swatchFor >= 0 || picker.opened

  function openFor(wheel) {
    draft = JSON.parse(JSON.stringify(wheel))
    swatchFor = -1
    opened = true
    Qt.callLater(function() { nameField.forceActiveFocus() })
  }

  function choosePicture(index) {
    swatchFor = -1
    imageFor = index
    picker.open()
  }

  function close() {
    swatchFor = -1
    picker.close()
    opened = false
  }

  function change(fn) {
    var d = JSON.parse(JSON.stringify(draft))
    fn(d)
    draft = d
    root.edited(d)
  }

  function handleKey(event) {
    if (!opened) return false
    if (picker.handleKey(event)) return true
    if (event.key === Qt.Key_Escape) {
      if (swatchFor >= 0) swatchFor = -1
      else root.doneRequested()
      return true
    }
    return false
  }

  visible: opened

  // Scrim
  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Color.background, 0.75)
    MouseArea {
      anchors.fill: parent
      // Swallow every button so right-clicks never reach fields underneath.
      acceptedButtons: Qt.AllButtons
      onClicked: function(mouse) { if (mouse.button === Qt.LeftButton) root.doneRequested() }
    }
  }

  BorderSurface {
    id: card
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(48), Style.space(980))
    height: Math.min(parent.height - Style.space(48), Style.space(660))
    color: Color.background
    borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
    radius: Style.cornerRadius
    padding: Style.space(20)

    MouseArea {
      anchors.fill: parent
      // Swallow every button so right-clicks never reach fields underneath.
      acceptedButtons: Qt.AllButtons
      onClicked: function(mouse) { if (mouse.button === Qt.LeftButton) root.swatchFor = -1 }
    }

    Item {
      id: body
      anchors.fill: parent
      anchors.margins: Style.space(20)

      // ---------- Header ----------
      Item {
        id: header
        width: parent.width
        height: doneButton.implicitHeight

        PanelSectionHeader {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "EDIT WHEEL"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Button {
            text: "Delete wheel"
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.deleteRequested()
          }
          Button {
            id: doneButton
            text: "Done"
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.doneRequested()
          }
        }
      }

      // ---------- Left: fields and options ----------
      Item {
        id: form
        anchors.top: header.bottom
        anchors.topMargin: Style.space(18)
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: parent.width - preview.width - Style.space(28)

        Column {
          id: fields
          width: parent.width
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            text: "Name"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          TextField {
            id: nameField
            width: parent.width
            maximumLength: Logic.MAX_NAME
            text: root.draft ? root.draft.name : ""
            placeholderText: "Wheel name"
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            foreground: root.fg
            onTextEdited: {
              var t = text
              root.change(function(d) { d.name = t })
            }
          }

          Row {
            spacing: Style.space(12)
            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: "Colors"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            ButtonGroup {
              anchors.verticalCenter: parent.verticalCenter
              options: [{ value: "theme", label: "Theme" }, { value: "classic", label: "Classic" }]
              value: root.draft ? root.draft.palette : "theme"
              focusable: false
              foreground: root.fg
              fontFamily: root.fontFamily
              onChanged: function(v) { root.change(function(d) { d.palette = v }) }
            }
          }

          Row {
            width: parent.width
            Text {
              textFormat: Text.PlainText
              width: parent.width - addOption.width
              anchors.verticalCenter: parent.verticalCenter
              text: "Options · " + (root.draft ? root.draft.options.length : 0)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Button {
              id: addOption
              text: "Add option"
              iconText: "\u{F0415}"
              bordered: true
              enabled: !!root.draft && root.draft.options.length < Logic.MAX_OPTIONS
              tooltipText: enabled ? "" : Logic.MAX_OPTIONS + " options is the most a wheel can hold"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: {
                root.change(function(d) { d.options.push(Logic.makeOption("Option " + (d.options.length + 1))) })
                Qt.callLater(function() { optionList.positionViewAtEnd() })
              }
            }
          }
        }

        ListView {
          id: optionList
          anchors.top: fields.bottom
          anchors.topMargin: Style.space(10)
          anchors.bottom: parent.bottom
          width: parent.width
          clip: true
          spacing: Style.space(6)
          // A count, not the array, so rows (and their text fields) stay put
          // while typing.
          model: root.draft ? root.draft.options.length : 0
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          delegate: Item {
            id: row
            required property int index
            readonly property var option: root.draft && root.draft.options[index] ? root.draft.options[index] : ({ label: "", color: "", image: "" })
            readonly property color fill: root.draft ? Logic.sliceColor(root.draft, index, root.theme) : "transparent"
            width: optionList.width - Style.space(14)
            height: Style.space(36)

            Rectangle {
              id: swatch
              width: Style.space(26)
              height: width
              radius: width / 2
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              color: row.fill
              border.width: row.option.color ? 2 : 1
              border.color: Util.alpha(root.fg, row.option.color ? 0.9 : 0.4)

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var p = swatch.mapToItem(body, 0, swatch.height + Style.space(6))
                  root.swatchY = p.y
                  root.swatchFor = root.swatchFor === row.index ? -1 : row.index
                }
              }
            }

            TextField {
              id: labelField
              anchors.left: swatch.right
              anchors.leftMargin: Style.space(10)
              anchors.right: pictureBox.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              maximumLength: Logic.MAX_LABEL
              text: row.option.label
              placeholderText: "Option " + (row.index + 1)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              foreground: root.fg
              onTextEdited: {
                var t = text
                var i = row.index
                root.change(function(d) { d.options[i].label = t })
              }
            }

            // Picture: a thumbnail when set, otherwise an add button.
            Item {
              id: pictureBox
              anchors.right: removeOption.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(58)
              height: Style.space(30)

              PanelActionButton {
                id: addPicture
                visible: !row.option.image
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                iconText: "\u{F02E9}"
                tooltipText: "Add a picture"
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: root.choosePicture(row.index)
              }

              Image {
                id: thumb
                visible: !!row.option.image
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(30)
                height: Style.space(30)
                source: Logic.isLocalImage(row.option.image) ? row.option.image : ""
                sourceSize.width: 96
                sourceSize.height: 96
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.choosePicture(row.index)
                }
              }
              Text {
                textFormat: Text.PlainText
                visible: !!row.option.image && thumb.status === Image.Error
                anchors.centerIn: thumb
                text: "?"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              PanelActionButton {
                visible: !!row.option.image
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "\u{F0156}"
                tooltipText: "Remove picture"
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: {
                  var i = row.index
                  root.change(function(d) { d.options[i].image = "" })
                }
              }
            }

            PanelActionButton {
              id: removeOption
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "\u{F01B4}"
              tooltipText: enabled ? "Remove option" : "A wheel needs at least two options"
              enabled: !!root.draft && root.draft.options.length > Logic.MIN_OPTIONS
              opacity: enabled ? 1 : 0.4
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: {
                var i = row.index
                if (root.swatchFor === i) root.swatchFor = -1
                root.change(function(d) { d.options.splice(i, 1) })
              }
            }
          }
        }
      }

      // ---------- Right: live preview ----------
      Item {
        id: preview
        anchors.top: header.bottom
        anchors.topMargin: Style.space(18)
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Math.min(parent.width * 0.45, height)

        Wheel {
          anchors.centerIn: parent
          width: Math.min(parent.width, parent.height)
          height: width
          wheel: root.draft
          theme: root.theme
          active: root.opened
          interactive: false
          fontFamily: root.fontFamily
          rimColor: root.fg
        }
      }

      // ---------- Color picker ----------
      Rectangle {
        id: swatchPopup
        visible: root.swatchFor >= 0
        x: Style.space(0)
        y: Math.min(root.swatchY, body.height - height)
        width: swatchGrid.width + Style.space(24)
        height: swatchColumn.implicitHeight + Style.space(24)
        radius: Style.cornerRadius
        color: Color.popups.background
        border.width: Math.max(1, Style.normalBorderWidth)
        border.color: Color.popups.border
        z: 10

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Column {
          id: swatchColumn
          anchors.centerIn: parent
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            text: "THEME"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Grid {
            id: swatchGrid
            columns: 10
            spacing: Style.space(6)
            Repeater {
              model: root.theme
              delegate: SwatchDot {
                required property string modelData
                swatchColor: modelData
              }
            }
          }
          Text {
            textFormat: Text.PlainText
            text: "CLASSIC"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Grid {
            columns: 10
            spacing: Style.space(6)
            Repeater {
              model: Logic.CLASSIC
              delegate: SwatchDot {
                required property string modelData
                swatchColor: modelData
              }
            }
          }
          Button {
            text: "Use wheel colors"
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: {
              var i = root.swatchFor
              root.swatchFor = -1
              if (i >= 0) root.change(function(d) { d.options[i].color = "" })
            }
          }
        }
      }
    }
  }

  ImagePicker {
    id: picker
    anchors.fill: parent
    fg: root.fg
    dim: root.dim
    fontFamily: root.fontFamily
    onPicked: function(url) {
      var i = root.imageFor
      root.imageFor = -1
      picker.close()
      if (i >= 0 && Logic.isLocalImage(url)) root.change(function(d) { if (d.options[i]) d.options[i].image = url })
    }
    onCanceled: {
      root.imageFor = -1
      picker.close()
    }
  }

  component SwatchDot: Rectangle {
    id: dot
    property string swatchColor: "#000000"
    width: Style.space(24)
    height: width
    radius: width / 2
    color: swatchColor
    border.width: dotMouse.containsMouse ? 2 : 1
    border.color: dotMouse.containsMouse ? root.fg : Util.alpha(root.fg, 0.3)

    MouseArea {
      id: dotMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        var i = root.swatchFor
        var c = dot.swatchColor
        root.swatchFor = -1
        if (i >= 0) root.change(function(d) { d.options[i].color = c })
      }
    }
  }
}

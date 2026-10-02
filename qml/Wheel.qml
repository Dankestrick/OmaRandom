import QtQuick
import qs.Commons
import "Logic.js" as Logic

// One wheel: colored slices, labels, optional pictures, a pointer on the
// right and a gentle idle sway. spin(winner) turns it so `winner` lands under
// the pointer, then emits landed(winner).
Item {
  id: root

  property var wheel: null
  property var theme: []
  // Where the wheel rests when it isn't spinning, in degrees.
  property real angle: 0
  // Sway and other motion only run while the window is showing.
  property bool active: true
  property real swayPhase: 0
  property bool interactive: true
  property string fontFamily: Style.font.family
  property color rimColor: Color.foreground
  property color hubColor: Color.background

  readonly property bool spinning: spinAnim.running
  readonly property int count: wheel && wheel.options ? wheel.options.length : 0
  readonly property real radius: Math.min(width, height) / 2 - pointerSize * 0.35
  readonly property real pointerSize: Math.max(14, Math.min(width, height) * 0.075)

  signal clicked()
  signal landed(int index)

  property int pendingWinner: -1
  property real discAngle: angle
  property real swayAmount: 1
  property real swayTime: 0
  // Gentle rock while resting: about 2 degrees each way, once every 4 s.
  readonly property real swayDegrees: 2 * swayAmount * Math.sin(2 * Math.PI * swayTime / 4 + swayPhase)

  onAngleChanged: if (!spinAnim.running) discAngle = angle
  onWheelChanged: canvas.requestPaint()
  onThemeChanged: canvas.requestPaint()

  function spin(winner) {
    if (count < 1 || spinAnim.running) return false
    pendingWinner = winner
    spinAnim.from = discAngle
    spinAnim.to = Logic.targetAngle(discAngle, winner, count)
    swayOff.restart()
    spinAnim.restart()
    return true
  }

  // Jump to the end of a spin (used when the window closes mid-spin).
  function finishNow() {
    if (!spinAnim.running) return
    var to = spinAnim.to
    spinAnim.stop()
    discAngle = to
    land()
  }

  function land() {
    swayAmount = 0
    swayOn.restart()
    var w = pendingWinner
    pendingWinner = -1
    if (w >= 0) root.landed(w)
  }

  NumberAnimation {
    id: spinAnim
    target: root
    property: "discAngle"
    duration: 5200
    easing.type: Easing.OutQuart
    onFinished: root.land()
  }
  NumberAnimation { id: swayOff; target: root; property: "swayAmount"; to: 0; duration: 300; easing.type: Easing.InOutQuad }
  NumberAnimation { id: swayOn; target: root; property: "swayAmount"; to: 1; duration: 1200; easing.type: Easing.InOutQuad }

  FrameAnimation {
    running: root.active && root.visible && !spinAnim.running
    onTriggered: root.swayTime += frameTime
  }

  // The pointer kicks each time a slice edge passes under it.
  property int lastIndex: -1
  onDiscAngleChanged: {
    var i = Logic.indexAt(discAngle + swayDegrees, count)
    if (spinAnim.running && i !== lastIndex) kick.restart()
    lastIndex = i
  }

  Item {
    id: disc
    width: root.radius * 2
    height: width
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: -root.pointerSize * 0.35
    rotation: root.discAngle + root.swayDegrees

    Canvas {
      id: canvas
      anchors.fill: parent
      antialiasing: true
      renderStrategy: Canvas.Cooperative

      property var sizes: ({})

      function imagesWanted() {
        var list = []
        if (!root.wheel) return list
        for (var i = 0; i < root.count; i++) {
          var img = root.wheel.options[i].image
          if (Logic.isLocalImage(img)) list.push(img)
        }
        return list
      }

      // Bounding box of the slice from angle a0 to a1 (radians).
      function wedgeBox(r, a0, a1) {
        var xs = [r, r + Math.cos(a0) * r, r + Math.cos(a1) * r]
        var ys = [r, r + Math.sin(a0) * r, r + Math.sin(a1) * r]
        for (var k = Math.ceil(a0 / (Math.PI / 2)); k * Math.PI / 2 <= a1; k++) {
          xs.push(r + Math.cos(k * Math.PI / 2) * r)
          ys.push(r + Math.sin(k * Math.PI / 2) * r)
        }
        var x0 = Math.min.apply(null, xs)
        var y0 = Math.min.apply(null, ys)
        return { x: x0, y: y0, w: Math.max(1, Math.max.apply(null, xs) - x0), h: Math.max(1, Math.max.apply(null, ys) - y0) }
      }

      onPaint: {
        var ctx = getContext("2d")
        var r = width / 2
        ctx.reset()
        if (root.count < 1) return
        var step = 2 * Math.PI / root.count
        var wanted = imagesWanted()
        for (var w = 0; w < wanted.length; w++)
          if (!isImageLoaded(wanted[w]) && !isImageLoading(wanted[w]) && !isImageError(wanted[w]))
            loadImage(wanted[w])

        for (var i = 0; i < root.count; i++) {
          var a0 = i * step
          var a1 = a0 + step
          var color = Logic.sliceColor(root.wheel, i, root.theme)
          ctx.beginPath()
          ctx.moveTo(r, r)
          ctx.arc(r, r, r, a0, a1, false)
          ctx.closePath()
          ctx.fillStyle = color
          ctx.fill()

          var img = root.wheel.options[i].image
          if (Logic.isLocalImage(img) && isImageLoaded(img)) {
            // Reading the size copies the pixels, so do it once per picture.
            if (!sizes[img]) {
              var data = ctx.createImageData(img)
              sizes[img] = { w: data ? data.width : 0, h: data ? data.height : 0 }
            }
            var iw = sizes[img].w
            var ih = sizes[img].h
            if (iw > 0 && ih > 0) {
              ctx.save()
              ctx.beginPath()
              ctx.moveTo(r, r)
              ctx.arc(r, r, r, a0, a1, false)
              ctx.closePath()
              ctx.clip()
              // Cover the wedge's bounding box, cropped to the wedge.
              var b = wedgeBox(r, a0, a1)
              var scale = Math.max(b.w / iw, b.h / ih)
              // Whole pixels inside the picture, or drawImage refuses.
              var sw = Math.max(1, Math.min(iw, Math.floor(b.w / scale)))
              var sh = Math.max(1, Math.min(ih, Math.floor(b.h / scale)))
              try {
                ctx.drawImage(img, Math.floor((iw - sw) / 2), Math.floor((ih - sh) / 2), sw, sh, b.x, b.y, b.w, b.h)
              } catch (e) {}
              ctx.restore()
            }
          }

          // Thin divider so neighbors with close colors still separate.
          ctx.beginPath()
          ctx.moveTo(r, r)
          ctx.lineTo(r + Math.cos(a0) * r, r + Math.sin(a0) * r)
          ctx.strokeStyle = Qt.rgba(0, 0, 0, 0.25)
          ctx.lineWidth = Math.max(1, r * 0.006)
          ctx.stroke()
        }
      }

      onImageLoaded: requestPaint()
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
    }

    Repeater {
      model: root.count
      delegate: Item {
        id: slot
        required property int index
        readonly property var option: root.wheel ? root.wheel.options[index] : null
        readonly property real step: 360 / Math.max(1, root.count)
        readonly property string sliceFill: String(Logic.sliceColor(root.wheel, index, root.theme))
        width: disc.width
        height: disc.height
        rotation: (index + 0.5) * step

        Text {
          textFormat: Text.PlainText
          x: parent.width / 2 + root.radius * 0.24
          width: root.radius * 0.68
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          // Long labels shrink to fit first, then end with "…".
          fontSizeMode: Text.HorizontalFit
          minimumPixelSize: Math.max(8, font.pixelSize * 0.55)
          elide: Text.ElideRight
          text: slot.option ? slot.option.label : ""
          color: Logic.textOn(slot.sliceFill)
          style: slot.option && slot.option.image ? Text.Outline : Text.Normal
          styleColor: Logic.textOn(slot.sliceFill) === "#000000" ? "#ffffff" : "#000000"
          font.family: root.fontFamily
          font.bold: true
          font.pixelSize: Math.max(8, Math.min(root.radius * 0.12,
            root.radius * 0.62 * Math.sin(Math.min(Math.PI / 2, Math.PI / Math.max(1, root.count)))))
        }
      }
    }
  }

  // Rim
  Rectangle {
    anchors.fill: disc
    radius: width / 2
    color: "transparent"
    border.width: Math.max(2, root.radius * 0.02)
    border.color: Util.alpha(root.rimColor, 0.85)
  }

  // Hub
  Rectangle {
    width: root.radius * 0.26
    height: width
    radius: width / 2
    anchors.centerIn: disc
    color: root.hubColor
    border.width: Math.max(2, root.radius * 0.02)
    border.color: Util.alpha(root.rimColor, 0.85)
  }

  // Pointer on the right, pointing in.
  Item {
    id: pointer
    width: root.pointerSize * 1.3
    height: root.pointerSize
    x: disc.x + disc.width - width * 0.45
    y: disc.y + disc.height / 2 - height / 2
    transformOrigin: Item.Right
    rotation: 0

    Canvas {
      id: pointerCanvas
      anchors.fill: parent
      antialiasing: true
      property color fill: Color.accent
      property color edge: root.rimColor
      onFillChanged: requestPaint()
      onEdgeChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.beginPath()
        ctx.moveTo(0, height / 2)
        ctx.lineTo(width, 2)
        ctx.lineTo(width, height - 2)
        ctx.closePath()
        ctx.fillStyle = fill
        ctx.fill()
        ctx.lineWidth = 2
        ctx.strokeStyle = edge
        ctx.stroke()
      }
    }

    SequentialAnimation {
      id: kick
      NumberAnimation { target: pointer; property: "rotation"; to: -16; duration: 40; easing.type: Easing.OutQuad }
      NumberAnimation { target: pointer; property: "rotation"; to: 0; duration: 140; easing.type: Easing.OutBack }
    }
  }

  MouseArea {
    anchors.fill: disc
    enabled: root.interactive
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: function(mouse) {
      var dx = mouse.x - width / 2
      var dy = mouse.y - height / 2
      if (dx * dx + dy * dy <= (width / 2) * (width / 2)) root.clicked()
    }
  }
}

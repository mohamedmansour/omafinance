import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var values: []
  property color lineColor: Color.foreground
  property color fillColor: Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.22)
  property color zeroLineColor: Color.muted
  property real zeroValue: Number.NaN
  property bool showZeroLine: false
  property int pad: 2
  property bool filled: true
  property bool interactive: false
  property string currency: "USD"
  property var priceHint: 2

  property bool hovering: false
  property int hoverIndex: -1
  property real hoverValue: Number.NaN
  property real hoverX: 0
  property real hoverY: 0
  property real hoverPointerX: 0
  property var cachedGeometry: null

  function numericValues() {
    var vals = root.values || []
    var nums = []
    var i
    for (i = 0; i < vals.length; i++) {
      if (vals[i] === null || vals[i] === undefined || vals[i] === "") continue
      var n = Number(vals[i])
      if (isFinite(n)) nums.push(n)
    }
    return nums
  }

  function buildGeom() {
    var nums = numericValues()
    var w = width
    var h = height
    var left = root.pad
    var right = Math.max(left + 1, w - root.pad)
    var top = root.pad
    var bot = Math.max(top + 1, h - root.pad)
    var unset = {
      nums: nums,
      min: 0,
      max: 1,
      span: 1,
      left: left,
      right: right,
      top: top,
      bot: bot,
      innerW: right - left,
      innerH: bot - top,
      drawZero: false,
      zero: 0
    }
    if (nums.length === 0) {
      unset.xs = []
      unset.ys = []
      unset.zeroY = Number.NaN
      return unset
    }

    var min = nums[0]
    var max = nums[0]
    var i
    for (i = 1; i < nums.length; i++) {
      if (nums[i] < min) min = nums[i]
      if (nums[i] > max) max = nums[i]
    }
    var zero = Number(root.zeroValue)
    var drawZero = root.showZeroLine && isFinite(zero)
    if (drawZero) {
      if (zero < min) min = zero
      if (zero > max) max = zero
    }
    var span = max - min
    if (span === 0) span = Math.abs(max) * 0.01 || 1
    min -= span * 0.08
    max += span * 0.08
    span = max - min
    var geometry = {
      nums: nums,
      min: min,
      max: max,
      span: span,
      left: left,
      right: right,
      top: top,
      bot: bot,
      innerW: right - left,
      innerH: bot - top,
      drawZero: drawZero,
      zero: zero
    }
    geometry.xs = []
    geometry.ys = []
    for (i = 0; i < nums.length; i++) {
      geometry.xs.push(xAt(geometry, i))
      geometry.ys.push(yAt(geometry, nums[i]))
    }
    geometry.zeroY = drawZero ? yAt(geometry, zero) : Number.NaN
    return geometry
  }

  function refreshGeometry() {
    cachedGeometry = buildGeom()
    canvas.requestPaint()
    if (hovering) updateHover(hoverPointerX)
  }

  function xAt(g, idx) {
    if (g.nums.length <= 1) return g.left + g.innerW / 2
    return g.left + g.innerW * (idx / (g.nums.length - 1))
  }

  function yAt(g, val) {
    return g.top + g.innerH * (1 - (val - g.min) / g.span)
  }

  function updateHover(px) {
    var g = cachedGeometry
    hoverPointerX = px
    if (!g) return
    if (g.nums.length === 0) {
      clearHover()
      return
    }
    var t = g.innerW <= 0 ? 0 : (px - g.left) / g.innerW
    if (t < 0) t = 0
    if (t > 1) t = 1
    var idx = Math.round(t * Math.max(0, g.nums.length - 1))
    hoverIndex = idx
    hoverValue = g.nums[idx]
    hoverX = g.xs[idx]
    hoverY = g.ys[idx]
    hovering = true
  }

  function clearHover() {
    hovering = false
    hoverIndex = -1
    hoverValue = Number.NaN
  }

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      var w = width
      var h = height
      ctx.clearRect(0, 0, w, h)

      var g = root.cachedGeometry
      if (!g) return
      ctx.lineWidth = 1.5
      ctx.lineJoin = "round"
      ctx.lineCap = "round"

      if (g.nums.length === 0) {
        ctx.globalAlpha = 0.35
        ctx.strokeStyle = root.lineColor
        ctx.beginPath()
        ctx.moveTo(root.pad, h / 2)
        ctx.lineTo(Math.max(root.pad, w - root.pad), h / 2)
        ctx.stroke()
        ctx.globalAlpha = 1
        return
      }

      if (g.drawZero) {
        ctx.save()
        ctx.lineWidth = 1
        ctx.globalAlpha = 0.55
        ctx.strokeStyle = root.zeroLineColor
        if (ctx.setLineDash) ctx.setLineDash([2, 3])
        ctx.beginPath()
        ctx.moveTo(g.left, g.zeroY)
        ctx.lineTo(g.right, g.zeroY)
        ctx.stroke()
        ctx.restore()
      }

      var i
      if (root.filled) {
        ctx.beginPath()
        ctx.moveTo(g.xs[0], g.ys[0])
        for (i = 1; i < g.nums.length; i++) ctx.lineTo(g.xs[i], g.ys[i])
        ctx.lineTo(g.xs[g.nums.length - 1], g.bot)
        ctx.lineTo(g.xs[0], g.bot)
        ctx.closePath()
        ctx.fillStyle = root.fillColor
        ctx.fill()
      }

      ctx.beginPath()
      ctx.moveTo(g.xs[0], g.ys[0])
      for (i = 1; i < g.nums.length; i++) ctx.lineTo(g.xs[i], g.ys[i])
      ctx.strokeStyle = root.lineColor
      ctx.stroke()
    }
  }

  Component.onCompleted: refreshGeometry()
  onValuesChanged: refreshGeometry()
  onLineColorChanged: canvas.requestPaint()
  onFillColorChanged: canvas.requestPaint()
  onZeroLineColorChanged: canvas.requestPaint()
  onZeroValueChanged: refreshGeometry()
  onShowZeroLineChanged: refreshGeometry()
  onPadChanged: refreshGeometry()
  onWidthChanged: refreshGeometry()
  onHeightChanged: refreshGeometry()
  onFilledChanged: canvas.requestPaint()

  MouseArea {
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: enabled ? Qt.CrossCursor : Qt.ArrowCursor
    onPositionChanged: function(mouse) { root.updateHover(mouse.x) }
    onExited: root.clearHover()
  }

  Rectangle {
    visible: root.interactive && root.hovering
    x: Math.round(root.hoverX)
    width: 1
    height: parent.height
    color: Qt.rgba(root.lineColor.r, root.lineColor.g, root.lineColor.b, 0.35)
  }

  Rectangle {
    visible: root.interactive && root.hovering && isFinite(root.hoverValue)
    width: Style.space(7)
    height: Style.space(7)
    radius: width / 2
    x: root.hoverX - width / 2
    y: root.hoverY - height / 2
    color: root.lineColor
    border.width: 1
    border.color: Color.popups.background
  }

  Rectangle {
    id: badge
    visible: root.interactive && root.hovering && isFinite(root.hoverValue)
    readonly property int maxX: Math.max(0, root.width - width)
    x: Math.min(maxX, Math.max(0, root.hoverX - width / 2))
    y: Math.max(0, Math.min(root.hoverY - height - Style.space(8), root.height - height))
    radius: height / 2
    color: Color.popups.background
    border.width: 1
    border.color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.14)
    implicitWidth: badgeLabel.implicitWidth + Style.space(12)
    implicitHeight: badgeLabel.implicitHeight + Style.space(6)

    Text {
      id: badgeLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: Model.formatPrice(root.hoverValue, root.currency, root.priceHint)
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
  }
}

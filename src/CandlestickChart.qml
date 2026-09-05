import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
    id: root

    property string symbol: ""
    property var candles: []
    property color upColor: Color.foreground
    property color downColor: Color.foreground
    property color gridColor: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.08)
    property color crosshairColor: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.35)
    property color labelColor: Color.muted
    property string currency: "USD"
    property var priceHint: 2
    property string rangeKey: "1D"
    property bool interactive: true
    property int pad: Style.space(6)
    property string fontFamily: Style.font.family

    property int viewStart: 0
    property int viewCount: -1
    property real dragStartX: 0
    property int dragStartViewStart: 0
    property int dragStartViewCount: 0
    property real dragStartCenterIndex: 0
    property real dragStartRatio: 0.5
    property bool dragging: false
    property bool isShiftDrag: false

    property bool hovering: false
    property int hoverIndex: -1
    property var hoverCandle: null
    property real hoverX: 0
    property real hoverY: 0
    property real hoverPointerX: 0
    property var cachedGeometry: null

    function resetZoom() {
        viewStart = 0;
        viewCount = -1;
        refreshGeometry();
    }

    function validCandles() {
        var src = root.candles || [];
        var out = [];
        for (var i = 0; i < src.length; i++) {
            var c = src[i];
            if (!c)
                continue;
            var o = Number(c.open);
            var h = Number(c.high);
            var l = Number(c.low);
            var cl = Number(c.close);
            if (isFinite(o) && isFinite(h) && isFinite(l) && isFinite(cl)) {
                out.push({
                    timestamp: c.timestamp,
                    open: o,
                    high: h,
                    low: l,
                    close: cl,
                    volume: c.volume || 0
                });
            }
        }
        return out;
    }

    function buildGeom() {
        var all = validCandles();
        var total = all.length;
        var w = width;
        var h = height;
        var topPad = root.pad + Style.space(20);
        var botPad = root.pad + Style.space(12);
        var left = root.pad;
        var right = Math.max(left + 1, w - root.pad);
        var top = topPad;
        var bot = Math.max(top + 1, h - botPad);
        var unset = {
            candles: [],
            strats: [],
            min: 0,
            max: 1,
            span: 1,
            left: left,
            right: right,
            top: top,
            bot: bot,
            innerW: right - left,
            innerH: bot - top,
            slotW: 1,
            candleW: 1,
            vStart: 0,
            vCount: 0,
            totalCandles: 0,
            xs: [],
            yOpens: [],
            yHighs: [],
            yLows: [],
            yCloses: []
        };
        if (total === 0)
            return unset;

        var minBars = 8;
        var vCount = (root.viewCount > 0 && root.viewCount < total) ? Math.max(minBars, root.viewCount) : total;
        var maxStart = Math.max(0, total - vCount);
        var vStart = Math.max(0, Math.min(maxStart, root.viewStart));

        var list = all.slice(vStart, vStart + vCount);
        if (list.length === 0)
            return unset;

        var strats = [];
        for (var si = 0; si < list.length; si++) {
            var globalIdx = vStart + si;
            var prev = globalIdx > 0 ? all[globalIdx - 1] : null;
            var st = Model.stratScenario(list[si], prev);
            list[si].strat = st;
            strats.push(st);
        }

        var min = list[0].low;
        var max = list[0].high;
        var i;
        for (i = 1; i < list.length; i++) {
            if (list[i].low < min)
                min = list[i].low;
            if (list[i].high > max)
                max = list[i].high;
        }
        var span = max - min;
        if (span === 0)
            span = Math.abs(max) * 0.01 || 1;
        min -= span * 0.06;
        max += span * 0.06;
        span = max - min;

        var innerW = right - left;
        var innerH = bot - top;
        var slotW = innerW / Math.max(1, list.length);
        var candleW = Math.max(1.2, Math.min(28, slotW * 0.72));

        var geometry = {
            candles: list,
            strats: strats,
            min: min,
            max: max,
            span: span,
            left: left,
            right: right,
            top: top,
            bot: bot,
            innerW: innerW,
            innerH: innerH,
            slotW: slotW,
            candleW: candleW,
            vStart: vStart,
            vCount: vCount,
            totalCandles: total,
            xs: [],
            yOpens: [],
            yHighs: [],
            yLows: [],
            yCloses: []
        };

        for (i = 0; i < list.length; i++) {
            var cx = left + (i + 0.5) * slotW;
            geometry.xs.push(cx);
            geometry.yOpens.push(top + innerH * (1 - (list[i].open - min) / span));
            geometry.yHighs.push(top + innerH * (1 - (list[i].high - min) / span));
            geometry.yLows.push(top + innerH * (1 - (list[i].low - min) / span));
            geometry.yCloses.push(top + innerH * (1 - (list[i].close - min) / span));
        }
        return geometry;
    }

    function refreshGeometry() {
        cachedGeometry = buildGeom();
        canvas.requestPaint();
        if (hovering)
            updateHover(hoverPointerX);
    }

    function updateHover(px) {
        var g = cachedGeometry;
        hoverPointerX = px;
        if (!g || g.candles.length === 0) {
            clearHover();
            return;
        }
        var offset = px - g.left;
        var idx = Math.floor(offset / Math.max(1, g.slotW));
        if (idx < 0)
            idx = 0;
        if (idx >= g.candles.length)
            idx = g.candles.length - 1;
        hoverIndex = idx;
        hoverCandle = g.candles[idx];
        hoverX = g.xs[idx];
        hoverY = g.yCloses[idx];
        hovering = true;
    }

    function clearHover() {
        hovering = false;
        hoverIndex = -1;
        hoverCandle = null;
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d");
            var w = width;
            var h = height;
            ctx.clearRect(0, 0, w, h);

            var g = root.cachedGeometry;
            if (!g || g.candles.length === 0) {
                ctx.globalAlpha = 0.3;
                ctx.strokeStyle = root.gridColor;
                ctx.beginPath();
                ctx.moveTo(root.pad, h / 2);
                ctx.lineTo(Math.max(root.pad, w - root.pad), h / 2);
                ctx.stroke();
                ctx.globalAlpha = 1;
                return;
            }

            // Candlesticks rendering
            var len = g.candles.length;
            var cW = g.candleW;
            var halfW = cW / 2;

            for (var i = 0; i < len; i++) {
                var c = g.candles[i];
                var isUp = c.close >= c.open;
                var color = isUp ? root.upColor : root.downColor;
                var cx = Math.round(g.xs[i]) + 0.5;
                var yH = Math.round(g.yHighs[i]);
                var yL = Math.round(g.yLows[i]);
                var yO = Math.round(g.yOpens[i]);
                var yC = Math.round(g.yCloses[i]);

                ctx.strokeStyle = color;
                ctx.fillStyle = color;
                ctx.lineWidth = 1;

                // Wick (Upper & Lower)
                ctx.beginPath();
                ctx.moveTo(cx, yH);
                ctx.lineTo(cx, yL);
                ctx.stroke();

                // Candle Body
                var bodyTop = Math.min(yO, yC);
                var bodyHeight = Math.max(1.5, Math.abs(yC - yO));
                var bodyLeft = Math.round(cx - halfW);
                ctx.fillRect(bodyLeft, bodyTop, Math.max(1, Math.round(cW)), bodyHeight);
            }

            // Strat numbers rendering
            if (g.slotW >= 6 && g.strats && g.strats.length > 0) {
                var fontSize = Math.max(9, Math.min(11, Math.round(g.slotW * 0.55)));
                ctx.font = "bold " + fontSize + "px " + root.fontFamily;
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";

                for (var si = 0; si < len; si++) {
                    var s = g.strats[si];
                    if (!s || s === "-")
                        continue;

                    var scx = Math.round(g.xs[si]) + 0.5;
                    var syH = Math.round(g.yHighs[si]);
                    var syL = Math.round(g.yLows[si]);

                    var sColor = root.labelColor;
                    if (s === "2u")
                        sColor = root.upColor;
                    else if (s === "2d")
                        sColor = root.downColor;
                    else if (s === "3")
                        sColor = Color.accent;

                    ctx.fillStyle = sColor;
                    if (s === "2d") {
                        ctx.fillText(s, scx, syL + fontSize * 0.85);
                    } else {
                        ctx.fillText(s, scx, syH - fontSize * 0.85);
                    }
                }
            }
        }
    }

    Component.onCompleted: refreshGeometry()
    onSymbolChanged: resetZoom()
    onRangeKeyChanged: resetZoom()
    onCandlesChanged: refreshGeometry()
    onUpColorChanged: canvas.requestPaint()
    onDownColorChanged: canvas.requestPaint()
    onGridColorChanged: canvas.requestPaint()
    onPadChanged: refreshGeometry()
    onWidthChanged: refreshGeometry()
    onHeightChanged: refreshGeometry()

    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_R && (event.modifiers & Qt.AltModifier)) {
            root.resetZoom();
            event.accepted = true;
        }
    }

    MouseArea {
        id: chartMouseArea
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        preventStealing: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.dragging ? Qt.ClosedHandCursor : (enabled ? Qt.CrossCursor : Qt.ArrowCursor)

        onPressed: function (mouse) {
            if (mouse.button === Qt.LeftButton) {
                root.dragging = true;
                root.isShiftDrag = (mouse.modifiers & Qt.ShiftModifier) || (mouse.modifiers & Qt.ControlModifier);
                root.dragStartX = mouse.x;
                var all = root.validCandles();
                var total = all.length;
                var g = root.cachedGeometry;
                root.dragStartViewStart = g ? g.vStart : 0;
                root.dragStartViewCount = (g && g.vCount) ? g.vCount : total;
                var innerW = g ? g.innerW : Math.max(1, root.width);
                root.dragStartRatio = Math.max(0, Math.min(1, (mouse.x - root.pad) / innerW));
                root.dragStartCenterIndex = root.dragStartViewStart + root.dragStartViewCount * root.dragStartRatio;
            }
        }

        onPositionChanged: function (mouse) {
            if (root.dragging && root.cachedGeometry) {
                var all = root.validCandles();
                var total = all.length;
                var g = root.cachedGeometry;

                if (root.isShiftDrag && total > 8) {
                    // Shift+Drag = Zoom
                    var deltaX = mouse.x - root.dragStartX;
                    var countDelta = Math.round(deltaX * 0.25);
                    var nextCount = Math.max(8, Math.min(total, root.dragStartViewCount - countDelta));
                    var nextStart = Math.max(0, Math.min(total - nextCount, Math.round(root.dragStartCenterIndex - nextCount * root.dragStartRatio)));

                    root.viewCount = nextCount >= total ? -1 : nextCount;
                    root.viewStart = nextStart;
                    root.refreshGeometry();
                } else if (g && g.totalCandles > g.vCount) {
                    // Normal Drag = PAN (Move left/right through time)
                    var deltaX = mouse.x - root.dragStartX;
                    var shiftBars = Math.round(deltaX / Math.max(1, g.slotW));
                    var maxStart = Math.max(0, g.totalCandles - g.vCount);
                    var nextStart = Math.max(0, Math.min(maxStart, root.dragStartViewStart - shiftBars));

                    if (nextStart !== root.viewStart) {
                        root.viewStart = nextStart;
                        root.refreshGeometry();
                    }
                }
            }
            root.updateHover(mouse.x);
        }

        onReleased: function (mouse) {
            root.dragging = false;
            root.isShiftDrag = false;
        }

        onCanceled: {
            root.dragging = false;
            root.isShiftDrag = false;
        }

        onWheel: function (wheel) {
            var all = root.validCandles();
            var total = all.length;
            if (total <= 8)
                return;
            var g = root.cachedGeometry;
            if (!g)
                return;
            var curCount = g.vCount ? g.vCount : total;
            var curStart = g.vStart ? g.vStart : 0;
            var innerW = g.innerW ? g.innerW : Math.max(1, root.width);
            var ratio = Math.max(0, Math.min(1, (wheel.x - root.pad) / innerW));

            var isHorizontal = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y);
            var isShiftVertical = (wheel.modifiers & Qt.ShiftModifier) && wheel.angleDelta.y !== 0;

            if (isHorizontal || isShiftVertical) {
                // Horizontal scroll or Shift+Scroll = PAN left/right (preserving zoom level)
                if (g.totalCandles > g.vCount) {
                    var delta = isShiftVertical ? -wheel.angleDelta.y : -wheel.angleDelta.x;
                    var bars = Math.round((delta / 120) * Math.max(1, Math.round(curCount * 0.10)));
                    if (bars === 0 && delta !== 0)
                        bars = delta > 0 ? 1 : -1;
                    var maxStart = Math.max(0, g.totalCandles - g.vCount);
                    var nextStart = Math.max(0, Math.min(maxStart, curStart + bars));
                    if (nextStart !== root.viewStart) {
                        root.viewStart = nextStart;
                        root.refreshGeometry();
                    }
                }
            } else if (wheel.angleDelta.y !== 0) {
                var deltaBars = Math.round((Math.abs(wheel.angleDelta.y) / 120) * Math.max(1, Math.round(curCount * 0.06)));
                if (deltaBars < 1)
                    deltaBars = 1;

                if (wheel.angleDelta.y > 0) {
                    // Zoom IN: reduce visible bar count (centered around mouse ratio)
                    var nextCount = Math.max(8, curCount - deltaBars);
                    var diff = curCount - nextCount;
                    var nextStart = Math.max(0, Math.min(total - nextCount, Math.round(curStart + diff * ratio)));
                    root.viewCount = nextCount;
                    root.viewStart = nextStart;
                    root.refreshGeometry();
                } else if (wheel.angleDelta.y < 0) {
                    // Zoom OUT: increase visible bar count (centered around mouse ratio)
                    var nextCount = Math.min(total, curCount + deltaBars);
                    var diff = nextCount - curCount;
                    var nextStart = Math.max(0, Math.min(total - nextCount, Math.round(curStart - diff * ratio)));
                    root.viewCount = nextCount >= total ? -1 : nextCount;
                    root.viewStart = nextStart;
                    root.refreshGeometry();
                }
            }
            wheel.accepted = true;
        }

        onExited: {
            if (!root.dragging)
                root.clearHover();
        }
    }

    // Vertical Crosshair
    Rectangle {
        visible: root.interactive && root.hovering
        x: Math.round(root.hoverX)
        width: 1
        height: parent.height
        color: root.crosshairColor
    }

    // Horizontal Crosshair
    Rectangle {
        visible: root.interactive && root.hovering
        y: Math.round(root.hoverY)
        x: root.pad
        width: Math.max(0, parent.width - 2 * root.pad)
        height: 1
        color: root.crosshairColor
    }

    // Candle Selection Highlight Pip
    Rectangle {
        visible: root.interactive && root.hovering && root.hoverCandle !== null
        width: Style.space(6)
        height: Style.space(6)
        radius: width / 2
        x: root.hoverX - width / 2
        y: root.hoverY - height / 2
        color: root.hoverCandle && root.hoverCandle.close >= root.hoverCandle.open ? root.upColor : root.downColor
        border.width: 1
        border.color: Color.popups.background
    }

    // Floating Tooltip / Status Readout Header
    Item {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        height: Style.space(16)
        visible: root.hovering && root.hoverCandle !== null

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
                textFormat: Text.PlainText
                text: root.hoverCandle ? Model.formatCandleTime(root.hoverCandle.timestamp, root.rangeKey) : ""
                color: Color.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
            }

            Text {
                visible: root.hoverCandle && root.hoverCandle.strat && root.hoverCandle.strat !== "-"
                textFormat: Text.PlainText
                text: root.hoverCandle && root.hoverCandle.strat ? root.hoverCandle.strat : ""
                color: {
                    if (!root.hoverCandle)
                        return Color.foreground;
                    var s = root.hoverCandle.strat;
                    if (s === "2u")
                        return root.upColor;
                    if (s === "2d")
                        return root.downColor;
                    if (s === "3")
                        return Color.accent;
                    return Color.muted;
                }
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
            }

            Text {
                textFormat: Text.PlainText
                text: {
                    if (!root.hoverCandle)
                        return "";
                    var c = root.hoverCandle;
                    return "O " + Model.formatPrice(c.open, root.currency, root.priceHint) + "   H " + Model.formatPrice(c.high, root.currency, root.priceHint) + "   L " + Model.formatPrice(c.low, root.currency, root.priceHint) + "   C " + Model.formatPrice(c.close, root.currency, root.priceHint);
                }
                color: root.hoverCandle && root.hoverCandle.close >= root.hoverCandle.open ? root.upColor : root.downColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
            }
        }
    }

    // Floating Close Price Badge
    Rectangle {
        id: priceBadge
        visible: root.interactive && root.hovering && root.hoverCandle !== null
        readonly property int maxX: Math.max(0, root.width - width - root.pad)
        x: Math.min(maxX, Math.max(root.pad, root.hoverX - width / 2))
        y: Math.max(root.pad + Style.space(18), Math.min(root.hoverY - height - Style.space(8), root.height - height - root.pad))
        radius: height / 2
        color: Color.popups.background
        border.width: 1
        border.color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.18)
        implicitWidth: badgeText.implicitWidth + Style.space(12)
        implicitHeight: badgeText.implicitHeight + Style.space(6)

        Text {
            id: badgeText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.hoverCandle ? Model.formatPrice(root.hoverCandle.close, root.currency, root.priceHint) : ""
            color: root.hoverCandle && root.hoverCandle.close >= root.hoverCandle.open ? root.upColor : root.downColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
        }
    }
}

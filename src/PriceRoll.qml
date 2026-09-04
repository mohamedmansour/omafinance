import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
    id: root

    property var price: null
    property string currency: "USD"
    property var priceHint: 2
    property color neutralColor: Color.foreground
    property color upColor: neutralColor
    property color downColor: neutralColor
    property string fontFamily: Style.font.family
    property real fontSize: Style.font.display
    property bool bold: true
    property bool active: true

    property string currentText: "-"
    property var slots: []
    property real lastPrice: Number.NaN
    property real rollProgress: 1
    property int rollDirection: 0
    property bool animating: false

    readonly property string formattedText: Model.formatPrice(price, currency, priceHint)
    readonly property color activeColor: rollDirection > 0 ? upColor : downColor

    implicitWidth: digitRow.implicitWidth
    implicitHeight: digitRow.implicitHeight
    clip: true

    function buildSlots(previous, next) {
        var count = Math.max(previous.length, next.length);
        var result = [];
        for (var i = 0; i < count; i++) {
            var oldCharacter = previous.charAt(i);
            var newCharacter = next.charAt(i);
            result.push({
                oldCharacter: oldCharacter,
                newCharacter: newCharacter,
                changed: oldCharacter !== newCharacter && (/\d/.test(oldCharacter) || /\d/.test(newCharacter))
            });
        }
        return result;
    }

    function settlePrice(text) {
        currentText = text;
        slots = buildSlots(text, text);
    }

    function syncPrice(animate) {
        var next = Number(price);
        var hasNext = price !== null && price !== undefined && isFinite(next);
        var hasPrevious = isFinite(lastPrice);
        var nextText = formattedText;

        if (!active || !hasNext || !hasPrevious || next === lastPrice) {
            rollAnimation.stop();
            settleTimer.stop();
            settlePrice(nextText);
            lastPrice = hasNext ? next : Number.NaN;
            rollProgress = 1;
            animating = false;
            return;
        }

        rollAnimation.stop();
        settleTimer.stop();
        slots = buildSlots(currentText, nextText);
        currentText = nextText;
        rollDirection = next > lastPrice ? 1 : -1;
        lastPrice = next;
        rollProgress = 0;
        animating = animate;
        if (animate)
            rollAnimation.restart();
        else
            rollProgress = 1;
    }

    onFormattedTextChanged: syncPrice(active)
    onActiveChanged: {
        if (active)
            syncPrice(false);
        else {
            rollAnimation.stop();
            settleTimer.stop();
            animating = false;
            settlePrice(formattedText);
            rollProgress = 1;
        }
    }
    Component.onCompleted: syncPrice(false)

    Row {
        id: digitRow

        Repeater {
            model: root.slots

            Item {
                required property var modelData

                width: Math.max(oldDigit.implicitWidth, newDigit.implicitWidth)
                height: Math.max(oldDigit.implicitHeight, newDigit.implicitHeight)

                Text {
                    id: oldDigit
                    visible: root.animating && modelData.changed && text !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.rollDirection > 0 ? -root.rollProgress * parent.height : root.rollProgress * parent.height
                    textFormat: Text.PlainText
                    text: modelData.oldCharacter
                    color: root.activeColor
                    opacity: 1 - root.rollProgress
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize
                    font.bold: root.bold
                }

                Text {
                    id: newDigit
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: modelData.changed && root.animating
                        ? (root.rollDirection > 0 ? (1 - root.rollProgress) * parent.height : -(1 - root.rollProgress) * parent.height)
                        : 0
                    textFormat: Text.PlainText
                    text: modelData.newCharacter
                    color: modelData.changed && root.animating ? root.activeColor : root.neutralColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize
                    font.bold: root.bold

                    Behavior on color {
                        ColorAnimation {
                            duration: 240
                        }
                    }
                }
            }
        }
    }

    SequentialAnimation {
        id: rollAnimation

        NumberAnimation {
            target: root
            property: "rollProgress"
            from: 0
            to: 1
            duration: 320
            easing.type: Easing.OutCubic
        }
        ScriptAction {
            script: {
                root.animating = false;
                settleTimer.restart();
            }
        }
    }

    Timer {
        id: settleTimer
        interval: 240
        repeat: false
        onTriggered: root.settlePrice(root.currentText)
    }
}

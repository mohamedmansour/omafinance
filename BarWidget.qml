import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "mohamedmansour.finance"

  readonly property color upColor: Qt.rgba(0.49, 0.73, 0.49, 1)
  readonly property color downColor: bar ? bar.urgent : Color.urgent
  readonly property string labelTone: panelLoader.item ? String(panelLoader.item.labelTone || "flat") : "flat"
  readonly property color pillColor: labelTone === "up"
    ? upColor
    : (labelTone === "down" ? downColor : (bar ? bar.barForeground : Color.foreground))

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property real openPanelIndicatorWidth: button.labelWidth

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: {
      if (!panelLoader.item) return "—"
      return root.vertical ? panelLoader.item.verticalLabel : panelLoader.item.label
    }
    foreground: root.pillColor
    useActiveColor: false
    tooltipText: ""
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}

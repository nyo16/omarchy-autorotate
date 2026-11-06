import QtQuick
import qs.Commons as Commons
import qs.Ui

// Rotation lock in the bar: click to lock or unlock, right-click to cycle the mode.
BarWidget {
  id: root
  moduleName: "io.github.nyo16.autorotate"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool hideWhenInactive: setting("hideWhenInactive", false) === true

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  visible: service !== null && (!hideWhenInactive || service.active)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string modeLabel: service ? strings.t("mode." + service.mode) : ""

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // md-screen_rotation_lock / md-screen_rotation
    text: root.service && root.service.locked ? "\u{f0478}" : "\u{f0475}"
    dimmed: !root.service || !root.service.active
    tooltipText: !root.service ? "" : root.service.locked
      ? strings.t("tooltip.locked").arg(root.modeLabel)
      : strings.t("tooltip.unlocked").arg(root.modeLabel)
    onPressed: function(b) {
      if (!root.service) return
      if (b === Qt.RightButton) root.service.cycleMode()
      else root.service.toggleLock()
    }
  }
}

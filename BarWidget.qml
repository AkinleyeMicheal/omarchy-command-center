import QtQuick
import qs.Ui

// Bar presence for the Command Center: a one-slot launcher button beside
// the Omarchy menu. Left click toggles the palette through the plugin's
// root-scope IPC route — the same summon the Super+Shift+K binding uses —
// and right click opens a terminal, the bar's click convention (copied
// from the menu widget).
//
// Deliberately stats-free (8.7): no timers, no processes at rest, so the
// button costs nothing until it is clicked, and it can never contend with
// metrics.sh for the palette's state files.
BarWidget {
  id: root
  moduleName: "fonsgaudii.cmdcenter"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Same codepoint the palette header wears (U+F0493, verified in the
    // installed JetBrainsMono Nerd Font).
    text: "󰒓"
    horizontalMargin: 7.5

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle fonsgaudii.cmdcenter '{}'")
    }
  }
}

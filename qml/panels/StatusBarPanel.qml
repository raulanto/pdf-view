import QtQuick
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    required property var theme
    required property var window
    required property var page

    Layout.fillWidth: true
    implicitHeight: window.focusMode ? 0 : Math.round(25 * theme.scale)
    visible: !window.focusMode
    color: theme.colors.surface
    Behavior on implicitHeight { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        ThemedLabel { theme: root.theme; text: root.page.busy ? "LEYENDO" : (root.page.error ? "ERROR" : "NORMAL"); color: root.page.error ? root.theme.colors.error : root.theme.colors.accent; font.pixelSize: 10; font.bold: true }
        ThemedLabel { theme: root.theme; Layout.fillWidth: true; text: root.page.hasPage ? root.window.documentName : "ningún documento abierto"; font.pixelSize: 11 }
        ThemedLabel { theme: root.theme; text: root.page.selectedText.length > 0 ? "selección · Ctrl+C" : (root.page.auxiliaryBusy ? "procesando…" : (root.page.selectionStartPage > 0 ? "inicio p."+root.page.selectionStartPage+" · Shift+clic" : "solo lectura")); font.pixelSize: 10; opacity: 0.65 }
    }
}

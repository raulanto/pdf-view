import QtQuick
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    required property var theme
    required property var window
    required property var picker

    Layout.fillWidth: true
    implicitHeight: window.focusMode ? 0 : Math.round(35 * theme.scale)
    visible: !window.focusMode
    color: theme.colors.surface
    Behavior on implicitHeight { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 4
        spacing: 8
        ThemedLabel { theme: root.theme; text: "▸ pdf-view"; color: root.theme.colors.accent; font.bold: true }
        ThemedLabel { theme: root.theme; Layout.fillWidth: true; text: root.window.documentPath || "~/"; opacity: 0.8; elide: Text.ElideMiddle }
        ThemedCommand { theme: root.theme; text: "configurar"; enabled: !root.window.document.saving; onClicked: root.window.showSettings() }
        ThemedCommand { theme: root.theme; text: "["+root.window.preferences.key("open","Ctrl+O")+"] abrir"; onClicked: root.picker.open() }
    }
}

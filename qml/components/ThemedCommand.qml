import QtQuick
import QtQuick.Controls

Button {
    required property var theme
    font.family: "monospace"
    font.pixelSize: Math.round(12 * theme.scale)
    padding: Math.round(7 * theme.scale)
    contentItem: Text {
        text: parent.text
        font: parent.font
        color: parent.enabled ? theme.colors.accent : theme.colors.border
    }
    background: Rectangle {
        color: parent.down || parent.hovered ? theme.colors.selection : "transparent"
        border.width: parent.visualFocus ? 1 : 0
        border.color: theme.colors.accent
    }
}

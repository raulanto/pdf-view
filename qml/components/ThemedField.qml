import QtQuick
import QtQuick.Controls

TextField {
    required property var theme
    font.family: "monospace"
    font.pixelSize: Math.round(12 * theme.scale)
    color: theme.colors.foreground
    selectionColor: theme.colors.accent
    selectedTextColor: theme.colors.onAccent
    placeholderTextColor: theme.colors.foreground
    padding: Math.round(6 * theme.scale)
    background: Rectangle {
        color: theme.colors.background
        border.color: parent.activeFocus ? theme.colors.accent : theme.colors.border
    }
}

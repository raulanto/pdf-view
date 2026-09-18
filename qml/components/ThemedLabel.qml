import QtQuick

Text {
    required property var theme
    textFormat: Text.PlainText
    color: theme.colors.foreground
    font.family: "monospace"
    font.pixelSize: Math.round(12 * theme.scale)
    elide: Text.ElideRight
}

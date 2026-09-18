import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Dialog {
    id: dialog
    required property var theme
    required property var page
    required property var canvasItem

    parent: canvasItem
    title: "[ seleccionar páginas ]"
    font.family: "monospace"
    modal: true
    closePolicy: Popup.NoAutoClose
    width: Math.min(380, canvasItem.width - 32)
    x: (canvasItem.width - width) / 2
    y: (canvasItem.height - height) / 2
    background: Rectangle { color: theme.colors.background; border.color: theme.colors.border }
    header: Rectangle {
        color: theme.colors.surface
        implicitHeight: 32
        ThemedLabel { anchors.fill: parent; anchors.leftMargin: 8; verticalAlignment: Text.AlignVCenter; text: "[ seleccionar páginas ]"; color: theme.colors.accent; theme: dialog.theme }
    }
    contentItem: RowLayout {
        spacing: 6
        ThemedLabel { theme: dialog.theme; text: "desde" }
        ThemedField { id: rangeFirst; theme: dialog.theme; Layout.fillWidth: true; text: "1"; validator: IntValidator { bottom: 1; top: dialog.page.pageCount } }
        ThemedLabel { theme: dialog.theme; text: "hasta" }
        ThemedField { id: rangeLast; theme: dialog.theme; Layout.fillWidth: true; text: dialog.page.currentPage; validator: IntValidator { bottom: 1; top: dialog.page.pageCount } }
    }
    footer: Rectangle {
        color: theme.colors.background
        implicitHeight: 34
        RowLayout {
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            spacing: 2
            ThemedCommand { theme: dialog.theme; text: "cancelar"; onClicked: dialog.reject() }
            ThemedCommand { theme: dialog.theme; text: "[ ok ]"; onClicked: dialog.accept() }
        }
    }
    onAccepted: page.selectPageRange(Number(rangeFirst.text), Number(rangeLast.text))
}

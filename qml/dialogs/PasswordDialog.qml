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
    title: "[ documento protegido ]"
    font.family: "monospace"
    modal: true
    closePolicy: Popup.NoAutoClose
    width: Math.min(420, canvasItem.width - 32)
    x: (canvasItem.width - width) / 2
    y: (canvasItem.height - height) / 2
    background: Rectangle { color: theme.colors.background; border.color: theme.colors.border }
    header: Rectangle {
        color: theme.colors.surface
        implicitHeight: 32
        ThemedLabel { anchors.fill: parent; anchors.leftMargin: 8; verticalAlignment: Text.AlignVCenter; text: "[ documento protegido ]"; color: theme.colors.accent; theme: dialog.theme }
    }
    contentItem: ThemedField {
        id: password
        theme: dialog.theme
        echoMode: TextInput.Password
        maximumLength: 1024
        placeholderText: "contraseña…"
        onAccepted: dialog.accept()
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
    onOpened: password.forceActiveFocus()
    onAccepted: { page.unlock(password.text); password.clear() }
    onRejected: password.clear()
}

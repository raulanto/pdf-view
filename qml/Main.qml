import qs.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import PdfView 1.0

FloatingWindow {
    id: window
    readonly property alias filePicker: picker
    readonly property alias theme: theme
    Theme { id: theme }
    readonly property alias document: page
    readonly property alias captureItem: canvas
    onClosed: Qt.quit()
    title: "PDF View"
    visible: true
    implicitWidth: 1040
    implicitHeight: 800
    minimumSize: Qt.size(560, 420)
    color: theme.colors.background

    FilePicker {
        id: picker
        parent: canvas
        colors: theme.colors
        onSelected: file => page.open(file)
    }
    Shortcut { sequence: "Ctrl+O"; onActivated: picker.open() }
    Rectangle {
        id: canvas
        anchors.fill: parent
        color: theme.colors.background
        ColumnLayout {
            id: layout
            anchors.fill: parent
            spacing: 0
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 64
                color: theme.colors.surface
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    Text { text: "PDF VIEW"; color: theme.colors.foreground; font.bold: true; font.pixelSize: 17 }
                    Item { Layout.fillWidth: true }
                    Text { text: page.hasPage ? "Página 1 de " + page.pageCount : "Prototipo · Fase 2"; color: theme.colors.foreground }
                    Button {
                        id: openButton
                        text: "Abrir PDF"
                        onClicked: picker.open()
                        padding: 12
                        contentItem: Text {
                            text: openButton.text
                            color: theme.colors.onAccent
                            font: openButton.font
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 6
                            color: openButton.down ? Qt.darker(theme.colors.accent, 1.15) : theme.colors.accent
                            border.width: openButton.visualFocus ? 3 : (openButton.hovered ? 2 : 0)
                            border.color: theme.colors.foreground
                        }
                    }
                }
            }
            Rectangle {
                color: theme.colors.background
                Layout.fillWidth: true
                Layout.fillHeight: true
                PdfPage { id: page; anchors.fill: parent; anchors.margins: 24 }
                Column {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 64, 440)
                    spacing: 14
                    visible: !page.hasPage
                    Text {
                        width: parent.width
                        text: page.busy ? "Preparando la primera página…" : (page.error ? "No se pudo abrir el documento" : "Tu documento, sin distracciones")
                        color: theme.colors.foreground; font.pixelSize: 22
                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        text: page.error || (page.busy ? "Procesando en un entorno aislado" : "Abre un PDF con el botón superior o Ctrl+O")
                        color: page.error ? theme.colors.error : theme.colors.foreground
                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.margins: 12
                text: "Primera página · Solo lectura · Motor aislado"
                color: theme.colors.foreground; font.pixelSize: 12
            }
        }
    }
    Component.onCompleted: {
        const file = Quickshell.env("PDF_VIEW_DOCUMENT")
        if (file) page.open(file)
    }
}

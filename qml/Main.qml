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
    readonly property alias document: page
    readonly property alias captureItem: canvas
    property string documentPath: ""
    readonly property string documentName: documentPath.split("/").pop() || "sin documento"
    Theme { id: theme }
    onClosed: Qt.quit()
    title: documentPath ? documentName + " — pdf-view" : "pdf-view"
    visible: true
    implicitWidth: 1120
    implicitHeight: 780
    minimumSize: Qt.size(560, 420)
    color: theme.colors.background

    function openDocument(file) {
        documentPath = decodeURIComponent(file.toString().replace(/^file:\/\//, ""))
        page.open(file)
    }
    component Label: Text {
        color: theme.colors.foreground
        font.family: "monospace"
        font.pixelSize: 12
        elide: Text.ElideRight
    }
    component Command: Button {
        font.family: "monospace"
        font.pixelSize: 12
        padding: 7
        contentItem: Text { text: parent.text; font: parent.font; color: theme.colors.accent }
        background: Rectangle {
            color: parent.down || parent.hovered ? theme.colors.selection : "transparent"
            border.width: parent.visualFocus ? 1 : 0
            border.color: theme.colors.accent
        }
    }
    FilePicker {
        id: picker
        parent: canvas
        colors: theme.colors
        onSelected: file => window.openDocument(file)
    }
    Shortcut { sequence: "Ctrl+O"; onActivated: picker.open() }
    Rectangle {
        id: canvas
        anchors.fill: parent
        color: theme.colors.background
        border.color: theme.colors.border
        border.width: 1
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 35
                color: theme.colors.surface
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 14
                    Label { text: "▸ pdf-view"; color: theme.colors.accent; font.bold: true }
                    Label { Layout.fillWidth: true; text: window.documentPath || "~/"; opacity: 0.8; elide: Text.ElideMiddle }
                    Command { text: "[Ctrl+O] abrir"; onClicked: picker.open() }
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.colors.border }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                Rectangle {
                    Layout.preferredWidth: window.width < 720 ? 148 : 210
                    Layout.fillHeight: true
                    color: theme.colors.background
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12
                        Label { text: "DOCUMENTO"; opacity: 0.6; font.pixelSize: 10; font.letterSpacing: 1.5 }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 30
                            color: theme.colors.selection
                            Label { anchors.fill: parent; anchors.leftMargin: 7; verticalAlignment: Text.AlignVCenter; text: "› " + window.documentName }
                        }
                        Label { text: "PDF / solo lectura"; opacity: 0.65 }
                        Label { text: page.hasPage ? page.pageCount + (page.pageCount === 1 ? " página" : " páginas") : "—"; opacity: 0.65 }
                        Item { Layout.fillHeight: true }
                        Label { text: "ATAJOS"; opacity: 0.6; font.pixelSize: 10; font.letterSpacing: 1.5 }
                        Command { text: "^O  abrir archivo"; onClicked: picker.open() }
                    }
                }
                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: theme.colors.border }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 28
                        color: theme.colors.background
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            Label { text: "VISTA"; opacity: 0.6; font.pixelSize: 10; font.letterSpacing: 1.5 }
                            Item { Layout.fillWidth: true }
                            Label { text: page.hasPage ? "1 / " + page.pageCount : "— / —"; color: theme.colors.accent }
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        PdfPage { id: page; anchors.fill: parent; anchors.margins: 16 }
                        Column {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 32, 420)
                            spacing: 12
                            visible: !page.hasPage
                            Label { text: page.busy ? "[ … ] cargando" : (page.error ? "[ ! ] error de apertura" : "[ pdf-view ]"); color: page.error ? theme.colors.error : theme.colors.accent }
                            Label {
                                width: parent.width
                                text: page.error || (page.busy ? "Preparando la primera página…" : "Abre un documento para comenzar.\nCtrl+O  ·  seleccionar PDF")
                                wrapMode: Text.WordWrap
                                elide: Text.ElideNone
                                opacity: 0.8
                            }
                        }
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.colors.border }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 25
                color: theme.colors.surface
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    Label { text: page.busy ? "LEYENDO" : (page.error ? "ERROR" : "NORMAL"); color: page.error ? theme.colors.error : theme.colors.accent; font.pixelSize: 10; font.bold: true }
                    Label { Layout.fillWidth: true; text: page.hasPage ? window.documentName : "ningún documento abierto"; font.pixelSize: 11 }
                    Label { text: "primera página · solo lectura"; font.pixelSize: 10; opacity: 0.65 }
                }
            }
        }
    }
    Component.onCompleted: {
        const file = Quickshell.env("PDF_VIEW_DOCUMENT")
        if (file) openDocument(file)
    }
}

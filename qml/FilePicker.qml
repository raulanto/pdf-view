import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell

Dialog {
    id: picker
    required property var colors
    signal selected(url file)
    title: "Abrir PDF"
    modal: true
    width: Math.min(parent.width - 32, 720)
    height: Math.min(parent.height - 32, 540)
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    standardButtons: Dialog.Cancel
    palette.window: colors.background
    palette.windowText: colors.foreground
    palette.base: colors.background
    palette.text: colors.foreground
    palette.button: colors.surface
    palette.buttonText: colors.foreground
    palette.highlight: colors.selection
    palette.highlightedText: colors.foreground
    background: Rectangle { color: picker.colors.background; radius: 8; border.color: picker.colors.border }
    FolderListModel {
        id: files
        folder: "file://" + Quickshell.env("HOME").split("/").map(encodeURIComponent).join("/")
        nameFilters: ["*.pdf", "*.PDF"]
        showDirs: true
        showDirsFirst: true
        showDotAndDotDot: false
    }
    contentItem: ColumnLayout {
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Button { text: "↑"; Accessible.name: "Carpeta superior"; onClicked: files.folder = files.parentFolder }
            Text { Layout.fillWidth: true; text: decodeURIComponent(files.folder.toString().replace(/^file:\/\//, "")); elide: Text.ElideMiddle; color: picker.colors.foreground }
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: files
            ScrollBar.vertical: ScrollBar {}
            delegate: ItemDelegate {
                required property string fileName
                required property url fileUrl
                required property bool fileIsDir
                width: list.width
                text: (fileIsDir ? "▸  " : "    ") + fileName
                onClicked: {
                    if (fileIsDir) files.folder = fileUrl
                    else { picker.selected(fileUrl); picker.close() }
                }
            }
            Text { anchors.centerIn: parent; visible: files.count === 0; text: "No hay PDF en esta carpeta"; color: picker.colors.foreground }
        }
    }
}

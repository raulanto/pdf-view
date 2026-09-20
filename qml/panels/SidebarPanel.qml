import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    required property var theme
    required property var window
    required property var page
    required property var picker
    required property var rangeDialog
    required property var searchDelay

    readonly property alias ocrLanguageField: ocrLanguage

    Layout.preferredWidth: window.width < 720 ? 148 : 210
    visible: !window.focusMode
    Layout.fillHeight: true
    color: theme.colors.background

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 6
        ThemedLabel { theme: root.theme; text: "DOCUMENTO"; opacity: 0.6; font.pixelSize: 10; font.letterSpacing: 1.5 }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 30
            color: root.theme.colors.selection
            ThemedLabel { theme: root.theme; anchors.fill: parent; anchors.leftMargin: 7; verticalAlignment: Text.AlignVCenter; text: "› " + root.window.documentName }
        }
        ThemedLabel { theme: root.theme; text: "PDF / lectura y notas"; opacity: 0.65 }
        ThemedLabel { theme: root.theme; text: root.page.pageCount > 0 ? root.page.pageCount + (root.page.pageCount === 1 ? " página" : " páginas") : "—"; opacity: 0.65 }
        RowLayout {
            Layout.fillWidth: true
            ThemedCommand { theme: root.theme; text: root.window.sidebarMode==="pages" ? "[páginas]" : "páginas"; onClicked: root.window.sidebarMode="pages" }
            ThemedCommand { theme: root.theme; text: root.window.sidebarMode==="index" ? "[índice]" : "índice"; onClicked: root.window.sidebarMode="index" }
        }
        ListView {
            id: sideList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cacheBuffer: 0
            model: root.window.sidebarMode==="pages" ? root.page.pageCount : root.page.outline.length
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                id: entry
                required property int index
                readonly property bool isThumbnail: root.window.sidebarMode==="pages"
                readonly property bool isCurrent: isThumbnail && root.page.currentPage===index+1
                readonly property var chapter: !isThumbnail ? root.page.outline[index] : null
                width: sideList.width
                height: isThumbnail ? 172 : 38
                color: "transparent"
                border.width: activeFocus ? 1 : 0
                border.color: root.theme.colors.accent
                activeFocusOnTab: true
                function activate() { if (isThumbnail) root.window.changePage(index+1); else if (chapter && chapter.page) root.window.changePage(chapter.page) }
                Keys.onReturnPressed: activate()
                Keys.onSpacePressed: activate()
                Accessible.role: Accessible.Button
                Accessible.name: isThumbnail ? "Página " + (index+1) : (chapter ? chapter.title : "")
                Rectangle {
                    id: thumbBox
                    visible: entry.isThumbnail
                    anchors.top: parent.top; anchors.topMargin: 4
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 20
                    height: 138
                    color: root.theme.colors.surface
                    border.color: entry.isCurrent ? root.theme.colors.accent : (entryMouse.containsMouse ? root.theme.colors.border : "transparent")
                    border.width: entry.isCurrent ? 2 : 1
                    Image {
                        anchors.fill: parent
                        anchors.margins: 3
                        fillMode: Image.PreserveAspectFit
                        source: entry.isThumbnail ? (root.page.thumbnails[String(entry.index+1)] || "") : ""
                        onSourceChanged: if (entry.isThumbnail && source.toString()==="") Qt.callLater(() => root.page.requestThumbnail(entry.index+1))
                    }
                }
                ThemedLabel {
                    theme: root.theme
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: entry.isThumbnail ? thumbBox.bottom : undefined
                    anchors.topMargin: entry.isThumbnail ? 4 : 0
                    anchors.bottom: !entry.isThumbnail ? parent.bottom : undefined
                    anchors.bottomMargin: !entry.isThumbnail ? 6 : 0
                    anchors.leftMargin: entry.isThumbnail ? 0 : 6+Math.min(entry.chapter ? entry.chapter.depth : 0,4)*10
                    horizontalAlignment: entry.isThumbnail ? Text.AlignHCenter : Text.AlignLeft
                    text: entry.isThumbnail ? String(entry.index+1) : (entry.chapter ? entry.chapter.title : "")
                    color: entry.isCurrent ? root.theme.colors.accent : root.theme.colors.foreground
                    font.bold: entry.isCurrent
                    opacity: !entry.isThumbnail && entry.chapter && !entry.chapter.page ? 0.55 : 1
                }
                MouseArea {
                    id: entryMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { parent.forceActiveFocus(); entry.activate() }
                }
                Component.onCompleted: if (isThumbnail) root.page.requestThumbnail(index+1)
                onIsThumbnailChanged: if (isThumbnail) root.page.requestThumbnail(index+1)
            }
            ThemedLabel { theme: root.theme; anchors.centerIn: parent; visible: root.window.sidebarMode==="index" && root.page.outline.length===0; text: "Sin índice"; opacity: 0.6 }
        }
        RowLayout {
            Layout.fillWidth: true
            ThemedCommand {
                theme: root.theme
                text: root.page.ocrEnabled ? "[x] OCR" : "[ ] OCR"
                onClicked: {
                    root.page.ocrEnabled = !root.page.ocrEnabled
                    if (root.window.searchField.text.length) root.searchDelay.restart()
                }
            }
            ThemedField {
                id: ocrLanguage
                theme: root.theme
                Layout.fillWidth: true
                text: root.page.ocrLanguage
                maximumLength: 32
                placeholderText: "eng"
                onAccepted: { root.page.ocrLanguage = text; root.page.forceActiveFocus() }
                Accessible.name: "Idioma OCR"
            }
        }
        ThemedCommand { theme: root.theme; text: "seleccionar rango"; enabled: root.page.canCopy; onClicked: root.rangeDialog.open() }
        RowLayout {
            ThemedCommand { theme: root.theme; text: "^O"; Accessible.name: "Abrir"; onClicked: root.picker.open() }
            ThemedCommand { theme: root.theme; text: "^F"; Accessible.name: "Buscar"; enabled: root.page.pageCount > 0; onClicked: root.window.showSearch() }
            ThemedCommand { theme: root.theme; text: "^C"; Accessible.name: "Copiar"; enabled: root.page.selectedText.length > 0; onClicked: root.page.copySelection() }
        }
    }
}

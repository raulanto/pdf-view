import qs.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "components"
import "dialogs"
import "panels"

FloatingWindow {
    id: window
    readonly property alias selectionActions: selectionToolbar
    readonly property alias annotationDialog: notesDialog
    readonly property alias filePicker: picker
    readonly property alias theme: theme
    readonly property alias document: page
    readonly property alias captureItem: canvas
    property string documentPath: ""
    readonly property alias viewport: viewport
    readonly property alias searchField: searchBar.searchField
    property string openingError: ""
    property bool searchVisible: false
    property bool focusMode: false
    property string sidebarMode: "pages"
    readonly property bool commandsEnabled: !picker.visible && !passwordDialog.visible && !rangeDialog.visible && !notesDialog.visible && !page.saving && !sidebarPanel.ocrLanguageField.activeFocus && !searchBar.searchField.activeFocus && !toolbarPanel.pageInputField.activeFocus
    readonly property string documentName: documentPath.split("/").pop() || "sin documento"
    Theme { id: theme }
    onClosed: { if (page.saving) visible=true; else Qt.quit() }
    title: documentPath ? documentName + " — pdf-view" : "pdf-view"
    visible: true
    implicitWidth: 1120
    implicitHeight: 780
    minimumSize: Qt.size(560, 420)
    color: theme.colors.background

    function openDocument(file) {
        selectionToolbar.close()
        if (page.saving) { openingError="Espera a que termine el guardado."; return }
        wheelScroll.stop()
        openingError = ""
        searchVisible = false
        searchBar.searchTimer.stop()
        searchBar.searchField.text = ""
        viewport.fitMode = "page"
        viewport.contentX = 0; viewport.contentY = 0
        documentPath = decodeURIComponent(file.toString().replace(/^file:\/\//, ""))
        page.open(file)
    }

    function showNotes() { selectionToolbar.close(); notesDialog.open() }
    function showSelectionTools() {
        if (page.anchor<0 || page.cursor<0 || page.saving) return
        const rect=page.mapRect(page.words[page.cursor].rect)
        selectionToolbar.showAt(page.mapToItem(canvas,rect.x+rect.width/2,rect.y+(page.currentPage-1)*(page.singleHeight+16)))
    }
    SelectionToolbar {
        id: selectionToolbar; parent: canvas
        theme: window.theme; selectedColor: page.annotationColor
        canAnnotate: page.canAnnotate && !page.saving
        onColorChosen: value => page.annotationColor=value
        onUnderlineRequested: if (page.saveAnnotation("underline","")) close()
        onRemoveUnderlineRequested: if (page.saveAnnotation("remove_underline","")) close()
        onNoteRequested: window.showNotes()
        onCopyRequested: { page.copySelection(); close() }
    }
    Shortcut { sequence: "Ctrl+Shift+A"; enabled: window.commandsEnabled && page.anchor>=0; onActivated: window.showSelectionTools() }

    NotesDialog { id: notesDialog; theme: window.theme; page: page; canvasItem: canvas }
    PasswordDialog {
        id: passwordDialog
        theme: window.theme
        page: page
        canvasItem: canvas
    }

    RangeDialog {
        id: rangeDialog
        theme: window.theme
        page: page
        canvasItem: canvas
    }

    Connections {
        target: page
        function onSelectionFinished(position) {
            if (!notesDialog.visible && !page.saving) selectionToolbar.showAt(page.mapToItem(canvas,position.x,position.y))
        }
        function onChanged() {
            if (!page.selectedText.length || page.saving) selectionToolbar.close()
            if (!page.busy) regionDelay.restart()
            if (page.passwordRequired && !page.busy && !passwordDialog.visible) passwordDialog.open()
        }
        function onRevealMatch(point) {
            viewport.contentX = Math.max(0, Math.min(viewport.contentWidth - viewport.width, page.x + point.x - viewport.width/2))
            viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height, page.y + point.y - viewport.height/2))
        }
    }

    function changePage(number) {
        if (page.saving) return
        wheelScroll.stop()
        if (number < 1 || (page.pageCount > 0 && number > page.pageCount)) return
        viewport.contentX = 0
        const singleHeight = page.pageHeight * 96/72 * viewport.effectiveScale
        viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height, (number - 1) * (singleHeight + 4)))
        page.goToPage(number)
    }

    function showSearch() { searchVisible = true; searchBar.searchField.forceActiveFocus(); searchBar.searchField.selectAll() }

    Shortcut { sequence: "Ctrl+F"; enabled: !notesDialog.visible && !page.saving && !picker.visible && !passwordDialog.visible; onActivated: window.showSearch() }
    Shortcut { sequence: "Ctrl+E"; enabled: !notesDialog.visible && !page.saving && !picker.visible && !passwordDialog.visible; onActivated: window.focusMode = !window.focusMode }
    Shortcut { sequence: "PgDown"; enabled: window.commandsEnabled; onActivated: window.changePage(page.currentPage + 1) }
    Shortcut { sequence: "PgUp"; enabled: window.commandsEnabled; onActivated: window.changePage(page.currentPage - 1) }
    Shortcut { sequence: "Ctrl+Home"; enabled: window.commandsEnabled; onActivated: window.changePage(1) }
    Shortcut { sequence: "Ctrl+End"; enabled: window.commandsEnabled; onActivated: window.changePage(page.pageCount) }
    Shortcut { sequence: "Ctrl++"; enabled: window.commandsEnabled; onActivated: viewport.adjustZoom(1.25) }
    Shortcut { sequence: "Ctrl+-"; enabled: window.commandsEnabled; onActivated: viewport.adjustZoom(0.8) }
    Shortcut { sequence: "Ctrl+0"; enabled: window.commandsEnabled; onActivated: viewport.fitMode = "page" }
    Shortcut { sequence: "Ctrl+R"; enabled: window.commandsEnabled; onActivated: page.rotatePage(1) }
    Shortcut { sequence: "Ctrl+C"; enabled: window.commandsEnabled; onActivated: page.copySelection() }
    Shortcut { sequence: "Ctrl+A"; enabled: window.commandsEnabled; onActivated: page.selectAll() }
    Shortcut { sequence: "F3"; enabled: !notesDialog.visible && !page.saving && !picker.visible && !passwordDialog.visible; onActivated: page.nextMatch(1) }
    Shortcut { sequence: "Shift+F3"; enabled: !notesDialog.visible && !page.saving && !picker.visible && !passwordDialog.visible; onActivated: page.nextMatch(-1) }
    Shortcut { sequence: "Escape"; enabled: !notesDialog.visible && !page.saving && !picker.visible && !passwordDialog.visible; onActivated: { if (selectionToolbar.opened) { selectionToolbar.close() } else if (page.anchor >= 0) { page.clearSelection() } else if (window.focusMode) { window.focusMode = false } else if (window.searchVisible) { searchBar.searchTimer.stop(); window.searchVisible = false; page.search(""); page.forceActiveFocus() } } }

    FilePicker {
        id: picker
        parent: canvas
        colors: theme.colors
        onSelected: file => window.openDocument(file)
    }
    Shortcut { sequence: "Ctrl+O"; enabled: !notesDialog.visible && !page.saving; onActivated: picker.open() }

    Rectangle {
        id: canvas
        anchors.fill: parent
        color: theme.colors.background
        border.color: theme.colors.border
        border.width: 1

        DropArea {
            anchors.fill: parent
            onDropped: drop => {
                if (drop.hasUrls && drop.urls.length === 1 && drop.urls[0].toString().startsWith("file:")) {
                    window.openDocument(drop.urls[0]); drop.acceptProposedAction()
                } else window.openingError = "Arrastra un único archivo PDF local."
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 0
            spacing: 0

            HeaderBar {
                theme: window.theme
                window: window
                picker: picker
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; visible: !window.focusMode; color: theme.colors.border }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                SidebarPanel {
                    id: sidebarPanel
                    theme: window.theme
                    window: window
                    page: page
                    picker: picker
                    rangeDialog: rangeDialog
                    searchDelay: searchBar.searchTimer
                }

                Rectangle { Layout.fillHeight: true; implicitWidth: 1; visible: !window.focusMode; color: theme.colors.border }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    ToolbarPanel {
                        id: toolbarPanel
                        theme: window.theme
                        window: window
                        page: page
                        viewport: viewport
                    }

                    SearchBarPanel {
                        id: searchBar
                        theme: window.theme
                        window: window
                        page: page
                    }

                    ThemedLabel {
                        theme: window.theme
                        Layout.fillWidth: true; Layout.margins: 4
                        visible: text.length > 0
                        text: window.openingError || page.auxiliaryError || page.searchError || (page.hasPage ? page.error : "")
                        color: theme.colors.error
                        wrapMode: Text.WordWrap
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Flickable {
                            id: viewport
                            anchors.fill: parent
                            clip: true
                            property string fitMode: "page"
                            property real zoom: 1.0
                            readonly property real singleHeight: page.pageHeight * 96/72 * effectiveScale
                            readonly property real singleWidth: page.pageWidth * 96/72 * effectiveScale
                            readonly property real totalDocHeight: page.pageCount > 0 ? page.pageCount * singleHeight + Math.max(0, page.pageCount - 1) * 4 : singleHeight
                            readonly property real effectiveScale: fitMode === "width" ? Math.max(0.05, width/(page.pageWidth*96/72)) :
                                (fitMode === "page" ? Math.max(0.05, Math.min(width/(page.pageWidth*96/72), height/(page.pageHeight*96/72))) : zoom)
                            function scrollBy(delta) {
                                const destination=Math.max(0,Math.min(contentHeight-height,(wheelScroll.running ? wheelScroll.to : contentY)+delta))
                                wheelScroll.stop(); cancelFlick()
                                wheelScroll.from=contentY; wheelScroll.to=destination; wheelScroll.start()
                            }
                            NumberAnimation { id: wheelScroll; target: viewport; property: "contentY"; duration: 140; easing.type: Easing.OutCubic }
                            onDraggingChanged: if (dragging) wheelScroll.stop()
                            function adjustZoom(factor) { selectionToolbar.close(); zoom = Math.max(0.25, Math.min(4, effectiveScale*factor)); fitMode = "manual" }
                            contentWidth: Math.max(width, singleWidth)
                            contentHeight: Math.max(height, totalDocHeight)
                            onContentXChanged: { selectionToolbar.close(); regionDelay.restart() }
                            onContentYChanged: {
                                selectionToolbar.close()
                                regionDelay.restart()
                                if (page.pageCount > 1) {
                                    const pageIndex = Math.max(1, Math.min(page.pageCount, Math.floor((contentY + height/3) / (singleHeight + 4)) + 1))
                                    if (pageIndex !== page.currentPage) {
                                        page.goToPage(pageIndex)
                                    }
                                }
                            }
                            onWidthChanged: regionDelay.restart()
                            onHeightChanged: regionDelay.restart()
                            boundsBehavior: Flickable.StopAtBounds
                            acceptedButtons: Qt.MiddleButton
                            ScrollBar.vertical: ScrollBar { palette.mid: theme.colors.border; palette.dark: theme.colors.accent }
                            ScrollBar.horizontal: ScrollBar { palette.mid: theme.colors.border; palette.dark: theme.colors.accent }
                            WheelHandler {
                                acceptedModifiers: Qt.ControlModifier
                                onWheel: event => { viewport.adjustZoom(event.angleDelta.y > 0 ? 1.1 : 1/1.1); event.accepted = true }
                            }
                            PdfPage {
                                id: page
                                width: viewport.singleWidth
                                height: viewport.totalDocHeight
                                singleHeight: viewport.singleHeight
                                visibleTop: Math.max(0,viewport.contentY-y)
                                visibleHeight: viewport.height
                                x: (viewport.contentWidth-width)/2
                                y: 0
                                renderScale: viewport.effectiveScale*window.devicePixelRatio
                                highlightColor: theme.colors.accent
                            }
                            Timer {
                                id: regionDelay
                                interval: 180
                                onTriggered: if (!page.busy) page.requestRegion(Qt.rect(viewport.contentX-page.x,viewport.contentY-page.y,viewport.width,viewport.height))
                            }
                        }
                        Column {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 32, 420)
                            spacing: 12
                            visible: !page.hasPage && !page.busy
                            ThemedLabel { theme: window.theme; text: page.busy ? "[ … ] cargando" : (page.error ? "[ ! ] error de apertura" : "[ pdf-view ]"); color: page.error ? theme.colors.error : theme.colors.accent }
                            ThemedLabel {
                                theme: window.theme
                                width: parent.width
                                text: page.error || (page.busy ? "Preparando la página…" : "Abre o arrastra un documento.\nCtrl+O  ·  seleccionar PDF")
                                wrapMode: Text.WordWrap
                                elide: Text.ElideNone
                                opacity: 0.8
                            }
                            ThemedCommand { theme: window.theme; visible: page.passwordRequired; text: "Introducir contraseña"; onClicked: passwordDialog.open() }
                        }
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; visible: !window.focusMode; color: theme.colors.border }
            StatusBarPanel {
                theme: window.theme
                window: window
                page: page
            }
        }
    }
    Component.onCompleted: {
        const file = Quickshell.env("PDF_VIEW_DOCUMENT")
        if (file) openDocument(file)
    }
}

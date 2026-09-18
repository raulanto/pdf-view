import qs.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

FloatingWindow {
    id: window
    readonly property alias filePicker: picker
    readonly property alias theme: theme
    readonly property alias document: page
    readonly property alias captureItem: canvas
    property string documentPath: ""
    readonly property alias viewport: viewport
    readonly property alias searchField: query
    property string openingError: ""
    property bool searchVisible: false
    property string sidebarMode: "pages"
    readonly property bool commandsEnabled: !picker.visible && !passwordDialog.visible && !rangeDialog.visible && !ocrLanguage.activeFocus && !query.activeFocus && !pageInput.activeFocus
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
        openingError = ""
        searchVisible = false
        searchDelay.stop()
        query.text = ""
        viewport.fitMode = "page"
        viewport.contentX = 0; viewport.contentY = 0
        documentPath = decodeURIComponent(file.toString().replace(/^file:\/\//, ""))
        page.open(file)
    }
    component Label: Text {
        textFormat: Text.PlainText
        color: theme.colors.foreground
        font.family: "monospace"
        font.pixelSize: 12
        elide: Text.ElideRight
    }
    component Command: Button {
        font.family: "monospace"
        font.pixelSize: 12
        padding: 7
        contentItem: Text { text: parent.text; font: parent.font; color: parent.enabled ? theme.colors.accent : theme.colors.border }
        background: Rectangle {
            color: parent.down || parent.hovered ? theme.colors.selection : "transparent"
            border.width: parent.visualFocus ? 1 : 0
            border.color: theme.colors.accent
        }
    }
    component Field: TextField {
        font.family: "monospace"
        font.pixelSize: 12
        color: theme.colors.foreground
        selectionColor: theme.colors.accent
        selectedTextColor: theme.colors.onAccent
        placeholderTextColor: theme.colors.foreground
        padding: 6
        background: Rectangle {
            color: theme.colors.background
            border.color: parent.activeFocus ? theme.colors.accent : theme.colors.border
        }
    }
    Dialog {
        id: passwordDialog
        parent: canvas
        title: "[ documento protegido ]"
        font.family: "monospace"
        modal: true
        width: Math.min(420, canvas.width - 32)
        x: (canvas.width-width)/2; y: (canvas.height-height)/2
        standardButtons: Dialog.Ok | Dialog.Cancel
        palette.windowText: theme.colors.foreground
        palette.buttonText: theme.colors.foreground
        palette.button: theme.colors.surface
        background: Rectangle { color: theme.colors.background; border.color: theme.colors.border }
        contentItem: Field { id: password; echoMode: TextInput.Password; maximumLength: 1024; placeholderText: "Contraseña"; onAccepted: passwordDialog.accept() }
        onOpened: password.forceActiveFocus()
        onAccepted: { page.unlock(password.text); password.clear() }
        onRejected: password.clear()
    }
    Dialog {
        id: rangeDialog
        parent: canvas
        title: "[ seleccionar páginas ]"
        font.family: "monospace"
        modal: true
        width: Math.min(380, canvas.width-32)
        x: (canvas.width-width)/2; y: (canvas.height-height)/2
        standardButtons: Dialog.Ok | Dialog.Cancel
        palette.windowText: theme.colors.foreground
        palette.buttonText: theme.colors.foreground
        palette.button: theme.colors.surface
        background: Rectangle { color: theme.colors.background; border.color: theme.colors.border }
        contentItem: RowLayout {
            Label { text: "Desde" }
            Field { id: rangeFirst; Layout.fillWidth: true; text: "1"; validator: IntValidator { bottom: 1; top: page.pageCount } }
            Label { text: "hasta" }
            Field { id: rangeLast; Layout.fillWidth: true; text: page.currentPage; validator: IntValidator { bottom: 1; top: page.pageCount } }
        }
        onAccepted: page.selectPageRange(Number(rangeFirst.text),Number(rangeLast.text))
    }
    Connections {
        target: page
        function onChanged() {
            if (!page.busy) regionDelay.restart()
            if (page.passwordRequired && !page.busy && !passwordDialog.visible) passwordDialog.open()
        }
        function onRevealMatch(point) {
            viewport.contentX = Math.max(0, Math.min(viewport.contentWidth - viewport.width, page.x + point.x - viewport.width/2))
            viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height, page.y + point.y - viewport.height/2))
        }
    }
    function changePage(number) {
        viewport.contentX = 0; viewport.contentY = 0
        page.goToPage(number)
    }
    function showSearch() { searchVisible = true; query.forceActiveFocus(); query.selectAll() }
    Shortcut { sequence: "Ctrl+F"; enabled: !picker.visible && !passwordDialog.visible; onActivated: window.showSearch() }
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
    Shortcut { sequence: "F3"; enabled: !picker.visible && !passwordDialog.visible; onActivated: page.nextMatch(1) }
    Shortcut { sequence: "Shift+F3"; enabled: !picker.visible && !passwordDialog.visible; onActivated: page.nextMatch(-1) }
    Shortcut { sequence: "Escape"; enabled: window.searchVisible && !picker.visible && !passwordDialog.visible; onActivated: { searchDelay.stop(); window.searchVisible = false; page.search(""); page.forceActiveFocus() } }
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
                        Label { text: page.pageCount > 0 ? page.pageCount + (page.pageCount === 1 ? " página" : " páginas") : "—"; opacity: 0.65 }
                        RowLayout {
                            Layout.fillWidth: true
                            Command { text: window.sidebarMode==="pages" ? "[páginas]" : "páginas"; onClicked: window.sidebarMode="pages" }
                            Command { text: window.sidebarMode==="index" ? "[índice]" : "índice"; onClicked: window.sidebarMode="index" }
                        }
                        ListView {
                            id: sideList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            cacheBuffer: 0
                            model: window.sidebarMode==="pages" ? page.pageCount : page.outline.length
                            ScrollBar.vertical: ScrollBar {}
                            delegate: Rectangle {
                                id: entry
                                required property int index
                                readonly property bool isThumbnail: window.sidebarMode==="pages"
                                readonly property var chapter: !isThumbnail ? page.outline[index] : null
                                width: sideList.width
                                height: isThumbnail ? 162 : 38
                                color: (isThumbnail && page.currentPage===index+1) ? theme.colors.selection : "transparent"
                                border.width: activeFocus ? 1 : 0
                                border.color: theme.colors.accent
                                activeFocusOnTab: true
                                function activate() { if (isThumbnail) window.changePage(index+1); else if (chapter && chapter.page) window.changePage(chapter.page) }
                                Keys.onReturnPressed: activate()
                                Keys.onSpacePressed: activate()
                                Accessible.role: Accessible.Button
                                Accessible.name: isThumbnail ? "Página " + (index+1) : (chapter ? chapter.title : "")
                                Image {
                                    anchors.top: parent.top; anchors.topMargin: 6
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width-16; height: 130
                                    visible: entry.isThumbnail
                                    fillMode: Image.PreserveAspectFit
                                    source: entry.isThumbnail ? (page.thumbnails[String(entry.index+1)] || "") : ""
                                    onSourceChanged: if (entry.isThumbnail && source.toString()==="") Qt.callLater(() => page.requestThumbnail(entry.index+1))
                                }
                                Label {
                                    anchors.left: parent.left; anchors.right: parent.right
                                    anchors.leftMargin: entry.isThumbnail ? 8 : 6+Math.min(entry.chapter ? entry.chapter.depth : 0,4)*10
                                    anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                                    text: entry.isThumbnail ? String(entry.index+1) : (entry.chapter ? entry.chapter.title : "")
                                    opacity: !entry.isThumbnail && entry.chapter && !entry.chapter.page ? 0.55 : 1
                                }
                                MouseArea { anchors.fill: parent; onClicked: { parent.forceActiveFocus(); entry.activate() } }
                                Component.onCompleted: if (isThumbnail) page.requestThumbnail(index+1)
                                onIsThumbnailChanged: if (isThumbnail) page.requestThumbnail(index+1)
                            }
                            Label { anchors.centerIn: parent; visible: window.sidebarMode==="index" && page.outline.length===0; text: "Sin índice"; opacity: 0.6 }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Command { text: page.ocrEnabled ? "[x] OCR" : "[ ] OCR"; onClicked: { page.ocrEnabled=!page.ocrEnabled; if (query.text.length) searchDelay.restart() } }
                            Field { id: ocrLanguage; Layout.fillWidth: true; text: page.ocrLanguage; maximumLength: 32; placeholderText: "eng"; onAccepted: { page.ocrLanguage=text; page.forceActiveFocus() } Accessible.name: "Idioma OCR" }
                        }
                        Command { text: "seleccionar rango"; enabled: page.canCopy; onClicked: rangeDialog.open() }
                        RowLayout {
                            Command { text: "^O"; Accessible.name: "Abrir"; onClicked: picker.open() }
                            Command { text: "^F"; Accessible.name: "Buscar"; enabled: page.pageCount > 0; onClicked: window.showSearch() }
                            Command { text: "^C"; Accessible.name: "Copiar"; enabled: page.selectedText.length > 0; onClicked: page.copySelection() }
                        }
                    }
                }
                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: theme.colors.border }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0
                    Flow {
                        Layout.fillWidth: true
                        Layout.margins: 5
                        spacing: 3
                        Command { text: "[‹]"; Accessible.name: "Página anterior"; enabled: page.currentPage > 1; onClicked: window.changePage(page.currentPage-1) }
                        Field {
                            id: pageInput
                            width: 48
                            text: page.currentPage
                            validator: IntValidator { bottom: 1; top: Math.max(1, page.pageCount) }
                            onAccepted: { window.changePage(Number(text)); page.forceActiveFocus() }
                            Accessible.name: "Ir a página"
                        }
                        Label { text: "/ " + page.pageCount; height: 30; verticalAlignment: Text.AlignVCenter }
                        Command { text: "[›]"; Accessible.name: "Página siguiente"; enabled: page.currentPage < page.pageCount; onClicked: window.changePage(page.currentPage+1) }
                        Command { text: "[-]"; Accessible.name: "Reducir zoom"; onClicked: viewport.adjustZoom(0.8) }
                        Label { text: Math.round(viewport.effectiveScale*100) + "%"; height: 30; verticalAlignment: Text.AlignVCenter }
                        Command { text: "[+]"; Accessible.name: "Aumentar zoom"; onClicked: viewport.adjustZoom(1.25) }
                        Command { text: "ajustar"; onClicked: viewport.fitMode = "page" }
                        Command { text: "ancho"; onClicked: viewport.fitMode = "width" }
                        Command { text: "↻ " + page.rotation + "°"; enabled: page.pageCount > 0; onClicked: page.rotatePage(1) }
                    }
                    RowLayout {
                        visible: window.searchVisible
                        Layout.fillWidth: true
                        Layout.leftMargin: 8; Layout.rightMargin: 8
                        Field {
                            id: query
                            Layout.fillWidth: true
                            placeholderText: "Buscar en el documento…"
                            maximumLength: 256
                            onTextEdited: { page.search(""); searchDelay.restart() }
                            onAccepted: { searchDelay.stop(); page.search(text) }
                        }
                        Timer { id: searchDelay; interval: 350; onTriggered: page.search(query.text) }
                        Label { text: page.searching ? "…" : (page.matchCount ? (page.matchIndex+1)+"/"+page.matchCount+(page.searchTruncated?"+":"") : "0") }
                        Command { text: "↑"; enabled: page.matchCount > 0; onClicked: page.nextMatch(-1) }
                        Command { text: "↓"; enabled: page.matchCount > 0; onClicked: page.nextMatch(1) }
                        Command { text: "[x]"; onClicked: { searchDelay.stop(); window.searchVisible = false; page.search(""); page.forceActiveFocus() } }
                    }
                    Label {
                        Layout.fillWidth: true; Layout.margins: 8
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
                            readonly property real effectiveScale: fitMode === "width" ? Math.max(0.05, (width-32)/(page.pageWidth*96/72)) :
                                (fitMode === "page" ? Math.max(0.05, Math.min((width-32)/(page.pageWidth*96/72), (height-32)/(page.pageHeight*96/72))) : zoom)
                            function adjustZoom(factor) { zoom = Math.max(0.25, Math.min(4, effectiveScale*factor)); fitMode = "manual" }
                            contentWidth: Math.max(width, page.width + 32)
                            contentHeight: Math.max(height, page.height + 32)
                            onContentXChanged: regionDelay.restart()
                            onContentYChanged: regionDelay.restart()
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
                                width: pageWidth*96/72*viewport.effectiveScale
                                height: pageHeight*96/72*viewport.effectiveScale
                                x: (viewport.contentWidth-width)/2
                                y: (viewport.contentHeight-height)/2
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
                            visible: !page.hasPage
                            Label { text: page.busy ? "[ … ] cargando" : (page.error ? "[ ! ] error de apertura" : "[ pdf-view ]"); color: page.error ? theme.colors.error : theme.colors.accent }
                            Label {
                                width: parent.width
                                text: page.error || (page.busy ? "Preparando la página…" : "Abre o arrastra un documento.\nCtrl+O  ·  seleccionar PDF")
                                wrapMode: Text.WordWrap
                                elide: Text.ElideNone
                                opacity: 0.8
                            }
                            Command { visible: page.passwordRequired; text: "Introducir contraseña"; onClicked: passwordDialog.open() }
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
                    Label { text: page.selectedText.length > 0 ? "selección · Ctrl+C" : (page.auxiliaryBusy ? "procesando…" : (page.selectionStartPage > 0 ? "inicio p."+page.selectionStartPage+" · Shift+clic" : "solo lectura")); font.pixelSize: 10; opacity: 0.65 }
                }
            }
        }
    }
    Component.onCompleted: {
        const file = Quickshell.env("PDF_VIEW_DOCUMENT")
        if (file) openDocument(file)
    }
}

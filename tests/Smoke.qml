import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property var viewer
    property int stage: 0
    readonly property bool themeTest: Quickshell.env("PDF_VIEW_TEST_THEME") === "1"
    Process {
        id: changeTheme
        command: ["python3", "-c", "import pathlib,sys; pathlib.Path(sys.argv[1]).write_text(\"background='#ffffff'\\nforeground='#112233'\\naccent='#0055cc'\\nmode='light'\\n\")", Quickshell.env("PDF_VIEW_THEME_FILE")]
    }
    Component.onCompleted: {
        const component = Qt.createComponent("../qml/Main.qml")
        if (component.status !== Component.Ready) {
            console.error(component.errorString())
            Qt.quit()
            return
        }
        viewer = component.createObject(root)
        if (!viewer) Qt.quit()
    }
    Timer {
        interval: 500
        repeat: true
        running: true
        onTriggered: {
            if (!root.viewer || root.viewer.document.busy) return
            if (!root.viewer.document.hasPage) {
                console.error("SMOKE FAILED: " + root.viewer.document.error)
                Qt.quit()
                return
            }
            if (!root.themeTest) {
                const doc = root.viewer.document
                if (root.stage === 0) { root.stage=1; root.viewer.changePage(2); return }
                if (root.stage === 1) {
                    if (doc.currentPage !== 2) { console.error("Wrong page"); Qt.quit(); return }
                    root.stage=2
                    root.viewer.viewport.adjustZoom(1.25)
                    doc.rotatePage(1)
                    return
                }
                if (root.stage === 2) {
                    if (doc.rotation !== 90) { console.error("Wrong rotation"); Qt.quit(); return }
                    root.stage=3
                    root.viewer.showSearch()
                    root.viewer.searchField.text = "Quickshell"
                    doc.search("Quickshell")
                    return
                }
                if (root.stage === 3) {
                    if (doc.searching) return
                    if (doc.matchCount !== 1 || doc.currentPage !== 1) { console.error("Search failed"); Qt.quit(); return }
                    doc.selectAll()
                    if (doc.selectedText.indexOf("Quickshell") === -1) { console.error("Selection failed"); Qt.quit(); return }
                    doc.clearSelection()
                    root.viewer.viewport.zoom=2
                    root.viewer.viewport.fitMode="manual"
                    root.stage=4
                    return
                }
                if (root.stage===4) {
                    if (!doc.thumbnails["1"] || !doc.thumbnails["2"] || doc.regionRect.width===0 || doc.auxiliaryBusy) return
                    root.stage=5
                    doc.selectPageRange(1,2)
                    return
                }
                if (root.stage===5) {
                    if (doc.auxiliaryBusy) return
                    if (doc.selectedText.indexOf("Second page")===-1) { console.error("Page range failed"); Qt.quit(); return }
                    doc.clearSelection()
                    root.viewer.sidebarMode="index"
                    root.viewer.viewport.fitMode="page"
                    root.stage=6
                    return
                }
                if (root.stage===6) {
                    root.viewer.sidebarMode="pages"
                    root.stage=7
                    return
                }

            }
            if (root.themeTest && root.stage === 0) {
                if (root.viewer.theme.colors.background !== "#1a1b26") return
                root.stage = 1
                root.viewer.captureItem.grabToImage(function(result) {
                    result.saveToFile(Quickshell.env("PDF_VIEW_SCREENSHOT") + ".dark.png")
                    changeTheme.running = true
                })
                return
            }
            if (root.themeTest && root.stage === 1) {
                if (root.viewer.theme.colors.background !== "#ffffff" || root.viewer.color.toString() !== "#ffffff") return
                root.stage = 2
                root.viewer.filePicker.open()
                return
            }
            if (root.themeTest && root.stage !== 2) return
            stop()
            const item = root.themeTest ? root.viewer.filePicker.contentItem : root.viewer.captureItem
            item.grabToImage(function(result) {
                if (!result.saveToFile(Quickshell.env("PDF_VIEW_SCREENSHOT"))) {
                    Qt.quit()
                    return
                }
                console.log("SMOKE PASSED: navigation, zoom, rotation, search and text selection in Quickshell" + (root.themeTest ? "; live dark/light reload and themed picker" : ""))
                Qt.quit()
            })
        }
    }
    Timer { interval: 40000; running: true; onTriggered: Qt.quit() }
}

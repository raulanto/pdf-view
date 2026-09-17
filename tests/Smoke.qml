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
                console.log("SMOKE PASSED: first page rendered in Quickshell" + (root.themeTest ? "; live dark/light reload and themed picker" : ""))
                Qt.quit()
            })
        }
    }
    Timer { interval: 20000; running: true; onTriggered: Qt.quit() }
}

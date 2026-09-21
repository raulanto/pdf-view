import QtQuick
import QtQuick.Layouts
import "../components"

Flow {
    id: root
    required property var theme
    required property var window
    required property var page
    required property var viewport

    readonly property alias pageInputField: pageInput

    Layout.fillWidth: true
    Layout.margins: 2
    visible: !window.focusMode
    spacing: 2
    ThemedCommand { theme: root.theme; text: "[‹]"; Accessible.name: "Página anterior"; enabled: root.page.currentPage > 1; onClicked: root.window.changePage(root.page.currentPage-1) }
    ThemedField {
        id: pageInput
        theme: root.theme
        width: 48
        text: root.page.currentPage
        validator: IntValidator { bottom: 1; top: Math.max(1, root.page.pageCount) }
        onAccepted: { root.window.changePage(Number(text)); root.page.forceActiveFocus() }
        Accessible.name: "Ir a página"
    }
    ThemedLabel { theme: root.theme; text: "/ " + root.page.pageCount; height: 30; verticalAlignment: Text.AlignVCenter }
    ThemedCommand { theme: root.theme; text: "[›]"; Accessible.name: "Página siguiente"; enabled: root.page.currentPage < root.page.pageCount; onClicked: root.window.changePage(root.page.currentPage+1) }
    ThemedCommand { theme: root.theme; text: "[-]"; Accessible.name: "Reducir zoom"; onClicked: root.viewport.adjustZoom(0.8) }
    ThemedLabel { theme: root.theme; text: Math.round(root.viewport.effectiveScale*100) + "%"; height: 30; verticalAlignment: Text.AlignVCenter }
    ThemedCommand { theme: root.theme; text: "[+]"; Accessible.name: "Aumentar zoom"; onClicked: root.viewport.adjustZoom(1.25) }
    ThemedCommand { theme: root.theme; text: "ajustar"; onClicked: root.viewport.fitMode = "page" }
    ThemedCommand { theme: root.theme; text: "ancho"; onClicked: root.viewport.fitMode = "width" }
    ThemedCommand { theme: root.theme; text: "↻ " + root.page.rotation + "°"; enabled: root.page.pageCount > 0; onClicked: root.page.rotatePage(1) }
    ThemedCommand { theme: root.theme; text: "anotar ▾"; Accessible.name: "Opciones de anotación"; enabled: root.page.canAnnotate && root.page.anchor>=0 && !root.page.saving; onClicked: root.window.showSelectionTools() }
    ThemedCommand { theme: root.theme; text: "desmarcar"; Accessible.name: "Desmarcar selección"; visible: root.page.anchor>=0; enabled: !root.page.saving; onClicked: root.page.clearSelection() }
    ThemedCommand { theme: root.theme; text: "notas · " + root.page.annotations.filter(a=>a.kind==="note").length; enabled: root.page.hasPage && !root.page.saving; onClicked: root.window.showNotes() }
}

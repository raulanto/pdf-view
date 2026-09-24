import QtQuick
import QtQuick.Layouts
import "../components"

RowLayout {
    id: root
    required property var theme
    required property var window
    required property var page

    readonly property alias searchField: query
    readonly property alias searchTimer: searchDelay

    visible: window.searchVisible
    Layout.fillWidth: true
    Layout.leftMargin: 4; Layout.rightMargin: 4
    ThemedField {
        id: query
        theme: root.theme
        Layout.fillWidth: true
        placeholderText: root.window.i18n ? root.window.i18n.tr("search.placeholder") : "Buscar en el documento…"
        maximumLength: 256
        onTextEdited: { root.page.search(""); searchDelay.restart() }
        onAccepted: { searchDelay.stop(); root.page.search(text) }
    }
    Timer { id: searchDelay; interval: 350; onTriggered: root.page.search(query.text) }
    ThemedLabel { theme: root.theme; text: root.page.searching ? "…" : (root.page.matchCount ? (root.page.matchIndex+1)+"/"+root.page.matchCount+(root.page.searchTruncated?"+":"") : "0") }
    ThemedCommand { theme: root.theme; text: "↑"; enabled: root.page.matchCount > 0; onClicked: root.page.nextMatch(-1) }
    ThemedCommand { theme: root.theme; text: "↓"; enabled: root.page.matchCount > 0; onClicked: root.page.nextMatch(1) }
    ThemedCommand { theme: root.theme; text: "[x]"; onClicked: { searchDelay.stop(); root.window.searchVisible = false; root.page.search(""); root.page.forceActiveFocus() } }
}

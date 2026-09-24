import QtQuick
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    required property var theme
    required property var window
    required property var page

    Layout.fillWidth: true
    implicitHeight: window.focusMode ? 0 : Math.round(25 * theme.scale)
    visible: !window.focusMode
    color: theme.colors.surface
    Behavior on implicitHeight { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        ThemedLabel {
            theme: root.theme
            text: root.page.saving
                  ? (root.window.i18n ? root.window.i18n.tr("status.saving") : "GUARDANDO")
                  : (root.page.busy
                     ? (root.window.i18n ? root.window.i18n.tr("status.reading") : "LEYENDO")
                     : (root.page.error
                        ? (root.window.i18n ? root.window.i18n.tr("status.error") : "ERROR")
                        : (root.window.i18n ? root.window.i18n.tr("status.normal") : "NORMAL")))
            color: root.page.error ? root.theme.colors.error : root.theme.colors.accent; font.pixelSize: 10; font.bold: true
        }
        ThemedLabel { theme: root.theme; Layout.fillWidth: true; text: root.page.hasPage ? root.window.documentName : (root.window.i18n ? root.window.i18n.tr("status.noDocument") : "ningún documento abierto"); font.pixelSize: 11 }
        ThemedLabel {
            theme: root.theme
            text: root.page.saveStatus || (root.page.selectedText.length > 0
                  ? (root.window.i18n ? root.window.i18n.tr("status.selection", root.window.preferences.key("copy","Ctrl+C")) : ("selección · "+root.window.preferences.key("copy","Ctrl+C")))
                  : (root.page.auxiliaryBusy
                     ? (root.window.i18n ? root.window.i18n.tr("status.processing") : "procesando…")
                     : (root.page.selectionStartPage > 0
                        ? (root.window.i18n ? root.window.i18n.tr("status.selectionStart", root.page.selectionStartPage) : ("inicio p."+root.page.selectionStartPage+" · Shift+clic"))
                        : (root.window.i18n ? root.window.i18n.tr("status.idle") : "lectura y notas"))))
            font.pixelSize: 10; opacity: 0.65
        }
    }
}

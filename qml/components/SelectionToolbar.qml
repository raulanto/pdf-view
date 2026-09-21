import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: toolbar
    required property var theme
    property string selectedColor: "#e69600"
    property bool canAnnotate: false
    signal colorChosen(string value)
    signal underlineRequested()
    signal removeUnderlineRequested()
    signal noteRequested()
    signal copyRequested()
    padding: 10
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    width: Math.min(380,parent.width-16)
    background: Rectangle { color: toolbar.theme.colors.surface; border.color: toolbar.theme.colors.border }
    function showAt(point) {
        x=Math.max(8,Math.min(parent.width-width-8,point.x-width/2))
        y=Math.max(8,Math.min(parent.height-height-8,point.y-height-12>=8 ? point.y-height-12 : point.y+18))
        open()
    }
    contentItem: ColumnLayout {
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            ThemedLabel { theme: toolbar.theme; text: "[ selección ]"; Layout.fillWidth: true }
            ThemedCommand { theme: toolbar.theme; text: "×"; Accessible.name: "Cerrar acciones"; onClicked: toolbar.close() }
        }
        AnnotationColors {
            theme: toolbar.theme; selectedColor: toolbar.selectedColor
            enabled: toolbar.canAnnotate
            onColorChosen: value => toolbar.colorChosen(value)
        }
        RowLayout {
            spacing: 0
            ThemedCommand { objectName: "quickUnderline"; theme: toolbar.theme; text: "subrayar"; enabled: toolbar.canAnnotate; onClicked: toolbar.underlineRequested() }
            ThemedCommand { objectName: "quickRemoveUnderline"; theme: toolbar.theme; text: "desmarcar"; onClicked: toolbar.removeUnderlineRequested() }
            ThemedCommand { objectName: "quickNote"; theme: toolbar.theme; text: "+ nota"; enabled: toolbar.canAnnotate; onClicked: toolbar.noteRequested() }
            ThemedCommand { objectName: "quickCopy"; theme: toolbar.theme; text: "copiar"; onClicked: toolbar.copyRequested() }
        }
        ThemedLabel { theme: toolbar.theme; text: toolbar.canAnnotate ? "Se guarda en el PDF · Esc cierra" : "Selección de solo lectura"; font.pixelSize: 10; opacity: 0.7 }
    }
}

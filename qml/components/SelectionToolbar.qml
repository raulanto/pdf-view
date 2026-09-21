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
    padding: Math.round(4 * theme.scale)
    modal: false
    focus: false
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    width: implicitWidth
    background: Rectangle {
        color: toolbar.theme.colors.surface
        border.color: toolbar.theme.colors.border
    }
    function showAt(point) {
        x = Math.max(4, Math.min(parent.width - implicitWidth - 4, point.x - implicitWidth / 2))
        y = Math.max(4, Math.min(parent.height - implicitHeight - 4,
                point.y - implicitHeight - 8 >= 4 ? point.y - implicitHeight - 8 : point.y + 14))
        open()
    }

    // Botón de acción compacto estilo terminal
    component Cmd: AbstractButton {
        id: cmd
        required property var theme
        property bool dim: false
        font.family: "monospace"
        font.pixelSize: Math.round(11 * theme.scale)
        padding: Math.round(4 * theme.scale)
        leftPadding: Math.round(6 * theme.scale)
        rightPadding: leftPadding
        Accessible.name: text
        contentItem: Text {
            text: cmd.text
            font: cmd.font
            color: cmd.enabled
                   ? (cmd.dim ? cmd.theme.colors.foreground : cmd.theme.colors.accent)
                   : cmd.theme.colors.border
            opacity: cmd.dim ? 0.65 : 1.0
        }
        background: Rectangle {
            color: cmd.down || cmd.hovered ? cmd.theme.colors.selection : "transparent"
            border.width: cmd.visualFocus ? 1 : 0
            border.color: cmd.theme.colors.accent
        }
    }

    contentItem: RowLayout {
        spacing: 0

        // Paleta de color: puntos diminutos
        Repeater {
            model: [
                { name: "Ámbar",   value: "#e69600" },
                { name: "Rojo",    value: "#dc4c64" },
                { name: "Verde",   value: "#2a9968" },
                { name: "Azul",    value: "#397ed0" },
                { name: "Violeta", value: "#9561c9" },
            ]
            delegate: AbstractButton {
                required property var modelData
                implicitWidth:  Math.round(16 * toolbar.theme.scale)
                implicitHeight: Math.round(24 * toolbar.theme.scale)
                enabled: toolbar.canAnnotate
                Accessible.name: "Color " + modelData.name
                ToolTip.visible: hovered; ToolTip.text: modelData.name
                onClicked: toolbar.colorChosen(modelData.value)
                background: null
                contentItem: Rectangle {
                    anchors.centerIn: parent
                    width:  Math.round(8 * toolbar.theme.scale)
                    height: width
                    radius: width / 2
                    color: modelData.value
                    border.width: toolbar.selectedColor === modelData.value ? 1 : 0
                    border.color: toolbar.theme.colors.foreground
                    opacity: toolbar.canAnnotate ? 1.0 : 0.4
                }
            }
        }

        // Separador
        Rectangle {
            implicitWidth: 1; implicitHeight: Math.round(14 * toolbar.theme.scale)
            color: toolbar.theme.colors.border
            Layout.leftMargin: Math.round(4 * toolbar.theme.scale)
            Layout.rightMargin: Layout.leftMargin
        }

        Cmd {
            objectName: "quickUnderline"; theme: toolbar.theme; text: "subrayar"
            enabled: toolbar.canAnnotate
            onClicked: toolbar.underlineRequested()
        }
        Cmd {
            objectName: "quickRemoveUnderline"; theme: toolbar.theme; text: "desmarcar"; dim: true
            enabled: toolbar.canAnnotate
            onClicked: toolbar.removeUnderlineRequested()
        }
        Cmd {
            objectName: "quickNote"; theme: toolbar.theme; text: "+ nota"
            enabled: toolbar.canAnnotate
            onClicked: toolbar.noteRequested()
        }
        Cmd { objectName: "quickCopy"; theme: toolbar.theme; text: "copiar"; dim: true; onClicked: toolbar.copyRequested() }

        // Separador + cierre
        Rectangle {
            implicitWidth: 1; implicitHeight: Math.round(14 * toolbar.theme.scale)
            color: toolbar.theme.colors.border
            Layout.leftMargin: Math.round(4 * toolbar.theme.scale)
            Layout.rightMargin: Layout.leftMargin
        }
        Cmd {
            theme: toolbar.theme; text: "×"; dim: true
            Accessible.name: "Cerrar"
            onClicked: toolbar.close()
        }
    }
}

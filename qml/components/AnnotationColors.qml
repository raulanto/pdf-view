import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RowLayout {
    id: inkPalette
    required property var theme
    property string selectedColor: "#e69600"
    signal colorChosen(string value)
    spacing: 8
    Repeater {
        model: [
            {name:"Ámbar",value:"#e69600"}, {name:"Rojo",value:"#dc4c64"},
            {name:"Verde",value:"#2a9968"}, {name:"Azul",value:"#397ed0"},
            {name:"Violeta",value:"#9561c9"}, {name:"Negro",value:"#242424"}
        ]
        delegate: RadioButton {
            required property var modelData
            objectName: "ink"+modelData.value.substring(1)
            implicitWidth: 30; implicitHeight: 30
            indicator: null
            checked: inkPalette.selectedColor===modelData.value
            Accessible.name: "Color " + modelData.name
            ToolTip.visible: hovered; ToolTip.text: modelData.name
            onClicked: inkPalette.colorChosen(modelData.value)
            background: Rectangle {
                color: modelData.value
                border.width: parent.checked || parent.visualFocus ? 3 : 1
                border.color: parent.checked || parent.visualFocus ? inkPalette.theme.colors.foreground : inkPalette.theme.colors.border
            }
            contentItem: Text {
                text: parent.checked ? "✓" : ""
                color: modelData.value==="#e69600" ? "#151515" : "#ffffff"
                font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
        }
    }
}

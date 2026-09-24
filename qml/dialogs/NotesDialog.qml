import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Dialog {
    id: dialog
    required property var theme
    required property var page
    required property var canvasItem
    property var i18n
    readonly property alias noteEditor: draft
    readonly property alias saveButton: saveNote
    Connections { target: dialog.page; function onAnnotationSaved() { draft.text=""; dialog.close() } }
    parent: canvasItem
    modal: true
    closePolicy: Popup.NoAutoClose
    width: Math.min(520,canvasItem.width-32)
    x: (canvasItem.width-width)/2; y: (canvasItem.height-height)/2
    font.family: "monospace"
    background: Rectangle { color: theme.colors.background; border.color: theme.colors.border }
    header: ThemedLabel { theme: dialog.theme; text: dialog.i18n ? dialog.i18n.tr("notes.header", dialog.page.currentPage) : ("[ notas · página " + dialog.page.currentPage + " ]"); padding: 12 }
    onOpened: { draft.text=""; page.auxiliaryError=""; if (page.canAnnotate) draft.forceActiveFocus() }
    contentItem: ColumnLayout {
        spacing: 10
        ListView {
            Layout.fillWidth: true; Layout.preferredHeight: Math.min(180,contentHeight)
            clip: true; spacing: 8
            model: dialog.page.annotations.filter(a=>a.kind==="note")
            delegate: ThemedLabel {
                required property var modelData
                theme: dialog.theme; width: ListView.view.width
                text: "• " + modelData.text; wrapMode: Text.Wrap
            }
            ScrollBar.vertical: ScrollBar {}
        }
        ThemedLabel {
            theme: dialog.theme; Layout.fillWidth: true; wrapMode: Text.Wrap
            text: dialog.page.canAnnotate
                  ? (dialog.i18n ? dialog.i18n.tr("notes.infoAnnotate") : "Escribe una nota. Se guardará dentro del PDF abierto.")
                  : (dialog.i18n ? dialog.i18n.tr("notes.infoNoAnnotate") : "Las notas requieren PDFium y un PDF sin protección ni firma.")
        }
        AnnotationColors { theme: dialog.theme; selectedColor: dialog.page.annotationColor; visible: dialog.page.canAnnotate; onColorChosen: value => dialog.page.annotationColor=value }
        ScrollView {
            Layout.fillWidth: true; Layout.preferredHeight: 120
            visible: dialog.page.canAnnotate
            TextArea {
                id: draft; objectName: "noteDraft"
                font.family: "monospace"; color: dialog.theme.colors.foreground
                selectionColor: dialog.theme.colors.selection
                wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText
                placeholderText: dialog.i18n ? dialog.i18n.tr("notes.placeholder") : "Nota sobre la selección o esta página…"
                background: Rectangle { color: dialog.theme.colors.surface; border.color: dialog.theme.colors.border }
                Accessible.name: dialog.i18n ? dialog.i18n.tr("notes.accessibleText") : "Texto de la nota"
            }
        }
        ThemedLabel { theme: dialog.theme; Layout.fillWidth: true; wrapMode: Text.Wrap; text: dialog.page.auxiliaryError; visible: text.length>0; color: dialog.theme.colors.error }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            ThemedCommand { theme: dialog.theme; text: dialog.i18n ? dialog.i18n.tr("notes.close") : "cerrar"; enabled: !dialog.page.saving; onClicked: dialog.close() }
            ThemedCommand { id: saveNote; theme: dialog.theme; text: dialog.i18n ? dialog.i18n.tr("notes.save") : "guardar nota"; enabled: dialog.page.canAnnotate && draft.text.trim().length>0 && draft.text.length<=4000 && !dialog.page.saving; onClicked: dialog.page.saveAnnotation("note",draft.text) }
        }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Dialog {
    id: dialog
    required property var theme
    required property var preferences
    required property var canvasItem
    property var i18n
    property var draft: ({})
    property int tab: 0
    parent: canvasItem
    modal: true; focus: true
    closePolicy: preferences.busy ? Popup.NoAutoClose : Popup.CloseOnEscape
    width: Math.min(620,canvasItem.width-24)
    height: Math.min(610,canvasItem.height-24)
    x: (canvasItem.width-width)/2; y: (canvasItem.height-height)/2
    padding: 14
    palette.window: theme.colors.background
    palette.base: theme.colors.surface
    palette.button: theme.colors.surface
    palette.text: theme.colors.foreground
    palette.windowText: theme.colors.foreground
    palette.buttonText: theme.colors.foreground
    palette.highlight: theme.colors.accent
    palette.highlightedText: theme.colors.onAccent
    font.family: "monospace"
    background: Rectangle { color: dialog.theme.colors.background; border.color: dialog.theme.colors.border }
    header: ThemedLabel { theme: dialog.theme; text: dialog.i18n ? dialog.i18n.tr("settings.title") : "[ configuración ]"; padding: 14; font.bold: true }
    onTabChanged: scroller.contentY=0
    onOpened: { draft=JSON.parse(JSON.stringify(preferences.values)); tab=0 }
    Connections { target: dialog.preferences; function onSaved() { dialog.close() } }
    contentItem: ColumnLayout {
        spacing: 10
        RowLayout {
            Repeater {
                model: dialog.i18n ? [dialog.i18n.tr("settings.tabReading"), dialog.i18n.tr("settings.tabAppearance"), dialog.i18n.tr("settings.tabShortcuts")] : ["Lectura","Apariencia / OCR","Atajos"]
                ThemedCommand {
                    required property int index
                    required property string modelData
                    theme: dialog.theme; text: (dialog.tab===index ? "▸ " : "")+modelData
                    onClicked: dialog.tab=index
                }
            }
        }
        Flickable {
            id: scroller
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.minimumHeight: 0; Layout.preferredHeight: 0
            clip: true; contentWidth: width
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            contentHeight: settingsBody.implicitHeight
            function reveal(item) {
                const y=item.mapToItem(settingsBody,0,0).y
                if (y<contentY) contentY=y
                else if (y+item.height>contentY+height) contentY=y+item.height-height
            }
            ColumnLayout {
                id: settingsBody
                width: scroller.width-12; spacing: 12
                visible: !!dialog.draft.keys
                ColumnLayout {
                    visible: dialog.tab===0; Layout.fillWidth: true; spacing: 10
                    ThemedLabel { theme: dialog.theme; text: dialog.i18n ? dialog.i18n.tr("settings.openSection") : "Al abrir un documento" }
                    RowLayout {
                        Repeater {
                            model: [
                                {id:"page",label: dialog.i18n ? dialog.i18n.tr("settings.fitPage") : "Página"},
                                {id:"width",label: dialog.i18n ? dialog.i18n.tr("settings.fitWidth") : "Ancho"},
                                {id:"manual",label: dialog.i18n ? dialog.i18n.tr("settings.fitManual") : "Zoom fijo"}
                            ]
                            ThemedCommand {
                                required property var modelData
                                theme: dialog.theme; text: (dialog.draft.fit===modelData.id ? "[✓] " : "[ ] ")+modelData.label
                                onClicked: { dialog.draft.fit=modelData.id; dialog.draft=Object.assign({},dialog.draft) }
                            }
                        }
                    }
                    RowLayout {
                        ThemedLabel { theme: dialog.theme; text: dialog.i18n ? dialog.i18n.tr("settings.initialZoom") : "Zoom inicial (%)"; Layout.fillWidth: true }
                        SpinBox { from: 25; to: 400; stepSize: 25; value: dialog.draft.zoom || 100; onValueModified: dialog.draft.zoom=value; Accessible.name: dialog.i18n ? dialog.i18n.tr("settings.initialZoom") : "Zoom inicial" }
                    }
                    RowLayout {
                        ThemedLabel { theme: dialog.theme; text: dialog.i18n ? dialog.i18n.tr("settings.scrollStep") : "Desplazamiento por rueda (px)"; Layout.fillWidth: true }
                        SpinBox { from: 20; to: 400; stepSize: 20; value: dialog.draft.scrollStep || 100; onValueModified: dialog.draft.scrollStep=value; Accessible.name: dialog.i18n ? dialog.i18n.tr("settings.scrollStep") : "Paso de desplazamiento" }
                    }
                    CheckBox { text: dialog.i18n ? dialog.i18n.tr("settings.smoothScroll") : "Desplazamiento suave"; checked: !!dialog.draft.smooth; onToggled: dialog.draft.smooth=checked }
                    CheckBox { text: dialog.i18n ? dialog.i18n.tr("settings.showSidebar") : "Mostrar panel lateral"; checked: !!dialog.draft.sidebar; onToggled: dialog.draft.sidebar=checked }
                    CheckBox { text: dialog.i18n ? dialog.i18n.tr("settings.selectionToolbar") : "Abrir cinta al seleccionar texto"; checked: !!dialog.draft.selectionToolbar; onToggled: dialog.draft.selectionToolbar=checked }
                    ThemedLabel { theme: dialog.theme; text: dialog.i18n ? dialog.i18n.tr("settings.initialColor") : "Color inicial de notas y subrayados" }
                    AnnotationColors { theme: dialog.theme; selectedColor: dialog.draft.color || "#e69600"; onColorChosen: value => { dialog.draft.color=value; dialog.draft=Object.assign({},dialog.draft) } }
                }
                ColumnLayout {
                    visible: dialog.tab===1; Layout.fillWidth: true; spacing: 10
                    ThemedLabel { theme: dialog.theme; text: dialog.i18n ? dialog.i18n.tr("settings.appLanguage") : "Idioma de la aplicación" }
                    RowLayout {
                        Repeater {
                            model: [
                                {id:"auto",label: dialog.i18n ? dialog.i18n.tr("settings.langAuto") : "Automático (Sistema)"},
                                {id:"es",label: dialog.i18n ? dialog.i18n.tr("settings.langEs") : "Español"},
                                {id:"en",label: dialog.i18n ? dialog.i18n.tr("settings.langEn") : "English"}
                            ]
                            ThemedCommand {
                                required property var modelData
                                theme: dialog.theme; text: ((dialog.draft.appLanguage || "auto")===modelData.id ? "[✓] " : "[ ] ")+modelData.label
                                onClicked: { dialog.draft.appLanguage=modelData.id; dialog.draft=Object.assign({},dialog.draft) }
                            }
                        }
                    }
                    RowLayout {
                        ThemedLabel { theme: dialog.theme; text: dialog.i18n ? dialog.i18n.tr("settings.uiScale") : "Escala de interfaz (%)"; Layout.fillWidth: true }
                        SpinBox { from: 75; to: 150; stepSize: 5; value: dialog.draft.uiScale || 100; onValueModified: dialog.draft.uiScale=value; Accessible.name: dialog.i18n ? dialog.i18n.tr("settings.uiScale") : "Escala de interfaz" }
                    }
                    ThemedLabel { theme: dialog.theme; Layout.fillWidth: true; wrapMode: Text.Wrap; text: dialog.i18n ? dialog.i18n.tr("settings.themeInfo") : "Los colores siguen el tema de Omarchy. La escala se aplica sobre la del escritorio." }
                    CheckBox { text: dialog.i18n ? dialog.i18n.tr("settings.enableOcr") : "Activar OCR al iniciar"; checked: !!dialog.draft.ocr; onToggled: dialog.draft.ocr=checked }
                    ThemedLabel { theme: dialog.theme; text: dialog.i18n ? dialog.i18n.tr("settings.ocrLanguages") : "Idiomas OCR instalados (ej.: eng, spa+eng)" }
                    ThemedField { theme: dialog.theme; Layout.fillWidth: true; text: dialog.draft.language || "eng"; onTextEdited: dialog.draft.language=text; Accessible.name: dialog.i18n ? dialog.i18n.tr("settings.ocrLanguages") : "Idiomas OCR" }
                    ThemedLabel { theme: dialog.theme; Layout.fillWidth: true; wrapMode: Text.Wrap; text: dialog.i18n ? dialog.i18n.tr("settings.ocrInfo") : "El OCR usa modelos locales de Tesseract. No se descargan modelos automáticamente." }
                }
                ColumnLayout {
                    visible: dialog.tab===2; Layout.fillWidth: true; spacing: 6
                    ThemedLabel { theme: dialog.theme; Layout.fillWidth: true; wrapMode: Text.Wrap; text: dialog.i18n ? dialog.i18n.tr("settings.shortcutsInfo") : "Ejemplos: Ctrl+O, Alt+Right, F3. No se permiten duplicados. Esc siempre cierra los diálogos." }
                    Repeater {
                        model: dialog.preferences.actions
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            readonly property string actionId: modelData ? modelData.id : ""
                            readonly property string actionDefaultLabel: modelData ? modelData.label : ""
                            readonly property string actionTitle: (dialog.i18n && actionId) ? dialog.i18n.actionLabel(actionId, actionDefaultLabel) : actionDefaultLabel
                            ThemedLabel { theme: dialog.theme; text: parent.actionTitle; Layout.fillWidth: true }
                            ThemedField {
                                theme: dialog.theme; Layout.preferredWidth: 170
                                text: (dialog.draft.keys && parent.actionId) ? dialog.draft.keys[parent.actionId] : ""
                                onTextEdited: if (parent.actionId) dialog.draft.keys[parent.actionId]=text
                                Accessible.name: "Atajo: "+parent.actionTitle
                                onActiveFocusChanged: if (activeFocus) scroller.reveal(this)
                            }
                        }
                    }
                }
            }
        }
        ThemedLabel { theme: dialog.theme; Layout.fillWidth: true; wrapMode: Text.Wrap; text: dialog.preferences.error; color: dialog.theme.colors.error; visible: text.length>0 }
        RowLayout {
            id: footerRow
            Layout.fillWidth: true
            ThemedCommand { theme: dialog.theme; text: dialog.i18n ? dialog.i18n.tr("settings.restoreDefaults") : "Restaurar valores"; enabled: !dialog.preferences.busy; onClicked: dialog.draft=JSON.parse(JSON.stringify(dialog.preferences.defaults)) }
            Item { Layout.fillWidth: true }
            ThemedCommand { theme: dialog.theme; text: dialog.i18n ? dialog.i18n.tr("settings.cancel") : "Cancelar"; enabled: !dialog.preferences.busy; onClicked: dialog.close() }
            ThemedCommand { objectName: "saveSettings"; theme: dialog.theme; text: dialog.preferences.busy ? (dialog.i18n ? dialog.i18n.tr("settings.saving") : "Guardando…") : (dialog.i18n ? dialog.i18n.tr("settings.save") : "Guardar"); enabled: dialog.preferences.ready && !dialog.preferences.busy; onClicked: dialog.preferences.request("save",dialog.draft) }
        }
    }
}

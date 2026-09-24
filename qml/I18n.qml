import QtQuick
import Quickshell

QtObject {
    id: i18n

    property string appLanguage: "auto"

    readonly property string systemLanguage: {
        const lang = (Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || "").toLowerCase()
        return lang.startsWith("es") ? "es" : "en"
    }

    readonly property string currentLanguage: appLanguage === "auto" ? systemLanguage : appLanguage
    readonly property bool isEs: currentLanguage === "es"

    readonly property var translations: ({
        // General / Header
        "app.title": { "es": "pdf-view", "en": "pdf-view" },
        "app.noDocument": { "es": "sin documento", "en": "no document" },
        "app.configure": { "es": "configurar", "en": "settings" },
        "app.open": { "es": "abrir", "en": "open" },
        "app.openTitle": { "es": "[ abrir documento ]", "en": "[ open document ]" },

        // Empty state & opening
        "main.loading": { "es": "[ … ] cargando", "en": "[ … ] loading" },
        "main.errorOpen": { "es": "[ ! ] error de apertura", "en": "[ ! ] error opening document" },
        "main.preparingPage": { "es": "Preparando la página…", "en": "Preparing page…" },
        "main.openOrDrag": { "es": "Abre o arrastra un documento.\n%1  ·  seleccionar PDF", "en": "Open or drag a document.\n%1  ·  select PDF" },
        "main.enterPassword": { "es": "Introducir contraseña", "en": "Enter password" },
        "main.waitSave": { "es": "Espera a que termine el guardado.", "en": "Wait for saving to complete." },
        "main.dragSinglePdf": { "es": "Arrastra un único archivo PDF local.", "en": "Drag a single local PDF file." },

        // Toolbar
        "toolbar.prevPage": { "es": "Página anterior", "en": "Previous page" },
        "toolbar.nextPage": { "es": "Página siguiente", "en": "Next page" },
        "toolbar.goToPage": { "es": "Ir a página", "en": "Go to page" },
        "toolbar.zoomIn": { "es": "Aumentar zoom", "en": "Zoom in" },
        "toolbar.zoomOut": { "es": "Reducir zoom", "en": "Zoom out" },
        "toolbar.fitPage": { "es": "ajustar", "en": "fit" },
        "toolbar.fitWidth": { "es": "ancho", "en": "width" },
        "toolbar.annotate": { "es": "anotar ▾", "en": "annotate ▾" },
        "toolbar.annotateOptions": { "es": "Opciones de anotación", "en": "Annotation options" },
        "toolbar.clear": { "es": "desmarcar", "en": "clear" },
        "toolbar.clearSelection": { "es": "Desmarcar selección", "en": "Clear selection" },
        "toolbar.notes": { "es": "notas · %1", "en": "notes · %1" },

        // Search Bar
        "search.placeholder": { "es": "Buscar en el documento…", "en": "Search in document…" },

        // Sidebar
        "sidebar.document": { "es": "DOCUMENTO", "en": "DOCUMENT" },
        "sidebar.subtitle": { "es": "PDF / lectura y notas", "en": "PDF / reading & notes" },
        "sidebar.pageCountSingular": { "es": "%1 página", "en": "%1 page" },
        "sidebar.pageCountPlural": { "es": "%1 páginas", "en": "%1 pages" },
        "sidebar.noPages": { "es": "—", "en": "—" },
        "sidebar.tabPages": { "es": "páginas", "en": "pages" },
        "sidebar.tabIndex": { "es": "índice", "en": "outline" },
        "sidebar.tabPagesSelected": { "es": "[páginas]", "en": "[pages]" },
        "sidebar.tabIndexSelected": { "es": "[índice]", "en": "[outline]" },
        "sidebar.pageNumber": { "es": "Página %1", "en": "Page %1" },
        "sidebar.noOutline": { "es": "Sin índice", "en": "No outline" },
        "sidebar.ocrLanguage": { "es": "Idioma OCR", "en": "OCR language" },
        "sidebar.selectRange": { "es": "seleccionar rango", "en": "select page range" },
        "sidebar.cmdOpen": { "es": "Abrir", "en": "Open" },
        "sidebar.cmdSearch": { "es": "Buscar", "en": "Search" },
        "sidebar.cmdCopy": { "es": "Copiar", "en": "Copy" },

        // Status Bar
        "status.saving": { "es": "GUARDANDO", "en": "SAVING" },
        "status.reading": { "es": "LEYENDO", "en": "READING" },
        "status.error": { "es": "ERROR", "en": "ERROR" },
        "status.normal": { "es": "NORMAL", "en": "NORMAL" },
        "status.noDocument": { "es": "ningún documento abierto", "en": "no open document" },
        "status.selection": { "es": "selección · %1", "en": "selection · %1" },
        "status.processing": { "es": "procesando…", "en": "processing…" },
        "status.selectionStart": { "es": "inicio p.%1 · Shift+clic", "en": "start p.%1 · Shift+click" },
        "status.idle": { "es": "lectura y notas", "en": "reading & notes" },

        // Selection Toolbar
        "selection.colorAmber": { "es": "Ámbar", "en": "Amber" },
        "selection.colorRed": { "es": "Rojo", "en": "Red" },
        "selection.colorGreen": { "es": "Verde", "en": "Green" },
        "selection.colorBlue": { "es": "Azul", "en": "Blue" },
        "selection.colorPurple": { "es": "Violeta", "en": "Purple" },
        "selection.colorName": { "es": "Color %1", "en": "%1 color" },
        "selection.underline": { "es": "subrayar", "en": "underline" },
        "selection.clear": { "es": "desmarcar", "en": "clear" },
        "selection.addNote": { "es": "+ nota", "en": "+ note" },
        "selection.copy": { "es": "copiar", "en": "copy" },
        "selection.close": { "es": "Cerrar", "en": "Close" },

        // Notes Dialog
        "notes.header": { "es": "[ notas · página %1 ]", "en": "[ notes · page %1 ]" },
        "notes.infoAnnotate": { "es": "Escribe una nota. Se guardará dentro del PDF abierto.", "en": "Write a note. It will be saved inside the open PDF." },
        "notes.infoNoAnnotate": { "es": "Las notas requieren PDFium y un PDF sin protección ni firma.", "en": "Notes require PDFium and an unprotected, unsigned PDF." },
        "notes.placeholder": { "es": "Nota sobre la selección o esta página…", "en": "Note on selection or this page…" },
        "notes.accessibleText": { "es": "Texto de la nota", "en": "Note text" },
        "notes.close": { "es": "cerrar", "en": "close" },
        "notes.save": { "es": "guardar nota", "en": "save note" },

        // Password Dialog
        "password.header": { "es": "[ documento protegido ]", "en": "[ protected document ]" },
        "password.placeholder": { "es": "contraseña…", "en": "password…" },
        "password.cancel": { "es": "cancelar", "en": "cancel" },
        "password.ok": { "es": "[ ok ]", "en": "[ ok ]" },

        // Range Dialog
        "range.header": { "es": "[ seleccionar páginas ]", "en": "[ select page range ]" },
        "range.from": { "es": "desde", "en": "from" },
        "range.to": { "es": "hasta", "en": "to" },
        "range.cancel": { "es": "cancelar", "en": "cancel" },

        // File Picker
        "picker.parentFolder": { "es": "Carpeta superior", "en": "Parent folder" },
        "picker.noPdfs": { "es": "[ sin documentos PDF ]", "en": "[ no PDF documents ]" },

        // Settings Dialog
        "settings.title": { "es": "[ configuración ]", "en": "[ settings ]" },
        "settings.tabReading": { "es": "Lectura", "en": "Reading" },
        "settings.tabAppearance": { "es": "Apariencia / OCR", "en": "Appearance / OCR" },
        "settings.tabShortcuts": { "es": "Atajos", "en": "Shortcuts" },
        "settings.openSection": { "es": "Al abrir un documento", "en": "When opening a document" },
        "settings.fitPage": { "es": "Página", "en": "Page" },
        "settings.fitWidth": { "es": "Ancho", "en": "Width" },
        "settings.fitManual": { "es": "Zoom fijo", "en": "Fixed zoom" },
        "settings.initialZoom": { "es": "Zoom inicial (%)", "en": "Initial zoom (%)" },
        "settings.scrollStep": { "es": "Desplazamiento por rueda (px)", "en": "Wheel scroll (px)" },
        "settings.smoothScroll": { "es": "Desplazamiento suave", "en": "Smooth scrolling" },
        "settings.showSidebar": { "es": "Mostrar panel lateral", "en": "Show sidebar panel" },
        "settings.selectionToolbar": { "es": "Abrir cinta al seleccionar texto", "en": "Show toolbar when selecting text" },
        "settings.initialColor": { "es": "Color inicial de notas y subrayados", "en": "Initial annotation color" },
        "settings.uiScale": { "es": "Escala de interfaz (%)", "en": "UI scale (%)" },
        "settings.themeInfo": { "es": "Los colores siguen el tema de Omarchy. La escala se aplica sobre la del escritorio.", "en": "Colors follow Omarchy theme. Scale applies on top of desktop scale." },
        "settings.appLanguage": { "es": "Idioma de la aplicación", "en": "Application language" },
        "settings.langAuto": { "es": "Automático (Sistema)", "en": "Automatic (System)" },
        "settings.langEs": { "es": "Español", "en": "Spanish" },
        "settings.langEn": { "es": "English", "en": "English" },
        "settings.enableOcr": { "es": "Activar OCR al iniciar", "en": "Enable OCR on startup" },
        "settings.ocrLanguages": { "es": "Idiomas OCR instalados (ej.: eng, spa+eng)", "en": "Installed OCR languages (e.g. eng, spa+eng)" },
        "settings.ocrInfo": { "es": "El OCR usa modelos locales de Tesseract. No se descargan modelos automáticamente.", "en": "OCR uses local Tesseract models. No models are downloaded automatically." },
        "settings.shortcutsInfo": { "es": "Ejemplos: Ctrl+O, Alt+Right, F3. No se permiten duplicados. Esc siempre cierra los diálogos.", "en": "Examples: Ctrl+O, Alt+Right, F3. Duplicates not allowed. Esc always closes dialogs." },
        "settings.restoreDefaults": { "es": "Restaurar valores", "en": "Restore defaults" },
        "settings.cancel": { "es": "Cancelar", "en": "Cancel" },
        "settings.saving": { "es": "Guardando…", "en": "Saving…" },
        "settings.save": { "es": "Guardar", "en": "Save" },

        // Shortcut Action Labels
        "action.open": { "es": "Abrir PDF", "en": "Open PDF" },
        "action.search": { "es": "Buscar", "en": "Search" },
        "action.focus": { "es": "Modo lectura", "en": "Reading mode" },
        "action.next": { "es": "Página siguiente", "en": "Next page" },
        "action.previous": { "es": "Página anterior", "en": "Previous page" },
        "action.first": { "es": "Primera página", "en": "First page" },
        "action.last": { "es": "Última página", "en": "Last page" },
        "action.zoomIn": { "es": "Aumentar zoom", "en": "Zoom in" },
        "action.zoomOut": { "es": "Reducir zoom", "en": "Zoom out" },
        "action.fit": { "es": "Ajustar página", "en": "Fit page" },
        "action.rotate": { "es": "Rotar página", "en": "Rotate page" },
        "action.copy": { "es": "Copiar selección", "en": "Copy selection" },
        "action.selectAll": { "es": "Seleccionar todo", "en": "Select all" },
        "action.nextMatch": { "es": "Siguiente coincidencia", "en": "Next match" },
        "action.previousMatch": { "es": "Coincidencia anterior", "en": "Previous match" },
        "action.annotate": { "es": "Cinta de anotación", "en": "Annotation toolbar" },
        "action.settings": { "es": "Configuración", "en": "Settings" },

        // Preferences service messages
        "pref.errorExited": { "es": "El servicio de configuración terminó. Vuelve a abrir el visor.", "en": "Settings service exited. Please reopen viewer." },
        "pref.errorRead": { "es": "No se pudo leer la configuración.", "en": "Failed to read settings." }
    })

    function tr(key, p1, p2) {
        const item = translations[key]
        if (!item) return key
        let text = item[currentLanguage] || item["es"] || key
        if (p1 !== undefined) text = text.replace("%1", p1)
        if (p2 !== undefined) text = text.replace("%2", p2)
        return text
    }

    function actionLabel(actionId, fallback) {
        const key = "action." + actionId
        const item = translations[key]
        if (!item) return fallback || actionId
        return item[currentLanguage] || item["es"] || fallback || actionId
    }
}

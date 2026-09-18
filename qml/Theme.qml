import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: theme
    property var colors: ({background: "#171b24", surface: "#222838", foreground: "#e0e6f0",
        accent: "#7aa2f7", selection: "#343e55", border: "#59657a", error: "#f3a6a6", onAccent: "#000000", mode: "dark"})
    property real scale: 1.0
    readonly property string helper: Quickshell.env("PDF_VIEW_THEME_HELPER")
    property Process service: Process {
        command: [theme.helper]
        running: theme.helper.length > 0
        stdout: SplitParser {
            onRead: data => {
                try {
                    const next = JSON.parse(data)
                    for (const key of ["background", "surface", "foreground", "accent", "selection", "border", "error", "onAccent"]) {
                        if (!/^#[0-9a-fA-F]{6}$/.test(next.palette[key])) return
                    }
                    theme.colors = next.palette
                    const s = Number(next.scale)
                    if (s > 0 && s <= 8) theme.scale = s
                } catch (error) { console.warn("No se pudo leer la paleta del servicio de temas") }
            }
        }
        stderr: SplitParser { onRead: data => console.warn("Servicio de temas: " + data) }
        onExited: retry.start()
    }
    property Timer retry: Timer {
        interval: 2000
        onTriggered: { if (theme.helper.length > 0) theme.service.running = true }
    }
}

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: preferences
    property var values: ({})
    property var defaults: ({})
    property var actions: []
    property string error: ""
    property bool busy: false
    property bool ready: false
    property int serial: 0
    signal applied()
    signal saved()
    function value(name,fallback) { return values[name]===undefined ? fallback : values[name] }
    function key(name,fallback) { return values.keys ? values.keys[name] : fallback }
    function request(op,settings) {
        if (!ready || busy) return
        busy=true; error=""
        service.write(JSON.stringify({id:++serial,op:op,settings:settings})+"\n")
    }
    property Process service: Process {
        command: [Quickshell.env("PDF_VIEW_BACKEND"),"--settings"]
        stdinEnabled: true
        running: command[0].length>0
        onStarted: { preferences.ready=true; preferences.request("load",null) }
        onExited: { preferences.ready=false; preferences.busy=false; preferences.error="El servicio de configuración terminó. Vuelve a abrir el visor." }
        stdout: SplitParser {
            onRead: line => {
                try {
                    const response=JSON.parse(line)
                    if (response.id!==preferences.serial) return
                    preferences.busy=false
                    preferences.defaults=response.defaults; preferences.actions=response.actions
                    if (response.data.error) {
                        preferences.error=response.data.error
                        if (!preferences.values.keys) { preferences.values=response.defaults; preferences.applied() }
                        return
                    }
                    const wasLoaded=!!preferences.values.keys
                    preferences.values=response.data.settings; preferences.applied()
                    if (wasLoaded) preferences.saved()
                } catch (e) { preferences.busy=false; preferences.error="No se pudo leer la configuración." }
            }
        }
    }
}

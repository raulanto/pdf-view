import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: page
    property bool loading: false
    readonly property bool busy: loading || renderDelay.running
    property string error: ""
    property int pageCount: 0
    readonly property bool hasPage: preview.source.toString().length > 0
    property int currentPage: 1
    property int rotation: 0
    property real originalWidth: 612
    property real originalHeight: 792
    readonly property real pageWidth: rotation % 180 ? originalHeight : originalWidth
    readonly property real pageHeight: rotation % 180 ? originalWidth : originalHeight
    property real renderScale: 1
    property bool textReady: false
    property bool needsText: false
    property bool needsRefinement: false
    property var pageImages: ({})
    property var imageOrder: []
    // The host supplies the height of one page; keep coordinates page-local.
    property real singleHeight: height
    property real visibleTop: (currentPage-1)*(singleHeight+16)
    property real visibleHeight: singleHeight
    readonly property int firstVisible: Math.max(1,Math.floor(visibleTop/(singleHeight+16)))
    readonly property int lastVisible: Math.min(pageCount,Math.ceil((visibleTop+visibleHeight)/(singleHeight+16))+1)
    property bool passwordRequired: false
    property bool searching: false
    property string searchError: ""
    property var matches: []
    readonly property int matchCount: matches.length
    property int matchIndex: -1
    property bool searchTruncated: false
    property string selectedText: ""
    property bool canCopy: false
    property var outline: []
    property var thumbnails: ({})
    property bool auxiliaryBusy: false
    property string auxiliaryError: ""
    property bool ocrEnabled: false
    property string ocrLanguage: "eng"
    property int selectionStartPage: 0
    property int selectionStartWord: 0
    property rect normalizedRegion: Qt.rect(0,0,0,0)
    readonly property rect regionRect: Qt.rect(normalizedRegion.x*width,normalizedRegion.y*singleHeight,normalizedRegion.width*width,normalizedRegion.height*singleHeight)
    property color highlightColor: "#7aa2f7"
    property var words: []
    property int anchor: -1
    property int cursor: -1
    property int serial: 0
    property var pending: [null,null,null]
    property var thumbnailQueue: []
    property var thumbnailOrder: []
    property var failedThumbnails: ({})
    property var pendingRegion: null
    property bool ready: false
    property var opening: null
    property string documentUrl: ""
    signal changed()
    signal revealMatch(point point)
    QtObject { id: highlights; function requestPaint() { page.changed() } }

    Process {
        id: backend
        command: [Quickshell.env("PDF_VIEW_BACKEND")]
        stdinEnabled: true
        running: command[0].length > 0
        onStarted: { page.ready=true; if (page.opening) { const file=page.opening; page.opening=null; page.open(file) } }
        onExited: {
            page.ready=false; page.loading=false; page.searching=false; page.auxiliaryBusy=false
            page.pending=[null,null,null]; page.error="El servicio Rust terminó. Abre el documento para reintentar."
            page.changed()
        }
        stdout: SplitParser {
            onRead: data => {
                try { page.receive(JSON.parse(data)) }
                catch (e) { page.error="Respuesta inválida del servicio Rust."; console.warn(page.error + " " + e) }
            }
        }
        stderr: SplitParser { onRead: data => console.warn("Motor Rust: " + data) }
    }
    function cancel(kind) {
        const next=pending.slice(); next[kind]=null; pending=next
        if (ready) backend.write(JSON.stringify({op:"cancel",kind:kind,id:++serial})+"\n")
        if (kind===0) loading=false
        else if (kind===1) searching=false
        else auxiliaryBusy=false
    }
    function send(kind, request) {
        if (!ready) return
        request.id=++serial; request.kind=kind; request.ocr=ocrEnabled; request.language=ocrLanguage
        const next=pending.slice(); next[kind]=request; pending=next
        if (kind===0) { loading=true; error="" }
        else if (kind===1) { searching=true; searchError="" }
        else { auxiliaryBusy=true; auxiliaryError="" }
        backend.write(JSON.stringify(request)+"\n")
        changed()
    }
    function renderRequest(op) {
        return {op:op,page:currentPage,rotation:rotation/90,dpi:Math.max(18,Math.min(768,144*renderScale)),outline:false,text:false}
    }
    function open(url) {
        if (!ready) { opening=url; backend.running=true; return }
        renderDelay.stop(); regionDelay.stop()
        cancel(0); cancel(1); cancel(2)
        documentUrl=url.toString(); pageCount=0; currentPage=1; rotation=0; canCopy=false; passwordRequired=false
        preview.source=""; pageImages={}; imageOrder=[]; textReady=false; needsText=true; needsRefinement=false; words=[]; outline=[]; thumbnails={}; thumbnailOrder=[]; thumbnailQueue=[]; failedThumbnails={}
        searchError=""; auxiliaryError=""; matches=[]; matchIndex=-1; searchTruncated=false; selectionStartPage=0; clearSelection(); resetRegion()
        const request=renderRequest("open"); request.url=documentUrl; request.dpi=54; needsRefinement=true; send(0,request)
    }
    function unlock(password) { needsText=true; needsRefinement=true; const request=renderRequest("unlock"); request.dpi=54; request.password=password; passwordRequired=false; send(0,request) }
    function render() {
        renderDelay.stop()
        if (documentUrl && !passwordRequired) {
            const request=renderRequest("render")
            if (!hasPage) { request.dpi=54; needsRefinement=true }
            send(0,request)
        }
    }
    function receive(message) {
        const kind=message.kind, request=pending[kind]
        if (!request || request.id!==message.id) return
        const next=pending.slice(); next[kind]=null; pending=next
        if (kind===0) loading=false
        else if (kind===1) searching=false
        else auxiliaryBusy=false
        const data=message.data
        if (data.error || data.locked) {
            const reason=data.error || "Introduce la contraseña del documento."
            if (kind===0) { error=reason; passwordRequired=!!data.locked }
            else if (kind===1) searchError=reason
            else { auxiliaryError=reason; if (request.op==="thumbnail") failedThumbnails[request.page]=true }
        } else if (request.op==="search") {
            matches=data.matches; searchTruncated=data.truncated; matchIndex=-1
            if (matches.length) nextMatch(1)
        } else if (request.op==="extract") {
            anchor=-1; cursor=-1; selectedText=data.text
        } else if (request.op==="text") {
            if (request.page===currentPage && request.rotation===rotation/90) {
                words=data.words; textReady=true
                if (data.outline) outline=data.outline
            }
        } else if (request.op==="thumbnail") {
            const images=Object.assign({},thumbnails); images[request.page]=data.image
            thumbnailOrder.push(request.page)
            while (thumbnailOrder.length>48) delete images[thumbnailOrder.shift()]
            thumbnails=images
        } else if (request.op==="region") {
            if (request.page===currentPage && request.rotation===rotation/90) {
                normalizedRegion=Qt.rect(request.region[0],request.region[1],request.region[2],request.region[3]); detail.source=data.image
            }
        } else {
            originalWidth=data.pageWidth; originalHeight=data.pageHeight; pageCount=data.pages
            canCopy=data.canCopy; passwordRequired=false; preview.source=data.image
            const key=currentPage+":"+rotation, images=Object.assign({},pageImages)
            images[key]=data.image; imageOrder=imageOrder.filter(k=>k!==key); imageOrder.push(key)
            while (imageOrder.length>6 || imageOrder.reduce((n,k)=>n+images[k].length,0)>48*1024*1024) delete images[imageOrder.shift()]
            pageImages=images
            if (data.outline) outline=data.outline
            revealCurrentMatch()
        }
        highlights.requestPaint(); changed(); Qt.callLater(pumpAuxiliary)
    }
    function goToPage(number) {
        if (number<1 || number>pageCount || number===currentPage) return
        cancelAuxiliary(); resetRegion(); currentPage=number
        preview.source=pageImages[number+":"+rotation] || (rotation===0 ? thumbnails[number] || "" : "")
        words=[]; textReady=false; needsText=true; needsRefinement=false; clearSelection(); render()
    }
    function rotatePage(steps) {
        if (!pageCount) return
        cancelAuxiliary(); resetRegion(); rotation=((rotation+steps*90)%360+360)%360
        preview.source=pageImages[currentPage+":"+rotation] || ""
        words=[]; textReady=false; needsText=true; needsRefinement=false; clearSelection(); render()
    }
    function search(query) {
        cancel(1); matches=[]; matchIndex=-1; searchTruncated=false; searchError=""; highlights.requestPaint()
        if (query.length && pageCount) send(1,{op:"search",query:query})
    }
    function nextMatch(direction) {
        if (!matches.length) return
        matchIndex=matchIndex<0 ? (direction<0 ? matches.length-1 : 0) : (matchIndex+(direction<0?-1:1)+matches.length)%matches.length
        if (currentPage!==matches[matchIndex].page) goToPage(matches[matchIndex].page)
        else revealCurrentMatch()
        highlights.requestPaint()
    }
    function mapRect(rect) {
        let x=rect[0],y=rect[1],w=rect[2],h=rect[3]
        if (rotation===90) { x=originalHeight-rect[1]-rect[3]; y=rect[0]; w=rect[3]; h=rect[2] }
        if (rotation===180) { x=originalWidth-rect[0]-rect[2]; y=originalHeight-rect[1]-rect[3] }
        if (rotation===270) { x=rect[1]; y=originalWidth-rect[0]-rect[2]; w=rect[3]; h=rect[2] }
        return Qt.rect(x*width/pageWidth,y*singleHeight/pageHeight,w*width/pageWidth,h*singleHeight/pageHeight)
    }
    function revealCurrentMatch() {
        if (matchIndex>=0 && matches[matchIndex].page===currentPage && hasPage) {
            const r=mapRect(matches[matchIndex].rect); revealMatch(Qt.point(r.x+r.width/2,r.y+r.height/2+(currentPage-1)*(singleHeight+16)))
        }
    }
    function wordAt(x,y) {
        let best=-1,distance=Infinity
        for (let i=0;i<words.length;i++) {
            const r=mapRect(words[i].rect), dx=Math.max(r.x-x,0,x-r.x-r.width),dy=Math.max(r.y-y,0,y-r.y-r.height),d=dx*dx+dy*dy
            if (d<distance) {best=i;distance=d}
        }return best
    }
    function updateSelection() {
        if (anchor<0 || cursor<0 || !canCopy) return
        let text="",first=Math.min(anchor,cursor),last=Math.max(anchor,cursor)
        for (let i=first;i<=last;i++) {
            text+=words[i].text
            if (i<last) {
                const a=words[i].rect,b=words[i+1].rect
                if (Math.abs(b[1]+b[3]/2-a[1]-a[3]/2)>a[3]/2) text+="\n"
                else if (words[i].space) text+=" "
            }
        }selectedText=text; highlights.requestPaint()
    }
    function clearSelection() { anchor=-1; cursor=-1; selectedText=""; highlights.requestPaint() }
    function selectAll() { if (canCopy && words.length) {selectionStartPage=currentPage;selectionStartWord=0;anchor=0;cursor=words.length-1;updateSelection()} }
    function copySelection() { if (selectedText.length) Quickshell.clipboardText=selectedText }
    function selectPageRange(first,last) {
        if (!canCopy || first<1 || last<first || last>pageCount || last-first>=100) {auxiliaryError="Selecciona un rango de hasta 100 páginas con permiso de copia.";return}
        cancelAuxiliary(); clearSelection(); send(2,{op:"extract",first:first,last:last})
    }
    function cancelAuxiliary() {
        if (pending[2] && pending[2].op==="text") needsText=true
        if (pending[2] && pending[2].op==="thumbnail") thumbnailQueue.unshift(pending[2].page)
        cancel(2)
    }
    function requestThumbnail(number) {
        if (number<1 || number>pageCount || thumbnails[number] || failedThumbnails[number] || thumbnailQueue.indexOf(number)>=0 || (pending[2] && pending[2].op==="thumbnail" && pending[2].page===number)) return
        if (thumbnailQueue.length>=24) thumbnailQueue.shift()
        thumbnailQueue.push(number); pumpAuxiliary()
    }
    function pumpAuxiliary() {
        if (busy || !pageCount || passwordRequired) return
        if (needsRefinement) { needsRefinement=false; send(0,renderRequest("render")) }
        if (auxiliaryBusy) return
        if (needsText) {
            needsText=false
            send(2,{op:"text",page:currentPage,rotation:rotation/90,outline:outline.length===0})
            requestThumbnail(currentPage-1); requestThumbnail(currentPage+1)
        } else if (pendingRegion) {
            const r=pendingRegion; pendingRegion=null
            send(2,{op:"region",page:currentPage,rotation:rotation/90,region:r,dpi:Math.max(18,Math.min(144*renderScale,2040*72/(r[2]*pageWidth),2040*72/(r[3]*pageHeight),768))})
        } else if (thumbnailQueue.length) send(2,{op:"thumbnail",page:thumbnailQueue.shift(),rotation:0,dpi:72})
    }
    function resetRegion() {
        regionDelay.stop(); pendingRegion=null; normalizedRegion=Qt.rect(0,0,0,0); detail.source=""
        if (pending[2] && pending[2].op==="region") cancel(2)
    }
    function requestRegion(visible) {
        if (!hasPage || width<=0 || height<=0 || renderScale<=1.25) return
        const top=visible.y-(currentPage-1)*(singleHeight+16)
        const x=Math.max(0,visible.x),y=Math.max(0,top),w=Math.min(width,visible.x+visible.width)-x,h=Math.min(singleHeight,top+visible.height)-y
        if (w<=0 || h<=0) return
        const r=[x/width,y/singleHeight,w/width,h/singleHeight],old=normalizedRegion
        if (r[0]===old.x && r[1]===old.y && r[2]===old.width && r[3]===old.height) return
        pendingRegion=r; regionDelay.restart()
    }
    onRenderScaleChanged: { resetRegion(); if (documentUrl && !passwordRequired) renderDelay.restart() }
    onOcrEnabledChanged: { selectionStartPage=0;clearSelection();search("");cancelAuxiliary();resetRegion();words=[];textReady=false;needsText=true;render() }
    onOcrLanguageChanged: { if (ocrEnabled) {selectionStartPage=0;clearSelection();search("");cancelAuxiliary();resetRegion();words=[];textReady=false;needsText=true;render()} }
    onHighlightColorChanged: highlights.requestPaint()
    onWidthChanged: highlights.requestPaint()
    onHeightChanged: highlights.requestPaint()
    Timer { id: renderDelay; interval:150; onTriggered: page.render() }
    Timer { id: regionDelay; interval:180; onTriggered: page.pumpAuxiliary() }
    Image { id: preview; visible: false; cache:false; smooth:true }
    Image { id: detail; visible: false; cache:false; smooth:true }
    Item {
        anchors.fill: parent
        Repeater {
            model: Math.max(0,page.lastVisible-page.firstVisible+1)
            delegate: Item {
                id: pageFrame
                required property int index
                readonly property int pageNum: page.firstVisible + index
                readonly property bool isCurrent: pageNum === page.currentPage
                width: page.width
                height: page.singleHeight
                y: (pageNum-1)*(height+16)
                Component.onCompleted: page.requestThumbnail(pageNum)
                
                Rectangle {
                    anchors.fill: parent
                    color: "#ffffff"
                    border.color: Qt.rgba(0, 0, 0, 0.2)
                    border.width: 1
                }
                
                Image {
                    anchors.fill: parent
                    cache: false
                    smooth: true
                    source: isCurrent && preview.source.toString().length > 0 ? preview.source : (page.pageImages[pageNum+":"+page.rotation] || (page.rotation===0 ? page.thumbnails[String(pageNum)] || "" : ""))
                }
                
                Image {
                    visible: isCurrent
                    x: page.regionRect.x; y: page.regionRect.y; width: page.regionRect.width; height: page.regionRect.height
                    cache: false; smooth: true
                    source: isCurrent ? detail.source : ""
                }
                
                Canvas {
                    id: frameCanvas
                    visible: isCurrent
                    anchors.fill: parent
                    canvasSize: Qt.size(Math.min(2000, width), Math.min(2000, height))
                    onPaint: {
                        const ctx = getContext("2d"); ctx.reset(); ctx.clearRect(0,0,canvasSize.width,canvasSize.height)
                        if (width <= 0 || height <= 0) return
                        ctx.scale(canvasSize.width/width, canvasSize.height/height)
                        ctx.fillStyle = Qt.rgba(page.highlightColor.r, page.highlightColor.g, page.highlightColor.b, 0.3)
                        ctx.strokeStyle = page.highlightColor; ctx.lineWidth = 2
                        for (let i = 0; i < page.matches.length; i++) if (page.matches[i].page === pageNum) {
                            const r = page.mapRect(page.matches[i].rect); ctx.fillRect(r.x, r.y, r.width, r.height)
                            if (i === page.matchIndex) ctx.strokeRect(r.x, r.y, r.width, r.height)
                        }
                        if (page.anchor >= 0 && page.cursor >= 0 && page.currentPage === pageNum) for(let i = Math.min(page.anchor, page.cursor); i <= Math.max(page.anchor, page.cursor); i++) {
                            const r = page.mapRect(page.words[i].rect); ctx.fillRect(r.x, r.y, r.width, r.height)
                        }
                    }
                    Connections {
                        target: page
                        function onChanged() { frameCanvas.requestPaint() }
                    }
                }
            }
        }
    }
    MouseArea {
        width: parent.width; height: page.singleHeight
        y: (page.currentPage-1)*(page.singleHeight+16)
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.IBeamCursor
        onPressed: mouse => {
            page.forceActiveFocus(); const i = page.wordAt(mouse.x, mouse.y)
            if (i < 0 || !page.canCopy) { mouse.accepted = false; return }
            if ((mouse.modifiers & Qt.ShiftModifier) && page.selectionStartPage > 0) {
                let first = page.selectionStartPage, last = page.currentPage, a = page.selectionStartWord, b = i
                if (first > last || (first === last && a > b)) { const p = first; first = last; last = p; const w = a; a = b; b = w }
                page.cancelAuxiliary(); page.clearSelection(); page.send(2, {op: "extract", first: first, last: last, firstWord: a, lastWord: b}); return
            }
            page.clearSelection(); const r = page.mapRect(page.words[i].rect)
            if (mouse.x < r.x - 4 || mouse.y < r.y - 4 || mouse.x > r.x + r.width + 4 || mouse.y > r.y + r.height + 4) { mouse.accepted = false; return }
            page.selectionStartPage = page.currentPage; page.selectionStartWord = i; page.anchor = i; page.cursor = i; page.updateSelection()
        }
        onPositionChanged: mouse => { if (pressed && page.anchor >= 0) { page.cursor = page.wordAt(mouse.x, mouse.y); page.updateSelection() } }
    }
}

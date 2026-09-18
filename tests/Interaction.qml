import QtQuick
import QtTest
import Quickshell
import qs.qml

ShellRoot {
  FloatingWindow {
    visible: true; implicitWidth: 900; implicitHeight: 900
    PdfPage { id: doc; width: pageWidth; height: pageHeight; y: -(currentPage-1)*(singleHeight+16) }
    TestCase {
        name: "RustPdfInteraction"
        property int checks: 0
        when: doc.ready
        function cleanupTestCase() {
            if (checks===9) console.log("INTERACTION PASSED: mouse selection at 0/90/180/270 degrees, drag, clipboard, Shift+click stale responses and preloaded scrolling")
            else console.error("INTERACTION FAILED: " + checks + "/9 checks completed")
            Qt.quit()
        }
        function initTestCase() {
            doc.open(Quickshell.env("PDF_VIEW_DOCUMENT"))
            tryVerify(() => doc.hasPage && !doc.busy && doc.textReady,20000)
        }
        function test_selection_data() {
            return [{tag:"0",angle:0},{tag:"90",angle:90},{tag:"180",angle:180},{tag:"270",angle:270}]
        }
        function test_selection(data) {
            doc.goToPage(1)
            doc.rotatePage((data.angle-doc.rotation)/90)
            tryVerify(() => doc.hasPage && !doc.busy && doc.textReady,20000)
            const index=doc.words.findIndex(w => w.text==="Quickshell")
            verify(index>=0)
            const r=doc.mapRect(doc.words[index].rect)
            mouseClick(doc,r.x+r.width/2,r.y+r.height/2+(doc.currentPage-1)*(doc.singleHeight+16))
            compare(doc.selectedText,"Quickshell")
            doc.copySelection()
            compare(Quickshell.clipboardText,"Quickshell")
            checks++
        }
        function test_drag() {
            doc.goToPage(1); doc.rotatePage(-doc.rotation/90)
            tryVerify(() => doc.hasPage && !doc.busy && doc.textReady,20000)
            const a=doc.mapRect(doc.words[0].rect),b=doc.mapRect(doc.words[doc.words.length-1].rect)
            mousePress(doc,a.x+a.width/2,a.y+a.height/2+(doc.currentPage-1)*(doc.singleHeight+16))
            mouseMove(doc,b.x+b.width/2,b.y+b.height/2+(doc.currentPage-1)*(doc.singleHeight+16))
            mouseRelease(doc,b.x+b.width/2,b.y+b.height/2+(doc.currentPage-1)*(doc.singleHeight+16))
            compare(doc.selectedText,"PDF View - Quickshell")
            checks++
        }
        function test_scrollCache() {
            doc.goToPage(1); doc.rotatePage(-doc.rotation/90)
            tryVerify(() => doc.imageIsReady(1) && doc.imageIsReady(2),20000)
            const images=Object.assign({},doc.pageImages); delete images["2:0"]; doc.pageImages=images
            doc.imageOrder=doc.imageOrder.filter(key=>key!=="2:0")
            doc.preloadAttempts={}; doc.preloadPages()
            verify(doc.pending[0] && doc.pending[0].preload)
            doc.send(0,doc.renderRequest("render")) // interrupt the preload before its response
            tryVerify(() => doc.imageIsReady(2),20000)
            const second=findChild(doc,"pdfPage2")
            verify(second!==null)
            for (let i=0;i<8;i++) {
                doc.goToPage(i%2+1)
                verify(doc.hasPage)
                verify(!doc.loading, "Preloaded page must not trigger a foreground render")
                wait(20)
                compare(findChild(doc,"pdfPage2"),second,"Visible delegates must survive page changes")
            }
            checks++
        }
        function test_scrollLateRender() {
            doc.goToPage(1); doc.rotatePage(-doc.rotation/90)
            tryVerify(() => doc.imageIsReady(1) && doc.imageIsReady(2),20000)
            // A render of page 1 can finish after scrolling to cached page 2.
            doc.send(0,doc.renderRequest("render"))
            const request=doc.pending[0], oldImage=doc.pageImages["1:0"], oldInfo=doc.imageInfo["1:0"]
            doc.goToPage(2)
            const visibleImage=doc.pageImages["2:0"]
            doc.receive({id:request.id,kind:0,data:{image:oldImage,pageWidth:oldInfo.pageWidth,pageHeight:oldInfo.pageHeight,pages:2,canCopy:true}})
            compare(doc.pageImages["2:0"],visibleImage)
            const frame=findChild(doc,"pdfPage2")
            const image=findChild(frame,"pageImage")
            compare(image.source.toString(),visibleImage)
            checks++
        }
        function test_staleResponses() {
            doc.search("Second")
            doc.open(Quickshell.env("PDF_VIEW_DOCUMENT"))
            tryVerify(() => doc.hasPage && !doc.busy && doc.textReady,20000)
            wait(200)
            compare(doc.currentPage,1);compare(doc.matchCount,0)
            checks++
        }
        function test_shiftRange() {
            doc.goToPage(1); doc.rotatePage(-doc.rotation/90)
            tryVerify(() => doc.hasPage && !doc.busy && doc.textReady,20000)
            const a=doc.mapRect(doc.words[0].rect)
            mouseClick(doc,a.x+a.width/2,a.y+a.height/2+(doc.currentPage-1)*(doc.singleHeight+16))
            doc.goToPage(2)
            tryVerify(() => doc.hasPage && !doc.busy && doc.textReady,20000)
            const b=doc.mapRect(doc.words[doc.words.length-1].rect)
            mouseClick(doc,b.x+b.width/2,b.y+b.height/2+(doc.currentPage-1)*(doc.singleHeight+16),Qt.LeftButton,Qt.ShiftModifier)
            tryVerify(() => !doc.auxiliaryBusy,20000)
            verify(doc.selectedText.indexOf("Quickshell")>=0)
            verify(doc.selectedText.indexOf("Second page")>=0)
            checks++
        }
    }
}
}

import QtQuick
import QtTest
import Quickshell
import qs.qml

ShellRoot {
  FloatingWindow {
    visible: true; implicitWidth: 900; implicitHeight: 900
    PdfPage { id: doc; width: pageWidth; height: pageHeight }
    TestCase {
        name: "RustPdfInteraction"
        property int checks: 0
        when: doc.ready
        function cleanupTestCase() {
            if (checks===7) console.log("INTERACTION PASSED: mouse selection at 0/90/180/270 degrees, drag, clipboard, Shift+click and stale responses")
            else console.error("INTERACTION FAILED: " + checks + "/7 checks completed")
            Qt.quit()
        }
        function initTestCase() {
            doc.open(Quickshell.env("PDF_VIEW_DOCUMENT"))
            tryVerify(() => doc.hasPage && !doc.busy,20000)
        }
        function test_selection_data() {
            return [{tag:"0",angle:0},{tag:"90",angle:90},{tag:"180",angle:180},{tag:"270",angle:270}]
        }
        function test_selection(data) {
            doc.goToPage(1)
            doc.rotatePage((data.angle-doc.rotation)/90)
            tryVerify(() => doc.hasPage && !doc.busy,20000)
            const index=doc.words.findIndex(w => w.text==="Quickshell")
            verify(index>=0)
            const r=doc.mapRect(doc.words[index].rect)
            mouseClick(doc,r.x+r.width/2,r.y+r.height/2)
            compare(doc.selectedText,"Quickshell")
            doc.copySelection()
            compare(Quickshell.clipboardText,"Quickshell")
            checks++
        }
        function test_drag() {
            doc.goToPage(1); doc.rotatePage(-doc.rotation/90)
            tryVerify(() => doc.hasPage && !doc.busy,20000)
            const a=doc.mapRect(doc.words[0].rect),b=doc.mapRect(doc.words[doc.words.length-1].rect)
            mousePress(doc,a.x+a.width/2,a.y+a.height/2)
            mouseMove(doc,b.x+b.width/2,b.y+b.height/2)
            mouseRelease(doc,b.x+b.width/2,b.y+b.height/2)
            compare(doc.selectedText,"PDF View - Quickshell")
            checks++
        }
        function test_staleResponses() {
            doc.search("Second")
            doc.open(Quickshell.env("PDF_VIEW_DOCUMENT"))
            tryVerify(() => doc.hasPage && !doc.busy,20000)
            wait(200)
            compare(doc.currentPage,1);compare(doc.matchCount,0)
            checks++
        }
        function test_shiftRange() {
            doc.goToPage(1); doc.rotatePage(-doc.rotation/90)
            tryVerify(() => doc.hasPage && !doc.busy,20000)
            const a=doc.mapRect(doc.words[0].rect)
            mouseClick(doc,a.x+a.width/2,a.y+a.height/2)
            doc.goToPage(2)
            tryVerify(() => doc.hasPage && !doc.busy,20000)
            const b=doc.mapRect(doc.words[doc.words.length-1].rect)
            mouseClick(doc,b.x+b.width/2,b.y+b.height/2,Qt.LeftButton,Qt.ShiftModifier)
            tryVerify(() => !doc.auxiliaryBusy,20000)
            verify(doc.selectedText.indexOf("Quickshell")>=0)
            verify(doc.selectedText.indexOf("Second page")>=0)
            checks++
        }
    }
}
}

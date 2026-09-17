#include "pdfpage.h"
#include "sandbox.h"
#include <QtTest>
#include <QPdfWriter>
#include <QPainter>
#include <QTemporaryDir>
#include <QFile>
#include <QClipboard>
#include <QGuiApplication>
#include <QStandardPaths>
#include <fcntl.h>
#include <unistd.h>

class SelectablePage : public PdfPage {
public:
    using PdfPage::mousePressEvent;
    using PdfPage::mouseReleaseEvent;
};

class Tests : public QObject {
    Q_OBJECT
    QTemporaryDir dir;
    QString pdf;
private slots:
    void initTestCase() {
        QVERIFY(dir.isValid());
        pdf = dir.filePath("sample with spaces.pdf");
        QPdfWriter writer(pdf);
        writer.setPageSize(QPageSize(QPageSize::A4));
        QPainter painter(&writer);
        painter.setPen(Qt::black);
        painter.setFont(QFont("sans-serif", 32));
        painter.drawText(200, 1000, "PDF View - Quickshell");
        writer.newPage();
        painter.drawText(200, 1000, "Second page");
        painter.end();
        const QString output = qEnvironmentVariable("PDF_VIEW_TEST_FIXTURE");
        if (!output.isEmpty()) {
            QVERIFY(!QFile::exists(output) || QFile::remove(output));
            QVERIFY(QFile::copy(pdf, output));
        }
    }
    void render() {
        PdfPage page;
        page.open(QUrl::fromLocalFile(pdf));
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 20000);
        QVERIFY2(page.error().isEmpty(), qPrintable(page.error()));
        QVERIFY(page.hasPage());
        QCOMPARE(page.pageCount(), 2);
        page.setWidth(400); page.setHeight(600);
        QImage image(400, 600, QImage::Format_RGB32); image.fill(Qt::magenta);
        QPainter painter(&image); page.paint(&painter); painter.end();
        QVERIFY(image.pixelColor(200,300) != QColor(Qt::magenta));
        QVERIFY(image.save(dir.filePath("render.png")));
    }
    void errorsAndRecovery() {
        PdfPage page;
        page.open(QUrl("https://example.com/file.pdf"));
        QVERIFY(!page.error().isEmpty());
        const QString bad = dir.filePath("bad.pdf");
        QFile f(bad); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("not a pdf"); f.close();
        page.open(QUrl::fromLocalFile(bad));
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 20000);
        QVERIFY(!page.error().isEmpty()); QVERIFY(!page.hasPage());
        page.open(QUrl::fromLocalFile(pdf));
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 20000);
        QVERIFY2(page.hasPage(), qPrintable(page.error()));
    }
    void navigationZoomRotationAndText() {
        PdfPage page;
        page.open(QUrl::fromLocalFile(pdf));
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 25000);
        QVERIFY2(page.hasPage(), qPrintable(page.error()));
        page.selectAll();
        QVERIFY(page.selectedText().contains("Quickshell"));
        page.copySelection();
        QCOMPARE(QGuiApplication::clipboard()->text(), page.selectedText());
        page.goToPage(2);
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 25000);
        QCOMPARE(page.currentPage(), 2);
        page.selectAll();
        QVERIFY2(page.selectedText().contains("Second page"), qPrintable(page.selectedText()));
        const double width=page.pageWidth(), height=page.pageHeight();
        page.rotatePage(1);
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 25000);
        QCOMPARE(page.rotation(), 90);
        QCOMPARE(page.pageWidth(), height);
        QCOMPARE(page.pageHeight(), width);
        page.selectAll();
        QVERIFY(page.selectedText().contains("Second page"));
        page.setRenderScale(4);
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 25000);
        QVERIFY2(page.hasPage(), qPrintable(page.error()));
        QCOMPARE(page.renderScale(), 4.0);
        page.goToPage(0); page.goToPage(3);
        QCOMPARE(page.currentPage(), 2);
        page.rotatePage(-1);
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 25000);
        QCOMPARE(page.rotation(), 0);
        page.clearSelection();
        QVERIFY(page.selectedText().isEmpty());
    }
    void mouseSelectionAfterRotation() {
        SelectablePage page;
        page.setWidth(600); page.setHeight(800);
        page.open(QUrl::fromLocalFile(pdf));
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 25000);
        for (int rotation=0; rotation<4; ++rotation) {
            if (rotation) page.rotatePage(1);
            QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 25000);
            QImage image(600,800,QImage::Format_RGB32); image.fill(Qt::white);
            QPainter painter(&image); page.paint(&painter); painter.end();
            QPointF hit(-1,-1);
            for (int y=0; y<800 && hit.x()<0; ++y) for (int x=0; x<600; ++x) {
                if (image.pixelColor(x,y).lightness()<80) { hit=QPointF(x,y); break; }
            }
            QVERIFY(hit.x()>=0);
            QMouseEvent press(QEvent::MouseButtonPress,hit,hit,Qt::LeftButton,Qt::LeftButton,Qt::NoModifier);
            page.mousePressEvent(&press);
            QVERIFY2(!page.selectedText().isEmpty(), qPrintable(QString("No text selected at rotation %1").arg(rotation*90)));
            QMouseEvent release(QEvent::MouseButtonRelease,hit,hit,Qt::LeftButton,Qt::NoButton,Qt::NoModifier);
            page.mouseReleaseEvent(&release);
            page.clearSelection();
        }
    }
    void searchAndCancellation() {
        PdfPage page;
        page.open(QUrl::fromLocalFile(pdf));
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 25000);
        page.search("SECOND");
        QTRY_VERIFY_WITH_TIMEOUT(!page.searching(), 35000);
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 25000);
        QVERIFY2(page.searchError().isEmpty(), qPrintable(page.searchError()));
        QCOMPARE(page.matchCount(), 1);
        QCOMPARE(page.currentPage(), 2);
        page.nextMatch(-1);
        QCOMPARE(page.matchIndex(), 0);
        page.search("unfindable-string");
        QTRY_VERIFY_WITH_TIMEOUT(!page.searching(), 35000);
        QCOMPARE(page.matchCount(), 0);
        page.search("Second");
        page.search("Quickshell");
        QTRY_VERIFY_WITH_TIMEOUT(!page.searching(), 35000);
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 25000);
        QCOMPARE(page.currentPage(), 1);
        QCOMPARE(page.matchCount(), 1);
        page.goToPage(2); page.goToPage(1); page.goToPage(2);
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 25000);
        QCOMPARE(page.currentPage(), 2);
        page.selectAll(); QVERIFY(page.selectedText().contains("Second"));
        page.search("Second");
        page.open(QUrl::fromLocalFile(dir.filePath("absent.pdf")));
        QTest::qWait(300);
        QVERIFY(!page.hasPage()); QVERIFY(!page.searching()); QCOMPARE(page.matchCount(), 0);
    }
    void passwordAndCopyPermissions() {
        const QString qpdf=QStandardPaths::findExecutable("qpdf");
        if (qpdf.isEmpty()) QSKIP("qpdf required to generate encrypted test documents");
        const QString encrypted=dir.filePath("protected.pdf");
        QCOMPARE(QProcess::execute(qpdf, {"--encrypt","test-user","test-owner","256","--extract=n","--",pdf,encrypted}), 0);
        PdfPage page;
        page.open(QUrl::fromLocalFile(encrypted));
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 25000);
        QVERIFY(page.passwordRequired()); QVERIFY(!page.hasPage());
        page.unlock("wrong");
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 25000);
        QVERIFY(page.passwordRequired());
        page.unlock("test-user");
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 25000);
        QVERIFY2(page.hasPage(), qPrintable(page.error()));
        QVERIFY(!page.passwordRequired()); QVERIFY(!page.canCopy());
        page.selectAll(); QVERIFY(page.selectedText().isEmpty());
        page.goToPage(2);
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 25000);
        QCOMPARE(page.currentPage(), 2); QVERIFY(page.hasPage());
    }
    void thumbnailsCacheRegionsAndRange() {
        PdfPage page;
        page.open(QUrl::fromLocalFile(pdf));
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(), 25000);
        page.requestThumbnail(2);
        QTRY_VERIFY_WITH_TIMEOUT(page.thumbnails().contains("2"), 25000);
        const auto data=page.thumbnails()["2"].toString().section(',',1).toLatin1();
        const auto image=QImage::fromData(QByteArray::fromBase64(data));
        QVERIFY(!image.isNull()); QVERIFY(image.width()<=256 && image.height()<=256);
        page.selectPageRange(1,2);
        QTRY_VERIFY_WITH_TIMEOUT(!page.auxiliaryBusy(), 45000);
        QVERIFY2(page.selectedText().contains("Quickshell") && page.selectedText().contains("Second page"),qPrintable(page.auxiliaryError()+page.selectedText()));
        page.goToPage(2);
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(),25000);
        page.goToPage(1);
        QVERIFY2(!page.busy(), "Previously rendered page must be cached");
        QVERIFY(page.hasPage());
        page.setRenderScale(4);
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(),25000);
        page.setWidth(page.pageWidth()*4*96/72); page.setHeight(page.pageHeight()*4*96/72);
        page.requestRegion(QRectF(100,100,800,600));
        QTRY_VERIFY_WITH_TIMEOUT(!page.regionRect().isEmpty(),25000);
        QVERIFY2(page.auxiliaryError().isEmpty(),qPrintable(page.auxiliaryError()));
        QVERIFY(qAbs(page.regionRect().x()-100)<1);
        QVERIFY(qAbs(page.regionRect().width()-800)<1);
        PdfRegion detail; detail.setSourcePage(&page); detail.setWidth(800); detail.setHeight(600);
        QImage region(800,600,QImage::Format_RGB32); region.fill(Qt::magenta);
        QPainter painter(&region); detail.paint(&painter); painter.end();
        QVERIFY(region.pixelColor(799,599)!=QColor(Qt::magenta));
        page.rotatePage(1);
        QVERIFY(page.regionRect().isEmpty());
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(),25000);
    }
    void ocrScannedDocument() {
        const QString scanned=dir.filePath("scanned.pdf");
        {
            QImage image(1400,300,QImage::Format_RGB32); image.fill(Qt::white);
            QPainter text(&image); text.setPen(Qt::black); text.setFont(QFont("sans-serif",64));
            text.drawText(QRect(20,20,1360,260),Qt::AlignCenter,"SCANNED DOCUMENT"); text.end();
            QPdfWriter writer(scanned); writer.setResolution(72); writer.setPageSize(QPageSize(QPageSize::A4));
            QPainter painter(&writer); painter.drawImage(QRect(20,70,520,112),image); painter.end();
        }
        PdfPage page;
        page.open(QUrl::fromLocalFile(scanned));
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(),25000);
        page.selectAll(); QVERIFY(page.selectedText().isEmpty());
        page.setOcrEnabled(true);
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(),45000);
        QVERIFY2(page.error().isEmpty(),qPrintable(page.error()));
        page.selectAll(); QVERIFY2(page.selectedText().contains("SCANNED",Qt::CaseInsensitive),qPrintable(page.selectedText()));
        page.search("scanned document");
        QTRY_VERIFY_WITH_TIMEOUT(!page.searching(),45000);
        QCOMPARE(page.matchCount(),1);
        page.selectPageRange(1,1);
        QTRY_VERIFY_WITH_TIMEOUT(!page.auxiliaryBusy(),45000);
        QVERIFY(page.selectedText().contains("SCANNED",Qt::CaseInsensitive));
        page.setOcrLanguage("missingmodel");
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(),45000);
        QVERIFY(!page.error().isEmpty());
        page.setOcrEnabled(false);
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(),25000);
        QVERIFY(page.hasPage()); QVERIFY(page.error().isEmpty());
    }
    void documentOutline() {
        const QByteArray one="BT /F1 20 Tf 50 700 Td (Chapter One) Tj ET";
        const QByteArray two="BT /F1 20 Tf 50 700 Td (Chapter Two) Tj ET";
        const QList<QByteArray> objects={
            "<< /Type /Catalog /Pages 2 0 R /Outlines 7 0 R >>",
            "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 6 0 R >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 9 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Length "+QByteArray::number(one.size())+" >>\nstream\n"+one+"\nendstream",
            "<< /Type /Outlines /First 8 0 R /Last 8 0 R /Count 1 >>",
            "<< /Title (Chapter Two) /Parent 7 0 R /Dest [4 0 R /Fit] >>",
            "<< /Length "+QByteArray::number(two.size())+" >>\nstream\n"+two+"\nendstream"};
        QByteArray data="%PDF-1.4\n"; QList<int> offsets;
        for (int i=0;i<objects.size();++i) { offsets.append(data.size()); data+=QByteArray::number(i+1)+" 0 obj\n"+objects[i]+"\nendobj\n"; }
        const int start=data.size();
        data+="xref\n0 10\n0000000000 65535 f \n";
        for (int offset:offsets) data+=QByteArray::number(offset).rightJustified(10,'0')+" 00000 n \n";
        data+="trailer\n<< /Size 10 /Root 1 0 R >>\nstartxref\n"+QByteArray::number(start)+"\n%%EOF\n";
        const QString name=dir.filePath("outline.pdf"); QFile file(name); QVERIFY(file.open(QIODevice::WriteOnly)); file.write(data); file.close();
        PdfPage page; page.open(QUrl::fromLocalFile(name));
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(),25000);
        QVERIFY2(page.hasPage(),qPrintable(page.error()));
        QCOMPARE(page.outline().size(),1);
        QCOMPARE(page.outline().first().toMap()["title"].toString(),QString("Chapter Two"));
        QCOMPARE(page.outline().first().toMap()["page"].toInt(),2);
        page.goToPage(page.outline().first().toMap()["page"].toInt());
        QTRY_VERIFY_WITH_TIMEOUT(!page.busy(),25000);
        page.selectAll(); QVERIFY(page.selectedText().contains("Chapter Two"));
    }
    void sandbox() {
        QFile file(pdf); QVERIFY(file.open(QIODevice::ReadOnly));
        int fd = file.handle();
        QProcess p;
        p.setChildProcessModifier([fd] { if (dup2(fd, 3) < 0 || fcntl(3,F_SETFD,0) < 0) _exit(126); });
        p.start("/usr/bin/bwrap", sandboxArguments(qEnvironmentVariable("PDF_VIEW_PROBE")));
        QVERIFY(p.waitForFinished(10000));
        QCOMPARE(p.exitStatus(), QProcess::NormalExit);
        QVERIFY2(p.exitCode() == 0, p.readAllStandardError().constData());
        QCOMPARE(p.readAllStandardOutput().trimmed(), QByteArray("isolated"));
    }
};
QTEST_MAIN(Tests)
#include "test.moc"

#include "pdfpage.h"
#include "sandbox.h"
#include <QtTest>
#include <QPdfWriter>
#include <QPainter>
#include <QTemporaryDir>
#include <QFile>
#include <fcntl.h>
#include <unistd.h>

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

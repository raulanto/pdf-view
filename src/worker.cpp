#include <QImage>
#include <QGuiApplication>
#include <QFile>
#include <QtEndian>
#include <poppler-qt6.h>
#include <sys/resource.h>
#include <cmath>

int main(int argc, char **argv) {
    const rlimit memory {1024ULL*1024*1024, 1024ULL*1024*1024};
    const rlimit cpu {10, 10};
    const rlimit core {0, 0};
    if (setrlimit(RLIMIT_AS, &memory) || setrlimit(RLIMIT_CPU, &cpu) || setrlimit(RLIMIT_CORE, &core)) return 10;
    QGuiApplication app(argc, argv);
    auto doc = Poppler::Document::load("/document.pdf");
    if (!doc || doc->isLocked() || doc->numPages() < 1 || doc->numPages() > 1000000) return 2;
    auto page = doc->page(0);
    if (!page) return 3;
    const QSizeF size = page->pageSizeF();
    if (!std::isfinite(size.width()) || !std::isfinite(size.height()) || size.width() <= 0 || size.height() <= 0) return 4;
    const double dpi = qMin(144.0, 2000.0*72.0/qMax(size.width(), size.height()));
    doc->setRenderHint(Poppler::Document::Antialiasing);
    doc->setRenderHint(Poppler::Document::TextAntialiasing);
    QImage image = page->renderToImage(dpi, dpi).convertToFormat(QImage::Format_RGBA8888);
    if (image.isNull() || image.width() > 2048 || image.height() > 2048) return 5;
    QByteArray header(20, '\0');
    header.replace(0, 4, "PDF1");
    qToLittleEndian<quint32>(image.width(), header.data()+4);
    qToLittleEndian<quint32>(image.height(), header.data()+8);
    qToLittleEndian<quint32>(doc->numPages(), header.data()+12);
    qToLittleEndian<quint32>(image.sizeInBytes(), header.data()+16);
    QFile out;
    if (!out.open(stdout, QIODevice::WriteOnly)) return 6;
    if (out.write(header) != header.size() || out.write(reinterpret_cast<const char *>(image.constBits()), image.sizeInBytes()) != image.sizeInBytes()) return 7;
    return out.flush() ? 0 : 8;
}

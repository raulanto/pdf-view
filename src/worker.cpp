#include <QImage>
#include <QGuiApplication>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QtEndian>
#include <poppler-qt6.h>
#include <sys/resource.h>
#include <cmath>

static QJsonArray rectangle(const QRectF &r) { return {r.x(), r.y(), r.width(), r.height()}; }
static int respond(const QJsonObject &object, const QImage &image = {}) {
    const QByteArray json = QJsonDocument(object).toJson(QJsonDocument::Compact);
    if (json.size() > 8*1024*1024) return 9;
    QByteArray header("PDF2", 4); header.resize(8);
    qToLittleEndian<quint32>(json.size(), header.data()+4);
    QFile out;
    if (!out.open(stdout, QIODevice::WriteOnly)) return 6;
    if (out.write(header) != header.size() || out.write(json) != json.size()) return 7;
    if (!image.isNull() && out.write(reinterpret_cast<const char *>(image.constBits()), image.sizeInBytes()) != image.sizeInBytes()) return 7;
    return out.flush() ? 0 : 8;
}
int main(int argc, char **argv) {
    const rlimit memory {1024ULL*1024*1024, 1024ULL*1024*1024};
    const rlimit cpu {20, 20}, core {0, 0};
    if (setrlimit(RLIMIT_AS, &memory) || setrlimit(RLIMIT_CPU, &cpu) || setrlimit(RLIMIT_CORE, &core)) return 10;
    QGuiApplication app(argc, argv);
    QFile in; if (!in.open(stdin, QIODevice::ReadOnly)) return 11;
    const auto requestBytes = in.read(16385);
    if (requestBytes.size() > 16384) return 11;
    QJsonParseError parseError;
    const auto requestDoc = QJsonDocument::fromJson(requestBytes, &parseError);
    if (parseError.error != QJsonParseError::NoError || !requestDoc.isObject()) return 11;
    const auto request = requestDoc.object();
    const QString operation = request["op"].toString();
    if (operation != "render" && operation != "search") return 11;
    const auto password = request["password"].toString().toLatin1();
    auto doc = Poppler::Document::load("/document.pdf", password, password);
    if (!doc) return respond({{"error", "No se pudo leer el PDF."}});
    if (doc->isLocked()) return respond({{"locked", true}});
    if (doc->numPages() < 1 || doc->numPages() > 1000000) return 2;
    if (operation == "search") {
        const QString query = request["query"].toString();
        if (query.isEmpty() || query.size() > 256) return 11;
        QJsonArray matches;
        bool truncated = false;
        for (int i = 0; i < doc->numPages(); ++i) {
            auto page = doc->page(i);
            if (!page) return respond({{"error", "No se pudo buscar en una página."}});
            for (const auto &rect : page->search(query, Poppler::Page::IgnoreCase)) {
                if (matches.size() == 2000) { truncated = true; break; }
                matches.append(QJsonObject{{"page", i+1}, {"rect", rectangle(rect)}});
            }
            if (truncated) break;
        }
        return respond({{"matches", matches}, {"truncated", truncated}});
    }
    const int number = request["page"].toInt(1), rotation = request["rotation"].toInt();
    const double requestedDpi = request["dpi"].toDouble(144);
    if (number < 1 || number > doc->numPages() || rotation < 0 || rotation > 3 ||
        !std::isfinite(requestedDpi) || requestedDpi < 18 || requestedDpi > 768) return 11;
    auto page = doc->page(number-1);
    if (!page) return 3;
    const QSizeF size = page->pageSizeF();
    if (!std::isfinite(size.width()) || !std::isfinite(size.height()) || size.width() <= 0 || size.height() <= 0 || size.width() > 100000 || size.height() > 100000) return 4;
    const double dpi = qMin(requestedDpi, 4000.0*72.0/qMax(size.width(), size.height()));
    doc->setRenderHint(Poppler::Document::Antialiasing);
    doc->setRenderHint(Poppler::Document::TextAntialiasing);
    const QImage image = page->renderToImage(dpi, dpi, -1,-1,-1,-1, Poppler::Page::Rotation(rotation)).convertToFormat(QImage::Format_RGBA8888);
    if (image.isNull() || image.width() > 4096 || image.height() > 4096) return 5;
    QJsonArray words;
    if (doc->okToCopy()) {
        for (const auto &box : page->textList()) {
            if (words.size() == 50000) return respond({{"error", "La página supera el límite de texto."}});
            const QString text = box->text();
            if (text.size() > 4096) return 9;
            words.append(QJsonObject{{"text", text}, {"rect", rectangle(box->boundingBox())}, {"space", box->hasSpaceAfter()}});
        }
    }
    return respond({{"width", image.width()}, {"height", image.height()}, {"pages", doc->numPages()},
        {"page", number}, {"rotation", rotation}, {"pageWidth", size.width()}, {"pageHeight", size.height()},
        {"words", words}, {"canCopy", doc->okToCopy()}}, image);
}

#include <QImage>
#include <QGuiApplication>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QtEndian>
#include <poppler-qt6.h>
#include <poppler-link.h>
#include <tesseract/baseapi.h>
#include <tesseract/resultiterator.h>
#include <QRegularExpression>
#include <stdexcept>
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
struct Word { QString text; QRectF rect; bool space; };
static std::vector<Word> wordsFor(Poppler::Page &page, bool ocr, const QString &language) {
    std::vector<Word> words;
    for (const auto &box : page.textList()) {
        if (words.size() == 50000 || box->text().size() > 4096) throw std::runtime_error("La página supera el límite de texto.");
        words.push_back({box->text(), box->boundingBox(), box->hasSpaceAfter()});
    }
    if (!words.empty() || !ocr) return words;
    const auto size=page.pageSizeF();
    if (!std::isfinite(size.width()) || !std::isfinite(size.height()) || size.width()<=0 || size.height()<=0) throw std::runtime_error("Tamaño inválido para OCR.");
    const double dpi=std::min(220.0, 2600.0*72/std::max(size.width(),size.height()));
    const auto image=page.renderToImage(dpi,dpi).convertToFormat(QImage::Format_RGB888);
    if (image.isNull()) throw std::runtime_error("No se pudo preparar el OCR.");
    tesseract::TessBaseAPI engine;
    if (engine.Init("/usr/share/tessdata",language.toLatin1().constData())) throw std::runtime_error("Modelo OCR no disponible. Instala tesseract-data para el idioma elegido.");
    engine.SetImage(image.constBits(),image.width(),image.height(),3,image.bytesPerLine());
    engine.SetSourceResolution(qRound(dpi));
    if (engine.Recognize(nullptr)) throw std::runtime_error("Falló el reconocimiento OCR.");
    std::unique_ptr<tesseract::ResultIterator> iterator(engine.GetIterator());
    if (iterator) do {
        std::unique_ptr<char[]> text(iterator->GetUTF8Text(tesseract::RIL_WORD));
        int x1,y1,x2,y2;
        if (!text || !iterator->BoundingBox(tesseract::RIL_WORD,&x1,&y1,&x2,&y2)) continue;
        const QString value=QString::fromUtf8(text.get()).trimmed();
        if (words.size()==50000 || value.size()>4096) throw std::runtime_error("El OCR supera el límite de texto.");
        if (!value.isEmpty()) words.push_back({value,QRectF(x1*72/dpi,y1*72/dpi,(x2-x1)*72/dpi,(y2-y1)*72/dpi),true});
    } while (iterator->Next(tesseract::RIL_WORD));
    return words;
}
static void outlineItems(const QVector<Poppler::OutlineItem> &items, int depth, QJsonArray &out) {
    if (depth>16) return;
    for (const auto &item : items) {
        if (out.size()>=2048) return;
        const auto destination=item.destination();
        const int page=destination && item.externalFileName().isEmpty() && item.uri().isEmpty() ? destination->pageNumber() : 0;
        out.append(QJsonObject{{"title",item.name().left(512)},{"page",page},{"depth",depth}});
        if (item.hasChildren()) outlineItems(item.children(),depth+1,out);
    }
}
static QString joined(const std::vector<Word> &words, int begin, int end) {
    QString text;
    for (int i=begin; i<=end && i<int(words.size()); ++i) {
        text+=words[i].text;
        if (text.size()>2*1024*1024) throw std::runtime_error("La selección supera el límite de texto.");
        if (i<end && i+1<int(words.size())) {
            if (qAbs(words[i+1].rect.center().y()-words[i].rect.center().y())>words[i].rect.height()/2) text+='\n';
            else if (words[i].space) text+=' ';
        }
    }
    return text;
}
int main(int argc, char **argv) try {
    const rlimit memory {1024ULL*1024*1024, 1024ULL*1024*1024};
    const rlimit cpu {30, 30}, core {0, 0};
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
    if (operation != "render" && operation != "search" && operation != "thumbnail" && operation != "extract" && operation != "region") return 11;
    const bool ocr=request["ocr"].toBool();
    const QString language=request["language"].toString("eng");
    if (!QRegularExpression("^[a-z_+]{1,32}$").match(language).hasMatch()) return 11;
    const auto password = request["password"].toString().toLatin1();
    auto doc = Poppler::Document::load("/document.pdf", password, password);
    if (!doc) return respond({{"error", "No se pudo leer el PDF."}});
    if (doc->isLocked()) return respond({{"locked", true}});
    if (doc->numPages() < 1 || doc->numPages() > 1000000) return 2;
    if (operation == "extract") {
        if (!doc->okToCopy()) return respond({{"error","El documento no permite copiar texto."}});
        const int first=request["first"].toInt(), last=request["last"].toInt();
        if (first<1 || last<first || last>doc->numPages() || last-first>=100) return respond({{"error","Selecciona un rango de hasta 100 páginas."}});
        QString text;
        for (int i=first; i<=last; ++i) {
            auto page=doc->page(i-1); if (!page) return 3;
            const auto words=wordsFor(*page,ocr,language);
            const int begin=i==first ? request["firstWord"].toInt(0) : 0;
            const int end=i==last ? request["lastWord"].toInt(int(words.size())-1) : int(words.size())-1;
            if (begin<0 || end < -1 || begin>int(words.size()) || end>=int(words.size())) return 11;
            if (i!=first) text+="\n\n";
            text+=joined(words,begin,end);
            if (text.size()>2*1024*1024) return respond({{"error","La selección supera 2 Mi caracteres."}});
        }
        return respond({{"text",text}});
    }
    if (operation == "search") {
        const QString query=request["query"].toString();
        if (query.isEmpty() || query.size()>256) return 11;
        QJsonArray matches; bool truncated=false;
        for (int i=0; i<doc->numPages(); ++i) {
            auto page=doc->page(i); if (!page) return 3;
            auto found=page->search(query,Poppler::Page::IgnoreCase);
            if (ocr && doc->okToCopy() && page->textList().empty()) {
                const auto words=wordsFor(*page,true,language);
                QString text; QVector<int> starts;
                for (const auto &word: words) { starts.append(text.size()); text+=word.text+' '; }
                int from=0, at;
                while ((at=text.indexOf(query,from,Qt::CaseInsensitive))>=0) {
                    QRectF rect;
                    for (int j=0;j<int(words.size());++j) if (starts[j]<at+query.size() && starts[j]+words[j].text.size()>at) rect=rect.united(words[j].rect);
                    if (!rect.isEmpty()) found.append(rect);
                    if (found.size()>2000) break;
                    from=at+query.size();
                }
            }
            for (const auto &rect:found) {
                if (matches.size()==2000) { truncated=true; break; }
                matches.append(QJsonObject{{"page",i+1},{"rect",rectangle(rect)}});
            }
            if (truncated) break;
        }
        return respond({{"matches",matches},{"truncated",truncated}});
    }
    const int number = request["page"].toInt(1), rotation = request["rotation"].toInt();
    const double requestedDpi = request["dpi"].toDouble(144);
    if (number < 1 || number > doc->numPages() || rotation < 0 || rotation > 3 ||
        !std::isfinite(requestedDpi) || requestedDpi < 18 || requestedDpi > 768) return 11;
    auto page = doc->page(number-1);
    if (!page) return 3;
    const QSizeF size = page->pageSizeF();
    if (!std::isfinite(size.width()) || !std::isfinite(size.height()) || size.width() <= 0 || size.height() <= 0 || size.width() > 100000 || size.height() > 100000) return 4;
    const double dpi = operation=="region" ? requestedDpi : qMin(requestedDpi, (operation=="thumbnail" ? 220.0 : 2000.0)*72.0/qMax(size.width(), size.height()));
    doc->setRenderHint(Poppler::Document::Antialiasing);
    doc->setRenderHint(Poppler::Document::TextAntialiasing);
    QRect slice(-1,-1,-1,-1);
    if (operation=="region") {
        const auto r=request["region"].toArray();
        if (r.size()!=4) return 11;
        double values[4];
        for (int i=0;i<4;++i) { values[i]=r[i].toDouble(-1); if (!std::isfinite(values[i]) || values[i]<0 || values[i]>1) return 11; }
        if (values[2]<=0 || values[3]<=0 || values[0]+values[2]>1.001 || values[1]+values[3]>1.001) return 11;
        const QSizeF rotated=rotation%2 ? QSizeF(size.height(),size.width()) : size;
        slice=QRect(qRound(values[0]*rotated.width()*dpi/72),qRound(values[1]*rotated.height()*dpi/72),
                    qMax(1,qRound(values[2]*rotated.width()*dpi/72)),qMax(1,qRound(values[3]*rotated.height()*dpi/72)));
        if (slice.width()>2048 || slice.height()>2048) return 11;
    }
    const QImage image = page->renderToImage(dpi,dpi,slice.x(),slice.y(),slice.width(),slice.height(),Poppler::Page::Rotation(rotation)).convertToFormat(QImage::Format_RGBA8888);
    if (image.isNull() || image.width() > 4096 || image.height() > 4096) return 5;
    QJsonArray words;
    if (operation=="render" && doc->okToCopy()) {
        for (const auto &word:wordsFor(*page,ocr,language)) words.append(QJsonObject{{"text",word.text},{"rect",rectangle(word.rect)},{"space",word.space}});
    }
    QJsonObject meta{{"width",image.width()},{"height",image.height()},{"pages",doc->numPages()},
        {"page",number},{"rotation",rotation},{"pageWidth",size.width()},{"pageHeight",size.height()},
        {"words",words},{"canCopy",doc->okToCopy()}};
    if (request["outline"].toBool()) { QJsonArray items; outlineItems(doc->outline(),0,items); meta["outline"]=items; }
    return respond(meta,image);
} catch (const std::exception &error) {
    return respond({{"error",QString::fromUtf8(error.what()).left(256)}});
}

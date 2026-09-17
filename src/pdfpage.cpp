#include "pdfpage.h"
#include "sandbox.h"
#include <QCursor>
#include <QBuffer>
#include <QRegularExpression>
#include <QFile>
#include <QFileInfo>
#include <QPainter>
#include <QMouseEvent>
#include <QGuiApplication>
#include <QClipboard>
#include <QJsonDocument>
#include <QJsonArray>
#include <QtEndian>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <cmath>
#include <memory>
#include <limits>

namespace {
constexpr qsizetype MaxMetadata = 8*1024*1024;
constexpr qsizetype MaxOutput = 8 + MaxMetadata + 4096LL*4096*4;
bool readRect(const QJsonValue &value, QRectF &result) {
    const auto a = value.toArray();
    if (a.size() != 4) return false;
    double v[4];
    for (int i=0; i<4; ++i) {
        if (!a[i].isDouble()) return false;
        v[i] = a[i].toDouble();
        if (!std::isfinite(v[i]) || std::abs(v[i]) > 100000) return false;
    }
    if (v[2] < 0 || v[3] < 0) return false;
    result = QRectF(v[0],v[1],v[2],v[3]);
    return true;
}
}
PdfPage::PdfPage(QQuickItem *parent) : QQuickPaintedItem(parent) {
    setTextureSize(QSize(1,1));
    setAcceptedMouseButtons(Qt::LeftButton);
    setCursor(Qt::IBeamCursor);
    m_regionTimer.setSingleShot(true);
    m_regionTimer.setInterval(180);
    connect(&m_regionTimer,&QTimer::timeout,this,&PdfPage::pumpAuxiliary);
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(150);
    connect(&m_debounce, &QTimer::timeout, this, &PdfPage::render);
    connect(this, &PdfPage::highlightColorChanged, this, [this] { update(); });
}
PdfPage::~PdfPage() {
    cancel(m_render); cancel(m_search); cancel(m_aux);
    if (m_fd >= 0) ::close(m_fd);
}
void PdfPage::cancel(QProcess *&process) {
    if (!process) return;
    auto old = process; process = nullptr;
    old->disconnect(this);
    if (old->state() == QProcess::NotRunning) old->deleteLater();
    else {
        connect(old, &QProcess::finished, old, &QObject::deleteLater);
        old->kill();
    }
}
// ponytail: each bounded request reopens the PDF; retain a worker only if large-document profiling justifies it.
QProcess *&PdfPage::slotFor(int kind) { return kind==2 ? m_aux : kind==1 ? m_search : m_render; }
void PdfPage::startJob(int kind, QJsonObject request) {
    auto &slot = slotFor(kind);
    cancel(slot);
    if (m_fd < 0) return;
    if (kind==2) m_auxError.clear();
    request["ocr"]=m_ocr; request["language"]=m_language;
    struct stat info {};
    if (fstat(m_fd,&info)==0) {
        const qint64 stamp=qint64(info.st_mtim.tv_sec)*1000000000LL+info.st_mtim.tv_nsec;
        if (stamp!=m_stamp) { m_cache.clear(); m_stamp=stamp; }
    }
    const QString requestOp=request["op"].toString();
    QJsonObject keyRequest=request; keyRequest.remove("outline");
    const QString cacheKey=QString::fromUtf8(QJsonDocument(keyRequest).toJson(QJsonDocument::Compact));
    request["cacheKey"]=cacheKey;
    if ((requestOp=="render" || requestOp=="region") && m_cache.contains(cacheKey)) {
        const auto output=*m_cache.object(cacheKey);
        applyResponse(kind,request,output,{}); return;
    }
    auto process = new QProcess(this);
    process->setProperty("request",request);
    slot = process;
    auto output = std::make_shared<QByteArray>();
    QProcess::UnixProcessParameters parameters;
    parameters.flags = QProcess::UnixProcessFlag::CloseFileDescriptors;
    parameters.lowestFileDescriptorToClose = 4;
    process->setUnixProcessParameters(parameters);
    const int fd = m_fd;
    process->setChildProcessModifier([fd] {
        if (dup2(fd,3) < 0 || fcntl(3,F_SETFD,0) < 0) _exit(126);
        if (fd != 3) ::close(fd);
    });
    auto timer = new QTimer(process);
    timer->setSingleShot(true);
    timer->setInterval(kind || m_ocr ? 45000 : 20000);
    connect(timer, &QTimer::timeout, this, [this, kind, process] {
        finish(kind, process, {}, "La operación excedió el tiempo permitido.");
    });
    connect(process, &QProcess::readyReadStandardOutput, this, [this, process, output, kind, requestOp] {
        const qsizetype limit = kind==1 || requestOp=="extract" ? 8+MaxMetadata : MaxOutput;
        if (process->bytesAvailable() > limit-output->size()) {
            finish(kind, process, {}, "Respuesta del motor demasiado grande."); return;
        }
        *output += process->readAllStandardOutput();
    });
    connect(process, &QProcess::readyReadStandardError, this, [process] { process->readAllStandardError(); });
    connect(process, &QProcess::errorOccurred, this, [this, process, kind](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) finish(kind, process, {}, "No se pudo iniciar el motor aislado.");
    });
    connect(process, &QProcess::finished, this, [this, process, output, kind, timer, requestOp](int code, QProcess::ExitStatus status) {
        timer->stop();
        // readyRead is normally emitted first, but account for a final buffered chunk.
        const qsizetype limit = kind==1 || requestOp=="extract" ? 8+MaxMetadata : MaxOutput;
        if (process->bytesAvailable() > limit-output->size()) {
            finish(kind, process, {}, "Respuesta del motor demasiado grande."); return;
        }
        *output += process->readAllStandardOutput();
        finish(kind, process, *output, code == 0 && status == QProcess::NormalExit ? QString() : "No se pudo procesar el PDF en aislamiento.");
    });
    request["password"] = m_password;
    const auto input = QJsonDocument(request).toJson(QJsonDocument::Compact);
    connect(process, &QProcess::started, this, [process, input] { process->write(input); process->closeWriteChannel(); });
    process->start("/usr/bin/bwrap", sandboxArguments(qEnvironmentVariable("PDF_VIEW_WORKER")));
    timer->start();
    if (kind==2) emit auxiliaryChanged(); else if (kind==1) emit searchChanged(); else emit changed();
}
void PdfPage::finish(int kind, QProcess *process, const QByteArray &output, const QString &failure) {
    auto &slot=slotFor(kind);
    if (slot!=process) return;
    const auto request=process->property("request").value<QJsonObject>();
    cancel(slot);
    applyResponse(kind,request,output,failure);
}
void PdfPage::applyResponse(int kind, const QJsonObject &request, const QByteArray &output, const QString &failure) {
    const QString operation=request["op"].toString();
    QString &error=kind==2 ? m_auxError : kind==1 ? m_searchError : m_error;
    auto notify=[&] { if (kind==2) emit auxiliaryChanged(); else if (kind==1) emit searchChanged(); else emit changed(); };
    auto reject=[&](const QString &message) {
        error=message;
        if (operation=="thumbnail") m_failedThumbnails.insert(request["page"].toInt());
        notify();
        if (kind==2) QTimer::singleShot(0,this,&PdfPage::pumpAuxiliary);
    };
    if (!failure.isEmpty()) { reject(failure); return; }
    if (output.size() < 8 || output.first(4) != "PDF2") { reject("Respuesta inválida del motor."); return; }
    const quint32 length = qFromLittleEndian<quint32>(output.constData()+4);
    if (length > MaxMetadata || output.size() < 8+length) { reject("Metadatos inválidos."); return; }
    QJsonParseError parseError;
    const auto document = QJsonDocument::fromJson(output.mid(8,length), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) { reject("Metadatos inválidos."); return; }
    const auto meta = document.object();
    if (meta["locked"].toBool()) {
        if (output.size() != 8+length) { reject("Respuesta inválida."); return; }
        m_locked = true;
        reject("Introduce la contraseña del documento."); return;
    }
    if (meta.contains("error")) { reject(meta["error"].toString().left(256)); return; }
    if (operation=="extract") {
        if (!meta["text"].isString() || meta["text"].toString().size()>2*1024*1024 || output.size()!=8+length) { reject("Selección inválida."); return; }
        m_anchor=m_cursor=-1; m_rangeText=meta["text"].toString();
        emit selectionChanged(); emit auxiliaryChanged(); update();
        QTimer::singleShot(0,this,&PdfPage::pumpAuxiliary); return;
    }
    if (kind==1) {
        const auto matches = meta["matches"].toArray();
        if (!meta["matches"].isArray() || matches.size() > 2000 || output.size() != 8+length) { reject("Búsqueda inválida."); return; }
        QVector<Match> validated;
        for (const auto &entry : matches) {
            const auto object = entry.toObject();
            const int number = object["page"].toInt();
            QRectF rect;
            if (number < 1 || number > m_pages || !readRect(object["rect"], rect)) { reject("Resultado de búsqueda inválido."); return; }
            validated.append({number, rect});
        }
        m_matches = validated;
        m_match = -1;
        m_truncated = meta["truncated"].toBool();
        emit searchChanged();
        if (!m_matches.isEmpty()) nextMatch(1);
        return;
    }
    const int w=meta["width"].toInt(), h=meta["height"].toInt(), pages=meta["pages"].toInt();
    const double pw=meta["pageWidth"].toDouble(), ph=meta["pageHeight"].toDouble();
    if (w<=0 || h<=0 || w>4096 || h>4096 || pages<1 || pages>1000000 ||
        !std::isfinite(pw) || !std::isfinite(ph) || pw<=0 || ph<=0 || pw>100000 || ph>100000 ||
        request["page"].toInt()>pages || meta["page"].toInt()!=request["page"].toInt() || meta["rotation"].toInt()!=request["rotation"].toInt() ||
        output.size()!=8+length+quint64(w)*h*4 || !meta["words"].isArray()) {
        reject("Dimensiones o tamaño de respuesta inválidos."); return;
    }
    if (operation=="thumbnail" || operation=="region") {
        const QImage image=QImage(reinterpret_cast<const uchar *>(output.constData()+8+length),w,h,w*4,QImage::Format_RGBA8888).copy();
        if (operation=="thumbnail") {
            if (w>256 || h>256) { reject("Miniatura demasiado grande."); return; }
            QByteArray png; QBuffer buffer(&png); buffer.open(QIODevice::WriteOnly); image.save(&buffer,"PNG");
            const int number=request["page"].toInt();
            m_thumbnails[QString::number(number)]="data:image/png;base64,"+QString::fromLatin1(png.toBase64());
            m_thumbnailOrder.enqueue(number);
            while (m_thumbnailOrder.size()>48) m_thumbnails.remove(QString::number(m_thumbnailOrder.dequeue()));
            emit thumbnailsChanged();
        } else {
            if (w>2048 || h>2048) { reject("Región demasiado grande."); return; }
            QRectF region;
            if (!readRect(request["region"],region)) { reject("Región inválida."); return; }
            if (request["page"].toInt()==m_page && request["rotation"].toInt()==m_rotation) {
                m_region=region; m_regionImage=image; emit regionChanged();
            }
            m_cache.insert(request["cacheKey"].toString(),new QByteArray(output),output.size());
        }
        emit auxiliaryChanged(); QTimer::singleShot(0,this,&PdfPage::pumpAuxiliary); return;
    }
    if (meta.contains("outline")) {
        const auto items=meta["outline"].toArray();
        if (items.size()>2048) { reject("Índice demasiado grande."); return; }
        QVariantList validated;
        for (const auto &entry:items) {
            const auto item=entry.toObject();
            const int page=item["page"].toInt(-1),depth=item["depth"].toInt(-1);
            if (!item["title"].isString() || item["title"].toString().size()>512 || page<0 || page>pages || depth<0 || depth>16) { reject("Índice inválido."); return; }
            validated.append(item.toVariantMap());
        }
        m_outline=validated; m_outlineLoaded=true; emit outlineChanged();
    }
    const auto words = meta["words"].toArray();
    if (words.size()>50000) { reject("Demasiado texto en la página."); return; }
    QVector<Word> validated;
    for (const auto &entry : words) {
        const auto object = entry.toObject();
        QRectF rect;
        if (!object["text"].isString() || object["text"].toString().size()>4096 || !readRect(object["rect"],rect)) {
            reject("Texto de página inválido."); return;
        }
        validated.append({object["text"].toString(), rect.intersected(QRectF(0,0,pw,ph)), object["space"].toBool()});
    }
    m_image = QImage(reinterpret_cast<const uchar *>(output.constData()+8+length), w,h,w*4,QImage::Format_RGBA8888).copy();
    bool sameText=m_words.size()==validated.size();
    if (sameText) for (int i=0;i<m_words.size();++i) if (m_words[i].text!=validated[i].text) { sameText=false; break; }
    if (!sameText) clearSelection();
    setTextureSize(m_image.size());
    const bool geometryDiffers = m_size != QSizeF(pw,ph);
    m_size = QSizeF(pw,ph); m_pages = pages; m_words = validated;
    m_canCopy = meta["canCopy"].toBool(); m_locked = false;
    m_cache.insert(request["cacheKey"].toString(),new QByteArray(output),output.size());
    if (geometryDiffers) emit geometryChanged();
    update(); emit changed(); revealCurrentMatch();
    QTimer::singleShot(0,this,&PdfPage::pumpAuxiliary);
}
void PdfPage::open(const QUrl &url) {
    m_debounce.stop(); cancel(m_render); cancel(m_search); cancel(m_aux);
    if (m_fd >= 0) ::close(m_fd);
    m_cache.clear(); m_outline.clear(); m_outlineLoaded=false;
    m_thumbnails.clear(); m_thumbnailQueue.clear(); m_thumbnailOrder.clear(); m_failedThumbnails.clear();
    m_auxError.clear(); m_rangeText.clear(); m_selectionPage=0; resetRegion();
    emit outlineChanged(); emit thumbnailsChanged(); emit auxiliaryChanged();
    m_fd = -1; m_password.clear(); m_locked=false; m_canCopy=false;
    m_image={}; m_words.clear(); m_error.clear(); m_searchError.clear(); m_matches.clear();
    m_pages=0; m_page=1; m_rotation=0; m_match=-1; m_truncated=false;
    emit geometryChanged();
    clearSelection(); update(); emit searchChanged();
    if (!url.isLocalFile()) { m_error="Selecciona un archivo PDF local."; emit changed(); return; }
    const auto path=QFile::encodeName(url.toLocalFile());
    const int fd=::open(path.constData(),O_RDONLY|O_CLOEXEC|O_NONBLOCK);
    struct stat info {};
    if (fd<0 || fstat(fd,&info) || !S_ISREG(info.st_mode) || info.st_size>256LL*1024*1024) {
        if (fd>=0) ::close(fd);
        m_error="El archivo no es regular, no se puede leer o supera 256 MiB."; emit changed(); return;
    }
    const QString worker=qEnvironmentVariable("PDF_VIEW_WORKER");
    if (worker.isEmpty() || !QFileInfo(worker).isExecutable()) {
        ::close(fd); m_error="Motor no encontrado. Usa scripts/run.sh."; emit changed(); return;
    }
    m_fd=fd; render();
}
void PdfPage::unlock(const QString &password) {
    if (!m_locked || password.size()>1024) return;
    m_password=password; m_locked=false; render();
}
void PdfPage::render() {
    if (m_fd<0 || m_locked) return;
    m_debounce.stop(); m_error.clear();
    startJob(false, {{"op","render"},{"page",m_page},{"rotation",m_rotation},{"dpi",qBound(18.0,144*m_scale,768.0)},{"outline",!m_outlineLoaded}});
}
void PdfPage::setRenderScale(double scale) {
    if (!std::isfinite(scale)) return;
    scale=qBound(0.125,scale,4.0);
    if (qAbs(scale-m_scale)<0.02) return;
    resetRegion();
    m_scale=scale;
    if (m_fd>=0 && !m_locked) m_debounce.start();
    emit scaleChanged(); emit changed();
}
void PdfPage::goToPage(int number) {
    if (number<1 || number>m_pages || number==m_page) return;
    resetRegion();
    m_page=number; m_image={}; m_words.clear(); clearSelection(); update(); render();
}
void PdfPage::rotatePage(int steps) {
    if (m_pages==0) return;
    resetRegion();
    m_rotation=(m_rotation+(steps%4)+4)%4;
    emit geometryChanged();
    m_image={}; m_words.clear(); clearSelection(); update(); render();
}
void PdfPage::search(const QString &query) {
    cancel(m_search); m_searchError.clear(); m_matches.clear(); m_match=-1; m_truncated=false; update();
    if (query.isEmpty() || m_pages==0) { emit searchChanged(); return; }
    if (query.size()>256) { m_searchError="La búsqueda admite hasta 256 caracteres."; emit searchChanged(); return; }
    startJob(true, {{"op","search"},{"query",query}});
}
void PdfPage::nextMatch(int direction) {
    if (m_matches.isEmpty()) return;
    m_match=m_match<0 ? (direction<0 ? m_matches.size()-1 : 0) : (m_match+(direction<0?-1:1)+m_matches.size())%m_matches.size();
    if (m_page!=m_matches[m_match].page) goToPage(m_matches[m_match].page);
    else { update(); revealCurrentMatch(); }
    emit searchChanged();
}
void PdfPage::revealCurrentMatch() {
    if (m_match>=0 && m_matches[m_match].page==m_page && hasPage()) emit revealMatch(mapRect(m_matches[m_match].rect).center());
}
QRectF PdfPage::targetRect() const {
    QSizeF size(pageWidth(),pageHeight()); size.scale(boundingRect().size(),Qt::KeepAspectRatio);
    return QRectF(QPointF((width()-size.width())/2,(height()-size.height())/2),size);
}
QRectF PdfPage::mapRect(const QRectF &rect) const {
    const double w=m_size.width(), h=m_size.height();
    QRectF rotated=rect;
    if (m_rotation==1) rotated=QRectF(h-rect.bottom(),rect.left(),rect.height(),rect.width());
    if (m_rotation==2) rotated=QRectF(w-rect.right(),h-rect.bottom(),rect.width(),rect.height());
    if (m_rotation==3) rotated=QRectF(rect.top(),w-rect.right(),rect.height(),rect.width());
    const auto target=targetRect();
    return QRectF(target.x()+rotated.x()*target.width()/pageWidth(), target.y()+rotated.y()*target.height()/pageHeight(),
        rotated.width()*target.width()/pageWidth(),rotated.height()*target.height()/pageHeight());
}
void PdfPage::paint(QPainter *painter) {
    if (m_image.isNull()) return;
    painter->setRenderHint(QPainter::SmoothPixmapTransform);
    painter->drawImage(targetRect(),m_image);
    paintHighlights(painter);
}
void PdfPage::paintHighlights(QPainter *painter) {
    QColor fill=m_highlight; fill.setAlpha(75);
    painter->setPen(Qt::NoPen);
    for (int i=0; i<m_matches.size(); ++i) if (m_matches[i].page==m_page) {
        painter->fillRect(mapRect(m_matches[i].rect),fill);
        if (i==m_match) { painter->setPen(QPen(m_highlight,2)); painter->drawRect(mapRect(m_matches[i].rect)); painter->setPen(Qt::NoPen); }
    }
    if (m_anchor>=0 && m_cursor>=0) {
        fill.setAlpha(110);
        for (int i=qMin(m_anchor,m_cursor); i<=qMax(m_anchor,m_cursor); ++i) painter->fillRect(mapRect(m_words[i].rect),fill);
    }
}
int PdfPage::wordAt(QPointF point) const {
    int best=-1; double distance=std::numeric_limits<double>::max();
    for (int i=0; i<m_words.size(); ++i) {
        const auto rect=mapRect(m_words[i].rect);
        if (rect.contains(point)) return i;
        const double dx=std::max({rect.left()-point.x(),0.0,point.x()-rect.right()});
        const double dy=std::max({rect.top()-point.y(),0.0,point.y()-rect.bottom()});
        if (dx*dx+dy*dy<distance) { distance=dx*dx+dy*dy; best=i; }
    }
    return best;
}
void PdfPage::mousePressEvent(QMouseEvent *event) {
    forceActiveFocus();
    const int index=wordAt(event->position());
    if ((event->modifiers() & Qt::ShiftModifier) && m_selectionPage>0 && index>=0 && m_canCopy) {
        int first=m_selectionPage,last=m_page,firstWord=m_selectionWord,lastWord=index;
        if (first>last || (first==last && firstWord>lastWord)) { std::swap(first,last); std::swap(firstWord,lastWord); }
        cancelAuxiliary(); m_rangeText.clear(); m_auxError.clear();
        startJob(2,{{"op","extract"},{"first",first},{"last",last},{"firstWord",firstWord},{"lastWord",lastWord}});
        event->accept(); return;
    }
    clearSelection();
    if (m_canCopy && index>=0 && mapRect(m_words[index].rect).adjusted(-4,-4,4,4).contains(event->position())) {
        m_selectionPage=m_page; m_selectionWord=index;
        m_anchor=m_cursor=index; update(); emit selectionChanged(); event->accept();
    } else event->ignore();
}
void PdfPage::mouseMoveEvent(QMouseEvent *event) {
    if (m_anchor<0) { event->ignore(); return; }
    m_cursor=wordAt(event->position()); update(); emit selectionChanged(); event->accept();
}
void PdfPage::mouseReleaseEvent(QMouseEvent *event) { event->accept(); }
QString PdfPage::selectedText() const {
    if (!m_rangeText.isEmpty()) return m_rangeText;
    if (m_anchor<0 || m_cursor<0 || !m_canCopy) return {};
    QString text;
    for (int i=qMin(m_anchor,m_cursor); i<=qMax(m_anchor,m_cursor); ++i) {
        text+=m_words[i].text;
        if (i<qMax(m_anchor,m_cursor)) {
            if (qAbs(m_words[i+1].rect.center().y()-m_words[i].rect.center().y()) > m_words[i].rect.height()/2) text+='\n';
            else if (m_words[i].space) text+=' ';
        }
    }
    return text;
}
void PdfPage::clearSelection() { m_rangeText.clear(); m_anchor=m_cursor=-1; update(); emit selectionChanged(); }
void PdfPage::selectAll() {
    if (!m_canCopy || m_words.isEmpty()) return;
    m_selectionPage=m_page; m_selectionWord=0;
    m_anchor=0; m_cursor=m_words.size()-1; update(); emit selectionChanged();
}
void PdfPage::copySelection() {
    const QString text=selectedText();
    if (!text.isEmpty()) QGuiApplication::clipboard()->setText(text);
}

void PdfPage::setOcrEnabled(bool enabled) {
    if (m_ocr==enabled) return;
    m_ocr=enabled; m_selectionPage=0; clearSelection(); m_cache.clear(); search(""); cancelAuxiliary(); resetRegion();
    emit ocrChanged(); render();
}
void PdfPage::setOcrLanguage(const QString &language) {
    if (language==m_language) return;
    if (!QRegularExpression("^[a-z_+]{1,32}$").match(language).hasMatch()) {
        m_auxError="Idioma OCR inválido (ejemplo: eng o spa+eng)."; emit auxiliaryChanged(); return;
    }
    m_language=language; m_selectionPage=0; clearSelection(); m_cache.clear(); emit ocrChanged();
    if (m_ocr) { search(""); cancelAuxiliary(); render(); }
}
void PdfPage::requestThumbnail(int number) {
    if (number<1 || number>m_pages || m_thumbnails.contains(QString::number(number)) || m_failedThumbnails.contains(number) || m_thumbnailQueue.contains(number)) return;
    if (m_aux && m_aux->property("request").value<QJsonObject>()["op"]=="thumbnail" && m_aux->property("request").value<QJsonObject>()["page"].toInt()==number) return;
    if (m_thumbnailQueue.size()>=24) m_thumbnailQueue.dequeue();
    m_thumbnailQueue.enqueue(number); pumpAuxiliary();
}
void PdfPage::pumpAuxiliary() {
    if (m_aux || busy() || m_fd<0 || m_locked) return;
    if (!m_pendingRegion.isEmpty()) {
        const auto region=m_pendingRegion; m_pendingRegion={};
        const double dpi=std::min({144*m_scale,2040*72/(region.width()*pageWidth()),2040*72/(region.height()*pageHeight()),768.0});
        startJob(2,{{"op","region"},{"page",m_page},{"rotation",m_rotation},{"dpi",qMax(18.0,dpi)},
            {"region",QJsonArray{region.x(),region.y(),region.width(),region.height()}}});
    } else if (!m_thumbnailQueue.isEmpty()) {
        const int number=m_thumbnailQueue.dequeue();
        startJob(2,{{"op","thumbnail"},{"page",number},{"rotation",0},{"dpi",72}});
    }
}
void PdfPage::cancelAuxiliary() {
    if (m_aux) {
        const auto request=m_aux->property("request").value<QJsonObject>();
        if (request["op"]=="thumbnail") m_thumbnailQueue.prepend(request["page"].toInt());
    }
    cancel(m_aux); emit auxiliaryChanged();
}
void PdfPage::selectPageRange(int first, int last) {
    if (!m_canCopy) { m_auxError="El documento no permite copiar texto."; emit auxiliaryChanged(); return; }
    if (first<1 || last<first || last>m_pages || last-first>=100) { m_auxError="Selecciona un rango de hasta 100 páginas."; emit auxiliaryChanged(); return; }
    cancelAuxiliary(); clearSelection(); m_auxError.clear();
    startJob(2,{{"op","extract"},{"first",first},{"last",last}});
}
QRectF PdfPage::regionRect() const {
    if (m_regionImage.isNull()) return {};
    return QRectF(m_region.x()*width(),m_region.y()*height(),m_region.width()*width(),m_region.height()*height());
}
void PdfPage::resetRegion() {
    m_regionTimer.stop(); m_pendingRegion={}; m_region={}; m_regionImage={};
    if (m_aux && m_aux->property("request").value<QJsonObject>()["op"]=="region") cancel(m_aux);
    emit regionChanged();
}
void PdfPage::requestRegion(QRectF visible) {
    if (!hasPage() || width()<=0 || height()<=0 || m_scale<=1.25) return;
    visible=visible.intersected(boundingRect());
    if (visible.isEmpty()) return;
    const QRectF region(visible.x()/width(),visible.y()/height(),visible.width()/width(),visible.height()/height());
    if (region==m_region || region==m_pendingRegion) return;
    m_pendingRegion=region; m_regionTimer.start();
}
void PdfRegion::setSourcePage(PdfPage *source) {
    if (m_source==source) return;
    if (m_source) m_source->disconnect(this);
    m_source=source;
    if (source) {
        connect(source,&PdfPage::regionChanged,this,[this] {
            setTextureSize(m_source && !m_source->m_regionImage.isNull() ? m_source->m_regionImage.size() : QSize(1,1)); update();
        });
        connect(source,&PdfPage::selectionChanged,this,[this] { update(); });
        connect(source,&PdfPage::searchChanged,this,[this] { update(); });
        connect(source,&PdfPage::highlightColorChanged,this,[this] { update(); });
    }
    emit sourcePageChanged(); update();
}
void PdfRegion::paint(QPainter *painter) {
    if (!m_source || m_source->m_regionImage.isNull()) return;
    painter->setRenderHint(QPainter::SmoothPixmapTransform);
    painter->drawImage(boundingRect(),m_source->m_regionImage);
    painter->translate(-m_source->regionRect().topLeft());
    m_source->paintHighlights(painter);
}

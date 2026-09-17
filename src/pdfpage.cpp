#include "pdfpage.h"
#include "sandbox.h"
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
    setAcceptedMouseButtons(Qt::LeftButton);
    setCursor(Qt::IBeamCursor);
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(150);
    connect(&m_debounce, &QTimer::timeout, this, &PdfPage::render);
    connect(this, &PdfPage::highlightColorChanged, this, [this] { update(); });
}
PdfPage::~PdfPage() {
    cancel(m_render); cancel(m_search);
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
void PdfPage::startJob(bool searchJob, QJsonObject request) {
    auto &slot = searchJob ? m_search : m_render;
    cancel(slot);
    if (m_fd < 0) return;
    auto process = new QProcess(this);
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
    timer->setInterval(searchJob ? 30000 : 20000);
    connect(timer, &QTimer::timeout, this, [this, searchJob, process] {
        finish(searchJob, process, {}, "La operación excedió el tiempo permitido.");
    });
    connect(process, &QProcess::readyReadStandardOutput, this, [this, process, output, searchJob] {
        const qsizetype limit = searchJob ? 8+MaxMetadata : MaxOutput;
        if (process->bytesAvailable() > limit-output->size()) {
            finish(searchJob, process, {}, "Respuesta del motor demasiado grande."); return;
        }
        *output += process->readAllStandardOutput();
    });
    connect(process, &QProcess::readyReadStandardError, this, [process] { process->readAllStandardError(); });
    connect(process, &QProcess::errorOccurred, this, [this, process, searchJob](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) finish(searchJob, process, {}, "No se pudo iniciar el motor aislado.");
    });
    connect(process, &QProcess::finished, this, [this, process, output, searchJob, timer](int code, QProcess::ExitStatus status) {
        timer->stop();
        // readyRead is normally emitted first, but account for a final buffered chunk.
        const qsizetype limit = searchJob ? 8+MaxMetadata : MaxOutput;
        if (process->bytesAvailable() > limit-output->size()) {
            finish(searchJob, process, {}, "Respuesta del motor demasiado grande."); return;
        }
        *output += process->readAllStandardOutput();
        finish(searchJob, process, *output, code == 0 && status == QProcess::NormalExit ? QString() : "No se pudo procesar el PDF en aislamiento.");
    });
    request["password"] = m_password;
    const auto input = QJsonDocument(request).toJson(QJsonDocument::Compact);
    connect(process, &QProcess::started, this, [process, input] { process->write(input); process->closeWriteChannel(); });
    process->start("/usr/bin/bwrap", sandboxArguments(qEnvironmentVariable("PDF_VIEW_WORKER")));
    timer->start();
    if (searchJob) emit searchChanged(); else emit changed();
}
void PdfPage::finish(bool searchJob, QProcess *process, const QByteArray &output, const QString &failure) {
    auto &slot = searchJob ? m_search : m_render;
    if (slot != process) return;
    cancel(slot);
    QString &error = searchJob ? m_searchError : m_error;
    auto reject = [&](const QString &message) {
        error = message;
        if (searchJob) emit searchChanged(); else emit changed();
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
    if (searchJob) {
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
        meta["page"].toInt()!=m_page || meta["rotation"].toInt()!=m_rotation ||
        output.size()!=8+length+quint64(w)*h*4 || !meta["words"].isArray()) {
        reject("Dimensiones o tamaño de respuesta inválidos."); return;
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
    m_size = QSizeF(pw,ph); m_pages = pages; m_words = validated;
    m_canCopy = meta["canCopy"].toBool(); m_locked = false;
    update(); emit changed(); revealCurrentMatch();
}
void PdfPage::open(const QUrl &url) {
    m_debounce.stop(); cancel(m_render); cancel(m_search);
    if (m_fd >= 0) ::close(m_fd);
    m_fd = -1; m_password.clear(); m_locked=false; m_canCopy=false;
    m_image={}; m_words.clear(); m_error.clear(); m_searchError.clear(); m_matches.clear();
    m_pages=0; m_page=1; m_rotation=0; m_match=-1; m_truncated=false;
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
    startJob(false, {{"op","render"},{"page",m_page},{"rotation",m_rotation},{"dpi",qBound(18.0,144*m_scale,768.0)}});
}
void PdfPage::setRenderScale(double scale) {
    if (!std::isfinite(scale)) return;
    scale=qBound(0.125,scale,4.0);
    if (qAbs(scale-m_scale)<0.02) return;
    m_scale=scale;
    if (m_fd>=0 && !m_locked) m_debounce.start();
    emit scaleChanged(); emit changed();
}
void PdfPage::goToPage(int number) {
    if (number<1 || number>m_pages || number==m_page) return;
    m_page=number; m_image={}; m_words.clear(); clearSelection(); update(); render();
}
void PdfPage::rotatePage(int steps) {
    if (m_pages==0) return;
    m_rotation=(m_rotation+(steps%4)+4)%4;
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
    m_match=(m_match+(direction<0?-1:1)+m_matches.size())%m_matches.size();
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
    forceActiveFocus(); clearSelection();
    const int index=wordAt(event->position());
    if (m_canCopy && index>=0 && mapRect(m_words[index].rect).adjusted(-4,-4,4,4).contains(event->position())) {
        m_anchor=m_cursor=index; update(); emit selectionChanged(); event->accept();
    } else event->ignore();
}
void PdfPage::mouseMoveEvent(QMouseEvent *event) {
    if (m_anchor<0) { event->ignore(); return; }
    m_cursor=wordAt(event->position()); update(); emit selectionChanged(); event->accept();
}
void PdfPage::mouseReleaseEvent(QMouseEvent *event) { event->accept(); }
QString PdfPage::selectedText() const {
    if (m_anchor<0 || m_cursor<0 || !m_canCopy) return {};
    QString text;
    for (int i=qMin(m_anchor,m_cursor); i<=qMax(m_anchor,m_cursor); ++i) {
        text+=m_words[i].text;
        if (i<qMax(m_anchor,m_cursor) && m_words[i].space) text+=' ';
    }
    return text;
}
void PdfPage::clearSelection() { m_anchor=m_cursor=-1; update(); emit selectionChanged(); }
void PdfPage::selectAll() {
    if (!m_canCopy || m_words.isEmpty()) return;
    m_anchor=0; m_cursor=m_words.size()-1; update(); emit selectionChanged();
}
void PdfPage::copySelection() {
    const QString text=selectedText();
    if (!text.isEmpty()) QGuiApplication::clipboard()->setText(text);
}

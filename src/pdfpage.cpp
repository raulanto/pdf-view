#include "pdfpage.h"
#include "sandbox.h"
#include <QFile>
#include <QFileInfo>
#include <QPainter>
#include <QtEndian>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

static constexpr qsizetype MaxOutput = 20 + 2048 * 2048 * 4;
PdfPage::PdfPage(QQuickItem *parent) : QQuickPaintedItem(parent) {
    QProcess::UnixProcessParameters parameters;
    parameters.flags = QProcess::UnixProcessFlag::CloseFileDescriptors;
    parameters.lowestFileDescriptorToClose = 4;
    m_process.setUnixProcessParameters(parameters);
    m_timeout.setSingleShot(true);
    m_timeout.setInterval(15000);
    connect(&m_timeout, &QTimer::timeout, this, [this] { fail("El documento excedió el tiempo permitido."); });
    connect(&m_process, &QProcess::readyReadStandardOutput, this, &PdfPage::receive);
    connect(&m_process, &QProcess::readyReadStandardError, this, [this] { m_process.readAllStandardError(); });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (m_busy && e == QProcess::FailedToStart) fail("No se pudo iniciar Bubblewrap. No se abrirá el PDF sin aislamiento.");
    });
    connect(&m_process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        m_timeout.stop();
        if (!m_busy) return;
        receive();
        if (!m_busy) return;
        if (status != QProcess::NormalExit || code != 0) {
            fail("No se pudo procesar el PDF: inválido, protegido, límite excedido o aislamiento no disponible.");
            return;
        }
        if (m_output.size() < 20 || m_output.first(4) != "PDF1") { fail("Respuesta inválida del motor."); return; }
        auto field = [this](int offset) { return qFromLittleEndian<quint32>(m_output.constData() + offset); };
        const quint32 w = field(4), h = field(8), pages = field(12), bytes = field(16);
        if (!w || !h || w > 2048 || h > 2048 || !pages || pages > 1000000 ||
            bytes != quint64(w) * h * 4 || m_output.size() != 20 + bytes) {
            fail("Dimensiones o tamaño de respuesta inválidos."); return;
        }
        m_image = QImage(reinterpret_cast<const uchar *>(m_output.constData()+20), w, h, w*4, QImage::Format_RGBA8888).copy();
        m_output.clear();
        m_pages = int(pages);
        m_busy = false;
        update();
        emit changed();
    });
}
PdfPage::~PdfPage() { m_process.kill(); m_process.waitForFinished(1000); }
void PdfPage::fail(const QString &message) {
    m_busy = false;
    m_timeout.stop();
    m_process.kill();
    m_output.clear();
    m_error = message;
    emit changed();
}
void PdfPage::receive() {
    if (!m_busy) { m_process.readAllStandardOutput(); return; }
    if (m_process.bytesAvailable() > MaxOutput - m_output.size()) { fail("Respuesta del motor demasiado grande."); return; }
    m_output += m_process.readAllStandardOutput();
}
void PdfPage::open(const QUrl &url) {
    m_busy = false;
    m_process.kill();
    m_process.waitForFinished(1000);
    m_timeout.stop();
    m_output.clear(); m_image = {}; m_error.clear(); m_pages = 0;
    update();
    if (!url.isLocalFile()) { fail("Selecciona un archivo PDF local."); return; }
    const auto path = QFile::encodeName(url.toLocalFile());
    const int fd = ::open(path.constData(), O_RDONLY | O_CLOEXEC | O_NONBLOCK);
    struct stat info {};
    if (fd < 0 || fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_size > 256LL*1024*1024) {
        if (fd >= 0) close(fd);
        fail("El archivo no es regular, no se puede leer o supera 256 MiB."); return;
    }
    const QString worker = qEnvironmentVariable("PDF_VIEW_WORKER");
    if (worker.isEmpty() || !QFileInfo(worker).isExecutable()) {
        close(fd); fail("Motor no encontrado. Inicia el visor mediante scripts/run.sh."); return;
    }
    m_process.setChildProcessModifier([fd] {
        if (dup2(fd, 3) < 0 || fcntl(3, F_SETFD, 0) < 0) _exit(126);
        if (fd != 3) close(fd);
    });
    m_busy = true;
    emit changed();
    m_process.start("/usr/bin/bwrap", sandboxArguments(worker));
    // QProcess executes its child modifier before start() returns on Unix.
    close(fd);
    if (m_busy) m_timeout.start();
}
void PdfPage::paint(QPainter *painter) {
    if (m_image.isNull()) return;
    QSizeF size = m_image.size();
    size.scale(boundingRect().size(), Qt::KeepAspectRatio);
    QRectF target(QPointF((width()-size.width())/2, (height()-size.height())/2), size);
    painter->setRenderHint(QPainter::SmoothPixmapTransform);
    painter->drawImage(target, m_image);
}

#pragma once
#include <QQuickPaintedItem>
#include <QProcess>
#include <QTimer>
#include <QImage>
#include <QJsonObject>
#include <QtQml/qqmlregistration.h>

class PdfPage : public QQuickPaintedItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(int pageCount READ pageCount NOTIFY changed)
    Q_PROPERTY(bool hasPage READ hasPage NOTIFY changed)
    Q_PROPERTY(int currentPage READ currentPage NOTIFY changed)
    Q_PROPERTY(int rotation READ rotation NOTIFY changed)
    Q_PROPERTY(double pageWidth READ pageWidth NOTIFY changed)
    Q_PROPERTY(double pageHeight READ pageHeight NOTIFY changed)
    Q_PROPERTY(double renderScale READ renderScale WRITE setRenderScale NOTIFY scaleChanged)
    Q_PROPERTY(bool passwordRequired READ passwordRequired NOTIFY changed)
    Q_PROPERTY(bool searching READ searching NOTIFY searchChanged)
    Q_PROPERTY(QString searchError READ searchError NOTIFY searchChanged)
    Q_PROPERTY(int matchCount READ matchCount NOTIFY searchChanged)
    Q_PROPERTY(int matchIndex READ matchIndex NOTIFY searchChanged)
    Q_PROPERTY(bool searchTruncated READ searchTruncated NOTIFY searchChanged)
    Q_PROPERTY(QString selectedText READ selectedText NOTIFY selectionChanged)
    Q_PROPERTY(bool canCopy READ canCopy NOTIFY changed)
    Q_PROPERTY(QColor highlightColor MEMBER m_highlight NOTIFY highlightColorChanged)
public:
    explicit PdfPage(QQuickItem *parent = nullptr);
    ~PdfPage() override;
    bool busy() const { return m_render != nullptr || m_debounce.isActive(); }
    QString error() const { return m_error; }
    int pageCount() const { return m_pages; }
    bool hasPage() const { return !m_image.isNull(); }
    int currentPage() const { return m_page; }
    int rotation() const { return m_rotation*90; }
    double pageWidth() const { return m_rotation%2 ? m_size.height() : m_size.width(); }
    double pageHeight() const { return m_rotation%2 ? m_size.width() : m_size.height(); }
    double renderScale() const { return m_scale; }
    void setRenderScale(double scale);
    bool passwordRequired() const { return m_locked; }
    bool searching() const { return m_search != nullptr; }
    QString searchError() const { return m_searchError; }
    int matchCount() const { return m_matches.size(); }
    int matchIndex() const { return m_match; }
    bool searchTruncated() const { return m_truncated; }
    QString selectedText() const;
    bool canCopy() const { return m_canCopy; }
    Q_INVOKABLE void open(const QUrl &url);
    Q_INVOKABLE void unlock(const QString &password);
    Q_INVOKABLE void goToPage(int number);
    Q_INVOKABLE void rotatePage(int steps);
    Q_INVOKABLE void search(const QString &query);
    Q_INVOKABLE void nextMatch(int direction);
    Q_INVOKABLE void selectAll();
    Q_INVOKABLE void clearSelection();
    Q_INVOKABLE void copySelection();
    void paint(QPainter *painter) override;
signals:
    void changed();
    void searchChanged();
    void selectionChanged();
    void scaleChanged();
    void highlightColorChanged();
    void revealMatch(QPointF point);
protected:
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
private:
    struct Word { QString text; QRectF rect; bool space; };
    struct Match { int page; QRectF rect; };
    void cancel(QProcess *&process);
    void startJob(bool searchJob, QJsonObject request);
    void render();
    void finish(bool searchJob, QProcess *process, const QByteArray &output, const QString &failure);
    QRectF targetRect() const;
    QRectF mapRect(const QRectF &rect) const;
    int wordAt(QPointF point) const;
    void revealCurrentMatch();
    QProcess *m_render = nullptr, *m_search = nullptr;
    QTimer m_debounce;
    QImage m_image;
    QSizeF m_size {612, 792};
    QString m_error, m_searchError, m_password;
    QVector<Word> m_words;
    QVector<Match> m_matches;
    int m_fd = -1, m_pages = 0, m_page = 1, m_rotation = 0, m_match = -1;
    int m_anchor = -1, m_cursor = -1;
    double m_scale = 1.0;
    bool m_locked = false, m_canCopy = false, m_truncated = false;
    QColor m_highlight {"#7aa2f7"};
};

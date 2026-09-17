#pragma once
#include <QQuickPaintedItem>
#include <QProcess>
#include <QTimer>
#include <QImage>
#include <QtQml/qqmlregistration.h>

class PdfPage : public QQuickPaintedItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(int pageCount READ pageCount NOTIFY changed)
    Q_PROPERTY(bool hasPage READ hasPage NOTIFY changed)
public:
    explicit PdfPage(QQuickItem *parent = nullptr);
    ~PdfPage() override;
    bool busy() const { return m_busy; }
    QString error() const { return m_error; }
    int pageCount() const { return m_pages; }
    bool hasPage() const { return !m_image.isNull(); }
    Q_INVOKABLE void open(const QUrl &url);
    void paint(QPainter *painter) override;
signals:
    void changed();
private:
    void fail(const QString &message);
    void receive();
    QProcess m_process;
    QTimer m_timeout;
    QByteArray m_output;
    QImage m_image;
    QString m_error;
    int m_pages = 0;
    bool m_busy = false;
};

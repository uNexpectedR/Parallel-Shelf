#pragma once

#include <QObject>
#include <QString>

// QFile helper for qmltestrunner (tests/TestFileBytes), same algorithm as
// parallel_shelf_core. The packaged view never imports this plugin.
class FileBytes : public QObject
{
    Q_OBJECT
public:
    explicit FileBytes(QObject *parent = nullptr);

    Q_INVOKABLE qint64 fileSize(const QString &path) const;
    Q_INVOKABLE QString readPiece(const QString &path, int offset, int size) const;
    Q_INVOKABLE bool writePiece(const QString &path, int offset, const QString &piece) const;
    Q_INVOKABLE QString mkdir(const QString &path) const;
    Q_INVOKABLE QString fetchDest(const QString &id, const QString &ext) const;
    Q_INVOKABLE QString holdFile(const QString &cid) const;
    Q_INVOKABLE bool writeHold(const QString &cid, const QString &path) const;
    Q_INVOKABLE QString readHold(const QString &cid) const;
    Q_INVOKABLE QString holdRead(const QString &path, int offset, int size, const QString &key) const;
    Q_INVOKABLE QString keepHold(const QString &key, const QString &cid) const;
    Q_INVOKABLE QString copyToStaging(const QString &path) const;
    Q_INVOKABLE QString stageShare(const QString &path) const;
    Q_INVOKABLE bool rememberSource(const QString &cid, const QString &path) const;
    Q_INVOKABLE QString readSource(const QString &cid) const;
    Q_INVOKABLE bool copyFile(const QString &src, const QString &dest) const;
    Q_INVOKABLE QString renderPage(const QString &cid, int page, int width) const;
};

#include "parallel_shelf_core_impl.h"
#include "file_read.h"
#include "page_render.h"

#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>

namespace {

std::string reply(bool ok, const QJsonValue &value, const QString &error)
{
    QJsonObject o;
    o.insert(QStringLiteral("success"), ok);
    o.insert(QStringLiteral("value"), value);
    o.insert(QStringLiteral("error"), error);
    return QJsonDocument(o).toJson(QJsonDocument::Compact).toStdString();
}

} // namespace

void ParallelShelfCoreImpl::onContextReady()
{
}

std::string ParallelShelfCoreImpl::snapshot()
{
    QJsonObject v;
    v.insert(QStringLiteral("version"), QStringLiteral("0.1.5"));
    return reply(true, v, QString());
}

std::string ParallelShelfCoreImpl::fetchDest(const std::string& id, const std::string& ext)
{
    QString dest = parallelShelfFetchDest(QString::fromStdString(id),
                                         QString::fromStdString(ext));
    if (dest.isEmpty() || dest.at(0) != QLatin1Char('/') || parallelShelfIsGlobalTmp(dest))
        dest = parallelShelfFetchDest(QStringLiteral("book"), QStringLiteral("pdf"));
    QDir().mkpath(QFileInfo(dest).absolutePath());
    return reply(true, QJsonValue(dest), QString());
}

std::string ParallelShelfCoreImpl::fileSize(const std::string& path)
{
    const qint64 n = parallelShelfFileSize(QString::fromStdString(path));
    if (n < 0)
        return reply(false, QJsonValue(), QStringLiteral("File not found."));
    return reply(true, QJsonValue(static_cast<double>(n)), QString());
}

std::string ParallelShelfCoreImpl::readPiece(const std::string& path, int64_t offset, int64_t size)
{
    const QString piece = parallelShelfReadPiece(QString::fromStdString(path), offset, size);
    if (piece.isEmpty() && size > 0)
        return reply(false, QJsonValue(QString()), QStringLiteral("Could not read the file."));
    return reply(true, QJsonValue(piece), QString());
}

std::string ParallelShelfCoreImpl::writePiece(const std::string& path, int64_t offset, const std::string& piece)
{
    const QString qpiece = QString::fromStdString(piece);
    if (!parallelShelfWritePiece(QString::fromStdString(path), offset, qpiece))
        return reply(false, QJsonValue(), QStringLiteral("Could not write the file."));
    return reply(true, QJsonValue(static_cast<double>(offset + static_cast<qint64>(piece.size()))), QString());
}

std::string ParallelShelfCoreImpl::mkdir(const std::string& path)
{
    QString raw = QString::fromStdString(path);
    QString dir;
    if (raw.trimmed().isEmpty() || !raw.trimmed().startsWith(QLatin1Char('/')))
        dir = parallelShelfCacheDir();
    else
        dir = parallelShelfMkdir(raw);
    if (dir.isEmpty() || dir.at(0) != QLatin1Char('/') || parallelShelfIsGlobalTmp(dir))
        dir = parallelShelfCacheDir();
    if (dir.isEmpty() || dir.at(0) != QLatin1Char('/') || parallelShelfIsGlobalTmp(dir))
        dir = parallelShelfPickDir(parallelShelfUnixHome());
    QDir().mkpath(dir);
    return reply(true, QJsonValue(dir), QString());
}

std::string ParallelShelfCoreImpl::holdFile(const std::string& cid)
{
    const QString path = parallelShelfHoldFile(QString::fromStdString(cid));
    if (path.isEmpty() || path.at(0) != QLatin1Char('/'))
        return reply(false, QJsonValue(), QStringLiteral("No hold path."));
    return reply(true, QJsonValue(path), QString());
}

std::string ParallelShelfCoreImpl::writeHold(const std::string& cid, const std::string& path)
{
    const QString qcid = QString::fromStdString(cid);
    QString stored = QString::fromStdString(path);
    if (!parallelShelfWriteHold(qcid, stored))
        return reply(false, QJsonValue(), QStringLiteral("Could not remember the hold."));
    stored = parallelShelfReadHold(qcid);
    if (stored.isEmpty())
        stored = parallelShelfPath(QString::fromStdString(path));
    if (stored.isEmpty())
        stored = parallelShelfHoldFile(qcid);
    return reply(true, QJsonValue(stored), QString());
}

std::string ParallelShelfCoreImpl::readHold(const std::string& cid)
{
    const QString path = parallelShelfReadHold(QString::fromStdString(cid));
    if (path.isEmpty() || path.at(0) != QLatin1Char('/'))
        return reply(false, QJsonValue(), QStringLiteral("No hold."));
    return reply(true, QJsonValue(path), QString());
}

std::string ParallelShelfCoreImpl::holdRead(const std::string& path, int64_t offset, int64_t size,
                                           const std::string& key)
{
    const QString piece = parallelShelfHoldRead(QString::fromStdString(path), offset, size,
                                               QString::fromStdString(key));
    if (piece.isEmpty() && size > 0)
        return reply(false, QJsonValue(QString()), QStringLiteral("Could not read the file."));
    return reply(true, QJsonValue(piece), QString());
}

std::string ParallelShelfCoreImpl::keepHold(const std::string& key, const std::string& cid)
{
    const QString path = parallelShelfKeepHold(QString::fromStdString(key),
                                              QString::fromStdString(cid));
    if (path.isEmpty() || path.at(0) != QLatin1Char('/'))
        return reply(false, QJsonValue(), QStringLiteral("Could not keep the hold."));
    return reply(true, QJsonValue(path), QString());
}

std::string ParallelShelfCoreImpl::stageShare(const std::string& path)
{
    const QString dest = parallelShelfStageShare(QString::fromStdString(path));
    if (dest.isEmpty() || dest.at(0) != QLatin1Char('/') || parallelShelfIsGlobalTmp(dest)
            || dest.contains(QLatin1String("/Downloads/")))
        return reply(false, QJsonValue(), QStringLiteral("Could not copy the file."));
    return reply(true, QJsonValue(dest), QString());
}

std::string ParallelShelfCoreImpl::rememberSource(const std::string& cid, const std::string& path)
{
    const QString qcid = QString::fromStdString(cid);
    const QString qpath = QString::fromStdString(path);
    if (!parallelShelfRememberSource(qcid, qpath))
        return reply(false, QJsonValue(), QStringLiteral("Could not remember the source."));
    const QString stored = parallelShelfReadSource(qcid);
    return reply(true, QJsonValue(stored), QString());
}

std::string ParallelShelfCoreImpl::readSource(const std::string& cid)
{
    const QString path = parallelShelfReadSource(QString::fromStdString(cid));
    if (path.isEmpty() || path.at(0) != QLatin1Char('/'))
        return reply(false, QJsonValue(), QStringLiteral("No source."));
    return reply(true, QJsonValue(path), QString());
}

std::string ParallelShelfCoreImpl::copyFile(const std::string& src, const std::string& dest)
{
    const QString from = QString::fromStdString(src);
    const QString to = QString::fromStdString(dest);
    if (!parallelShelfCopyFile(from, to))
        return reply(false, QJsonValue(), QStringLiteral("Could not copy the file."));
    return reply(true, QJsonValue(parallelShelfPath(to)), QString());
}

std::string ParallelShelfCoreImpl::renderPage(const std::string& cid, int64_t page, int64_t width,
                                             const std::string& dest)
{
    const QString path = parallelShelfRenderPage(QString::fromStdString(cid),
                                                int(page), int(width),
                                                QString::fromStdString(dest));
    if (path.isEmpty() || path.at(0) != QLatin1Char('/')
            || !path.endsWith(QLatin1String(".png"))
            || parallelShelfFileSize(path) < 32) {
        if (parallelShelfPdftoppmBin().isEmpty())
            return reply(false, QJsonValue(),
                         QStringLiteral("pdftoppm is missing from this install."));
        return reply(false, QJsonValue(),
                     QStringLiteral("pdftoppm could not be run."));
    }
    return reply(true, QJsonValue(path), QString());
}

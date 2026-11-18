#include "filebytes.h"
#include "file_read.h"
#include "page_render.h"

FileBytes::FileBytes(QObject *parent)
    : QObject(parent)
{
}

qint64 FileBytes::fileSize(const QString &path) const
{
    return parallelShelfFileSize(path);
}

QString FileBytes::readPiece(const QString &path, int offset, int size) const
{
    return parallelShelfReadPiece(path, offset, size);
}

bool FileBytes::writePiece(const QString &path, int offset, const QString &piece) const
{
    return parallelShelfWritePiece(path, offset, piece);
}

QString FileBytes::mkdir(const QString &path) const
{
    return parallelShelfMkdir(path);
}

QString FileBytes::fetchDest(const QString &id, const QString &ext) const
{
    return parallelShelfFetchDest(id, ext);
}

QString FileBytes::holdFile(const QString &cid) const
{
    return parallelShelfHoldFile(cid);
}

bool FileBytes::writeHold(const QString &cid, const QString &path) const
{
    return parallelShelfWriteHold(cid, path);
}

QString FileBytes::readHold(const QString &cid) const
{
    return parallelShelfReadHold(cid);
}

QString FileBytes::holdRead(const QString &path, int offset, int size, const QString &key) const
{
    return parallelShelfHoldRead(path, offset, size, key);
}

QString FileBytes::keepHold(const QString &key, const QString &cid) const
{
    return parallelShelfKeepHold(key, cid);
}

QString FileBytes::copyToStaging(const QString &path) const
{
    return parallelShelfStageShare(path);
}

QString FileBytes::stageShare(const QString &path) const
{
    return parallelShelfStageShare(path);
}

bool FileBytes::rememberSource(const QString &cid, const QString &path) const
{
    return parallelShelfRememberSource(cid, path);
}

QString FileBytes::readSource(const QString &cid) const
{
    return parallelShelfReadSource(cid);
}

bool FileBytes::copyFile(const QString &src, const QString &dest) const
{
    return parallelShelfCopyFile(src, dest);
}

QString FileBytes::renderPage(const QString &cid, int page, int width) const
{
    return parallelShelfRenderPage(cid, page, width);
}

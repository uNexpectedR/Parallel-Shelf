#pragma once

#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMutex>
#include <QMutexLocker>
#include <QStandardPaths>
#include <cstring>
#include <QDateTime>
#include <QString>
#include <QStringList>

#if defined(Q_OS_UNIX)
#include <pwd.h>
#include <unistd.h>
#endif

// QFile in the Logos host process (parallel_shelf_core), not in QmlSandbox.
inline QString parallelShelfPath(const QString &raw)
{
    QString path = raw.trimmed();
    if (path.startsWith(QLatin1String("file://"))) {
        path = path.mid(7);
        if (path.startsWith(QLatin1String("localhost/")))
            path = path.mid(9);
        if (!path.startsWith(QLatin1Char('/')))
            path.prepend(QLatin1Char('/'));
    }
    return path;
}

inline bool parallelShelfIsMemory(const QString &path)
{
    return path.startsWith(QLatin1String("memory:"));
}

inline QMutex &parallelShelfHoldLock()
{
    static QMutex mutex;
    return mutex;
}

inline QHash<QString, QByteArray> &parallelShelfHold()
{
    static QHash<QString, QByteArray> held;
    return held;
}

inline QHash<QString, QByteArray> &parallelShelfPending()
{
    static QHash<QString, QByteArray> pending;
    return pending;
}

// In-process cid → path maps. QML Settings / lastShare get stripped on
// Mac Basecamp; these hashes live in the core host process and cannot.
inline QHash<QString, QString> &parallelShelfHoldPaths()
{
    static QHash<QString, QString> map;
    return map;
}

inline QHash<QString, QString> &parallelShelfSourcePaths()
{
    static QHash<QString, QString> map;
    return map;
}

inline QByteArray parallelShelfToBytes(const QString &piece)
{
    QByteArray bytes;
    bytes.resize(piece.size());
    for (int i = 0; i < piece.size(); ++i)
        bytes[i] = static_cast<char>(piece.at(i).cell());
    return bytes;
}

inline QString parallelShelfFromBytes(const QByteArray &bytes)
{
    QString out;
    out.resize(bytes.size());
    for (int i = 0; i < bytes.size(); ++i)
        out[i] = QChar(static_cast<uchar>(bytes.at(i)));
    return out;
}

inline qint64 parallelShelfFileSize(const QString &raw)
{
    const QString path = parallelShelfPath(raw);
    if (parallelShelfIsMemory(path)) {
        QMutexLocker lock(&parallelShelfHoldLock());
        const auto it = parallelShelfHold().constFind(path);
        if (it == parallelShelfHold().constEnd())
            return -1;
        return it.value().size();
    }
    const QFileInfo info(path);
    if (!info.isFile())
        return -1;
    return info.size();
}

inline QString parallelShelfReadPiece(const QString &raw, qint64 offset, qint64 size)
{
    if (offset < 0 || size <= 0)
        return QString();
    const QString path = parallelShelfPath(raw);
    if (parallelShelfIsMemory(path)) {
        QMutexLocker lock(&parallelShelfHoldLock());
        const auto it = parallelShelfHold().constFind(path);
        if (it == parallelShelfHold().constEnd())
            return QString();
        return parallelShelfFromBytes(it.value().mid(offset, size));
    }
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return QString();
    if (!file.seek(offset))
        return QString();
    return parallelShelfFromBytes(file.read(size));
}

inline bool parallelShelfIsGlobalTmp(const QString &dir);
inline QString parallelShelfCacheDir();
inline QString parallelShelfWorkDir();

// Mirror of readPiece: downloadChunks → disk, the reverse of Share → uploadChunk.
inline QString parallelShelfMkdir(const QString &raw)
{
    QString path = parallelShelfPath(raw);
    QString dir = path;
    if (path.isEmpty() || !path.startsWith(QLatin1Char('/')))
        return parallelShelfCacheDir();
    if (!path.endsWith(QLatin1Char('/'))) {
        const QFileInfo info(path);
        const QString name = info.fileName();
        if (name.contains(QLatin1Char('.')))
            dir = info.absolutePath();
    }
    if (dir.isEmpty() || dir.at(0) != QLatin1Char('/') || parallelShelfIsGlobalTmp(dir))
        dir = parallelShelfCacheDir();
    QDir().mkpath(dir);
    if (dir.isEmpty() || dir.at(0) != QLatin1Char('/') || parallelShelfIsGlobalTmp(dir))
        return parallelShelfCacheDir();
    return dir;
}

inline bool parallelShelfWritePiece(const QString &raw, qint64 offset, const QString &piece)
{
    if (offset < 0)
        return false;
    const QString path = parallelShelfPath(raw);
    const QByteArray bytes = parallelShelfToBytes(piece);
    if (parallelShelfIsMemory(path)) {
        QMutexLocker lock(&parallelShelfHoldLock());
        QByteArray &held = parallelShelfHold()[path];
        if (offset == 0)
            held = bytes;
        else {
            const int need = int(offset + bytes.size());
            if (held.size() < need)
                held.resize(need);
            if (!bytes.isEmpty())
                memcpy(held.data() + offset, bytes.constData(), size_t(bytes.size()));
        }
        return true;
    }
    QDir().mkpath(QFileInfo(path).absolutePath());
    if (piece.isEmpty())
        return true;
    QFile file(path);
    if (offset == 0) {
        QDir().mkpath(QFileInfo(path).absolutePath());
        if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
            return false;
        return file.write(bytes) == bytes.size();
    }
    if (!file.open(QIODevice::ReadWrite))
        return false;
    if (!file.seek(offset))
        return false;
    return file.write(bytes) == bytes.size();
}

// Mac Storage cannot write a file sitting in global /tmp. Skip that root
// and keep looking; fetchDest must still return a path.
inline bool parallelShelfIsGlobalTmp(const QString &dir)
{
    QString abs = QDir(dir).absolutePath();
    while (abs.endsWith(QLatin1Char('/')) && abs.size() > 1)
        abs.chop(1);
    if (abs == QLatin1String("/tmp") || abs == QLatin1String("/private/tmp")
            || abs == QLatin1String("/var/tmp") || abs == QLatin1String("/private/var/tmp"))
        return true;
    if (abs.startsWith(QLatin1String("/tmp/"))
            || abs.startsWith(QLatin1String("/private/tmp/"))
            || abs.startsWith(QLatin1String("/var/tmp/"))
            || abs.startsWith(QLatin1String("/private/var/tmp/")))
        return true;
    return false;
}

inline QString parallelShelfJoinCache(const QString &root)
{
    if (root.trimmed().isEmpty())
        return QString();
    QString abs = QDir(root.trimmed()).absolutePath();
    while (abs.endsWith(QLatin1Char('/')) && abs.size() > 1)
        abs.chop(1);
    if (abs.isEmpty())
        return QString();
    if (QFileInfo(abs).fileName() == QLatin1String("parallel-shelf"))
        return abs;
    return QDir(abs).filePath(QStringLiteral("parallel-shelf"));
}

inline QString parallelShelfTryRoot(const QString &root, bool skipGlobalTmp)
{
    if (root.trimmed().isEmpty())
        return QString();
    if (skipGlobalTmp && parallelShelfIsGlobalTmp(root))
        return QString();
    const QString dir = parallelShelfJoinCache(root);
    if (dir.isEmpty())
        return QString();
    QDir().mkpath(dir);
    return dir;
}

inline QString parallelShelfSafeId(const QString &raw)
{
    QString id;
    const QString lower = raw.toLower();
    for (int i = 0; i < lower.size() && id.size() < 48; ++i) {
        const QChar c = lower.at(i);
        if ((c >= QLatin1Char('a') && c <= QLatin1Char('z'))
            || (c >= QLatin1Char('0') && c <= QLatin1Char('9'))
            || c == QLatin1Char('-'))
            id += c;
    }
    return id;
}

inline QString parallelShelfSafeExt(const QString &raw)
{
    QString ext = raw.toLower().trimmed();
    if (ext.startsWith(QLatin1Char('.')))
        ext = ext.mid(1);
    const int slash = ext.lastIndexOf(QLatin1Char('/'));
    if (slash >= 0)
        ext = ext.mid(slash + 1);
    static const QStringList ok = {
        QStringLiteral("pdf"), QStringLiteral("mp3"),
        QStringLiteral("m4a"), QStringLiteral("ogg")
    };
    if (!ok.contains(ext))
        return QString();
    return ext;
}

inline bool parallelShelfCanWriteDir(const QString &dir)
{
    if (dir.isEmpty() || dir.at(0) != QLatin1Char('/') || parallelShelfIsGlobalTmp(dir))
        return false;
    QDir().mkpath(dir);
    if (!QFileInfo(dir).isDir())
        return false;
    const QString probe = QDir(dir).filePath(QStringLiteral(".ps-write"));
    QFile file(probe);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    const bool ok = file.write("ok") == 2;
    file.close();
    QFile::remove(probe);
    return ok;
}

inline QString parallelShelfPickDir(const QString &root)
{
    const QString dir = parallelShelfTryRoot(root, true);
    if (parallelShelfCanWriteDir(dir))
        return dir;
    return QString();
}

// Mac Offscreen / a helper with HOME=/tmp still has a real account home.
inline QString parallelShelfUnixHome()
{
    auto take = [](const QString &raw) {
        QString p = raw.trimmed();
        if (p.isEmpty() || p.at(0) != QLatin1Char('/') || parallelShelfIsGlobalTmp(p))
            return QString();
        return QDir(p).absolutePath();
    };
    const QString fromEnv = take(QString::fromLocal8Bit(qgetenv("HOME")));
    if (!fromEnv.isEmpty())
        return fromEnv;
    const QString user = QString::fromLocal8Bit(qgetenv("USER"));
    if (!user.isEmpty() && !user.contains(QLatin1Char('/'))) {
        const QString mac = take(QStringLiteral("/Users/") + user);
        if (!mac.isEmpty() && QFileInfo(mac).isDir())
            return mac;
        const QString lin = take(QStringLiteral("/home/") + user);
        if (!lin.isEmpty() && QFileInfo(lin).isDir())
            return lin;
    }
#if defined(Q_OS_UNIX)
    struct passwd *pw = getpwuid(getuid());
    if (pw && pw->pw_dir)
        return take(QString::fromLocal8Bit(pw->pw_dir));
#endif
    return take(QDir::homePath());
}

inline QString parallelShelfCacheDir()
{
    const QString home = parallelShelfUnixHome();
    const QString candidates[] = {
        QStandardPaths::writableLocation(QStandardPaths::CacheLocation),
        QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation),
        QStandardPaths::writableLocation(QStandardPaths::AppDataLocation),
        QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation),
        QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation),
        QStandardPaths::writableLocation(QStandardPaths::TempLocation),
        QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation),
        QStandardPaths::writableLocation(QStandardPaths::HomeLocation),
        home.isEmpty() ? QString() : QDir(home).filePath(QStringLiteral("Library/Caches")),
        home.isEmpty() ? QString() : QDir(home).filePath(QStringLiteral("Library/Application Support")),
        home.isEmpty() ? QString() : QDir(home).filePath(QStringLiteral(".cache")),
        home.isEmpty() ? QString() : QDir(home).filePath(QStringLiteral(".local/share")),
        home,
        QDir::currentPath()
    };
    for (const QString &root : candidates) {
        const QString dir = parallelShelfPickDir(root);
        if (!dir.isEmpty())
            return dir;
    }
    const QString fallback = parallelShelfJoinCache(home);
    if (parallelShelfCanWriteDir(fallback))
        return fallback;
    return QString();
}

inline QString parallelShelfFetchDest(const QString &rawId, const QString &rawExt)
{
    QString id = parallelShelfSafeId(rawId);
    QString ext = parallelShelfSafeExt(rawExt);
    if (id.isEmpty())
        id = QStringLiteral("book");
    if (ext.isEmpty())
        ext = QStringLiteral("pdf");
    QString dir = parallelShelfCacheDir();
    QDir().mkpath(dir);
    return QDir(dir).filePath(QStringLiteral("parallel-shelf-%1.%2").arg(id, ext));
}

// Hold file named for the CID, next to a cid→path map the core process owns.
inline QString parallelShelfHoldName(const QString &cid)
{
    QString name;
    for (int i = 0; i < cid.size() && name.size() < 200; ++i) {
        const QChar c = cid.at(i);
        if ((c >= QLatin1Char('A') && c <= QLatin1Char('Z'))
            || (c >= QLatin1Char('a') && c <= QLatin1Char('z'))
            || (c >= QLatin1Char('0') && c <= QLatin1Char('9'))
            || c == QLatin1Char('_') || c == QLatin1Char('-'))
            name += c;
    }
    return name;
}

inline QString parallelShelfWorkIndex(const QString &name)
{
    QString dir = parallelShelfWorkDir();
    if (dir.isEmpty() || dir.at(0) != QLatin1Char('/') || parallelShelfIsGlobalTmp(dir))
        dir = parallelShelfCacheDir();
    if (dir.isEmpty() || dir.at(0) != QLatin1Char('/'))
        return QString();
    QDir().mkpath(dir);
    return QDir(dir).filePath(name);
}

inline void parallelShelfWriteIndex(const QString &indexPath, const QHash<QString, QString> &map)
{
    if (indexPath.isEmpty())
        return;
    QJsonObject obj;
    for (auto it = map.constBegin(); it != map.constEnd(); ++it)
        obj.insert(it.key(), it.value());
    QFile index(indexPath);
    if (!index.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;
    index.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
}

inline QString parallelShelfIndexLookup(const QString &indexPath, const QString &cid)
{
    if (indexPath.isEmpty() || cid.isEmpty())
        return QString();
    QFile index(indexPath);
    if (!index.open(QIODevice::ReadOnly))
        return QString();
    const QJsonObject map = QJsonDocument::fromJson(index.readAll()).object();
    return parallelShelfPath(map.value(cid).toString());
}

inline QString parallelShelfHoldFile(const QString &cid)
{
    const QString name = parallelShelfHoldName(cid);
    if (name.isEmpty())
        return QString();
    QString dir = parallelShelfWorkDir();
    if (dir.isEmpty() || dir.at(0) != QLatin1Char('/') || parallelShelfIsGlobalTmp(dir)
            || dir.contains(QLatin1String("/Downloads/")))
        dir = parallelShelfCacheDir();
    if (dir.isEmpty() || dir.at(0) != QLatin1Char('/') || parallelShelfIsGlobalTmp(dir))
        return QString();
    QDir().mkpath(dir);
    return QDir(dir).filePath(QStringLiteral("parallel-shelf-hold-") + name
                             + QStringLiteral(".bin"));
}

inline QString parallelShelfHoldsIndex(const QString &holdPath)
{
    const QString dir = QFileInfo(holdPath).absolutePath();
    if (dir.isEmpty() || dir.at(0) != QLatin1Char('/'))
        return QString();
    return QDir(dir).filePath(QStringLiteral("parallel-shelf-holds.json"));
}

// Memory first: Mac TCC can refuse a sidecar next to ~/Downloads, and QML
// lastShare is stripped. The core QHash cannot be stripped this session.
inline bool parallelShelfWriteHold(const QString &rawCid, const QString &rawPath)
{
    const QString cid = rawCid.trimmed();
    QString path = parallelShelfPath(rawPath);
    if (path.isEmpty())
        path = parallelShelfHoldFile(cid);
    if (cid.isEmpty() || path.isEmpty() || path.at(0) != QLatin1Char('/'))
        return false;
    {
        QMutexLocker lock(&parallelShelfHoldLock());
        parallelShelfHoldPaths().insert(cid, path);
        parallelShelfWriteIndex(parallelShelfWorkIndex(QStringLiteral("parallel-shelf-holds.json")),
                                parallelShelfHoldPaths());
    }
    if (!parallelShelfIsGlobalTmp(path) && !path.contains(QLatin1String("/Downloads/"))) {
        QDir().mkpath(QFileInfo(path).absolutePath());
        QFile sidecar(path + QStringLiteral(".cid"));
        if (sidecar.open(QIODevice::WriteOnly | QIODevice::Truncate))
            sidecar.write(cid.toUtf8());
        const QString indexPath = parallelShelfHoldsIndex(path);
        if (!indexPath.isEmpty()) {
            QJsonObject map;
            QFile index(indexPath);
            if (index.open(QIODevice::ReadOnly)) {
                map = QJsonDocument::fromJson(index.readAll()).object();
                index.close();
            }
            map.insert(cid, path);
            if (index.open(QIODevice::WriteOnly | QIODevice::Truncate))
                index.write(QJsonDocument(map).toJson(QJsonDocument::Compact));
        }
    }
    return true;
}

inline QString parallelShelfReadHold(const QString &rawCid)
{
    const QString cid = rawCid.trimmed();
    if (cid.isEmpty())
        return QString();
    {
        QMutexLocker lock(&parallelShelfHoldLock());
        const QString got = parallelShelfPath(parallelShelfHoldPaths().value(cid));
        if (!got.isEmpty() && got.at(0) == QLatin1Char('/'))
            return got;
    }
    const QString fromWork = parallelShelfIndexLookup(
        parallelShelfWorkIndex(QStringLiteral("parallel-shelf-holds.json")), cid);
    if (!fromWork.isEmpty() && fromWork.at(0) == QLatin1Char('/')) {
        QMutexLocker lock(&parallelShelfHoldLock());
        parallelShelfHoldPaths().insert(cid, fromWork);
        return fromWork;
    }
    const QString fallback = parallelShelfHoldFile(cid);
    QString dir = fallback.isEmpty() ? parallelShelfCacheDir()
                                     : QFileInfo(fallback).absolutePath();
    if (!dir.isEmpty() && dir.at(0) == QLatin1Char('/')) {
        const QString got = parallelShelfIndexLookup(
            QDir(dir).filePath(QStringLiteral("parallel-shelf-holds.json")), cid);
        if (!got.isEmpty() && got.at(0) == QLatin1Char('/')) {
            QMutexLocker lock(&parallelShelfHoldLock());
            parallelShelfHoldPaths().insert(cid, got);
            return got;
        }
    }
    if (!fallback.isEmpty() && parallelShelfFileSize(fallback) > 0)
        return fallback;
    return QString();
}

// Choose-file path keyed by CID. Empty path forgets (tests). Downloads is
// allowed: that is the path Share just used.
inline bool parallelShelfRememberSource(const QString &rawCid, const QString &rawPath)
{
    const QString cid = rawCid.trimmed();
    const QString path = parallelShelfPath(rawPath);
    if (cid.isEmpty())
        return false;
    {
        QMutexLocker lock(&parallelShelfHoldLock());
        if (path.isEmpty())
            parallelShelfSourcePaths().remove(cid);
        else if (path.at(0) == QLatin1Char('/'))
            parallelShelfSourcePaths().insert(cid, path);
        else
            return false;
        parallelShelfWriteIndex(parallelShelfWorkIndex(QStringLiteral("parallel-shelf-sources.json")),
                                parallelShelfSourcePaths());
    }
    return true;
}

inline QString parallelShelfReadSource(const QString &rawCid)
{
    const QString cid = rawCid.trimmed();
    if (cid.isEmpty())
        return QString();
    {
        QMutexLocker lock(&parallelShelfHoldLock());
        const QString got = parallelShelfPath(parallelShelfSourcePaths().value(cid));
        if (!got.isEmpty() && got.at(0) == QLatin1Char('/'))
            return got;
    }
    const QString fromWork = parallelShelfIndexLookup(
        parallelShelfWorkIndex(QStringLiteral("parallel-shelf-sources.json")), cid);
    if (!fromWork.isEmpty() && fromWork.at(0) == QLatin1Char('/')) {
        QMutexLocker lock(&parallelShelfHoldLock());
        parallelShelfSourcePaths().insert(cid, fromWork);
        return fromWork;
    }
    return QString();
}

// 64 KiB QFile copy. Open/Download use this so the PDF does not ride QML IPC.
inline bool parallelShelfCopyFile(const QString &rawSrc, const QString &rawDest)
{
    const QString src = parallelShelfPath(rawSrc);
    const QString dest = parallelShelfPath(rawDest);
    if (src.isEmpty() || dest.isEmpty() || src.at(0) != QLatin1Char('/')
            || dest.at(0) != QLatin1Char('/'))
        return false;
    if (src == dest)
        return parallelShelfFileSize(src) > 0 || QFile(src).open(QIODevice::ReadOnly);
    QDir().mkpath(QFileInfo(dest).absolutePath());
    if (QFile::exists(dest) && dest != src)
        QFile::remove(dest);
    QFile in(src);
    if (!in.open(QIODevice::ReadOnly))
        return false;
    QFile out(dest);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        in.close();
        return false;
    }
    char buf[65536];
    qint64 total = 0;
    for (;;) {
        const qint64 n = in.read(buf, sizeof(buf));
        if (n < 0) {
            in.close();
            out.close();
            QFile::remove(dest);
            return false;
        }
        if (n == 0)
            break;
        if (out.write(buf, n) != n) {
            in.close();
            out.close();
            QFile::remove(dest);
            return false;
        }
        total += n;
    }
    in.close();
    out.close();
    if (total <= 0) {
        QFile::remove(dest);
        return false;
    }
    return true;
}

// Share: core reads the Choose file for uploadChunk and keeps those
// bytes in a pending buffer. QML never has to hold them.
inline QString parallelShelfHoldRead(const QString &raw, qint64 offset, qint64 size,
                                     const QString &key)
{
    const QString piece = parallelShelfReadPiece(raw, offset, size);
    const QString k = key.trimmed();
    if (k.isEmpty() || piece.isEmpty())
        return piece;
    const QByteArray bytes = parallelShelfToBytes(piece);
    QMutexLocker lock(&parallelShelfHoldLock());
    QByteArray &held = parallelShelfPending()[k];
    if (offset <= 0 || held.isEmpty())
        held = bytes;
    else if (offset == held.size())
        held += bytes;
    else {
        const int need = int(offset + bytes.size());
        if (held.size() < need)
            held.resize(need);
        if (!bytes.isEmpty())
            memcpy(held.data() + offset, bytes.constData(), size_t(bytes.size()));
    }
    return piece;
}

// After uploadFinalize, bind the pending Share bytes to the CID hold
// file inside this core process. Open reads that file; not lastShare.
inline QString parallelShelfKeepHold(const QString &key, const QString &rawCid)
{
    const QString k = key.trimmed();
    const QString cid = rawCid.trimmed();
    if (k.isEmpty() || cid.isEmpty())
        return QString();
    QByteArray bytes;
    {
        QMutexLocker lock(&parallelShelfHoldLock());
        bytes = parallelShelfPending().take(k);
        if (bytes.isEmpty())
            return QString();
    }
    const QString path = parallelShelfHoldFile(cid);
    if (path.isEmpty() || path.at(0) != QLatin1Char('/') || parallelShelfIsGlobalTmp(path))
        return QString();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return QString();
    if (file.write(bytes) != bytes.size())
        return QString();
    file.close();
    if (!parallelShelfWriteHold(cid, path))
        return QString();
    return path;
}

// Muster swarmWorkDir: instance persistence / AppData, never global /tmp
// and never Cache (Mac wipes Cache across Basecamp restarts).
inline QString parallelShelfWorkDir()
{
    const QString home = parallelShelfUnixHome();
    const QString candidates[] = {
        QStandardPaths::writableLocation(QStandardPaths::AppDataLocation),
        QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation),
        QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation),
        QStandardPaths::writableLocation(QStandardPaths::CacheLocation),
        QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation),
        home.isEmpty() ? QString() : QDir(home).filePath(QStringLiteral("Library/Application Support")),
        home.isEmpty() ? QString() : QDir(home).filePath(QStringLiteral(".local/share")),
        home.isEmpty() ? QString() : QDir(home).filePath(QStringLiteral("Library/Caches")),
        home.isEmpty() ? QString() : QDir(home).filePath(QStringLiteral(".cache")),
        home,
        QDir::currentPath()
    };
    for (const QString &root : candidates) {
        const QString dir = parallelShelfPickDir(root);
        if (!dir.isEmpty())
            return dir;
    }
    return parallelShelfCacheDir();
}

// Muster sealFile: 64 KiB read of src into the work dir, then uploadUrl that
// dest. Do not require QFileInfo::isFile() first — Mac TCC can make isFile()
// lie while a ReadOnly open still works. Never write dest under ~/Downloads
// or global /tmp: Storage cannot QFile-open those.
inline QString parallelShelfStageShare(const QString &raw)
{
    const QString src = parallelShelfPath(raw);
    if (src.isEmpty() || src.at(0) != QLatin1Char('/'))
        return QString();
    QString dir = parallelShelfWorkDir();
    if (dir.isEmpty() || dir.at(0) != QLatin1Char('/') || parallelShelfIsGlobalTmp(dir)
            || dir.contains(QLatin1String("/Downloads/")))
        dir = parallelShelfCacheDir();
    if (dir.isEmpty() || dir.at(0) != QLatin1Char('/') || parallelShelfIsGlobalTmp(dir)
            || dir.contains(QLatin1String("/Downloads/")))
        return QString();
    QDir().mkpath(dir);
    QString name = QFileInfo(src).fileName();
    name.replace(QLatin1Char('/'), QLatin1Char('_'));
    if (name.isEmpty())
        name = QStringLiteral("file.bin");
    const QString dest = QDir(dir).filePath(
        QStringLiteral("parallel-shelf-stage-%1-%2")
            .arg(QString::number(QDateTime::currentMSecsSinceEpoch()), name));
    if (dest.contains(QLatin1String("/Downloads/")) || parallelShelfIsGlobalTmp(dest))
        return QString();
    if (QFile::exists(dest))
        QFile::remove(dest);
    QFile in(src);
    if (!in.open(QIODevice::ReadOnly))
        return QString();
    QFile out(dest);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        in.close();
        return QString();
    }
    // Muster SealChunkBytes = 65536.
    char buf[65536];
    qint64 total = 0;
    for (;;) {
        const qint64 n = in.read(buf, sizeof(buf));
        if (n < 0) {
            in.close();
            out.close();
            QFile::remove(dest);
            return QString();
        }
        if (n == 0)
            break;
        if (out.write(buf, n) != n) {
            in.close();
            out.close();
            QFile::remove(dest);
            return QString();
        }
        total += n;
    }
    in.close();
    out.close();
    if (total <= 0) {
        QFile::remove(dest);
        return QString();
    }
    return dest;
}

#pragma once

#include "file_read.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QProcess>
#include <QProcessEnvironment>
#include <QStandardPaths>
#include <QStringList>

#include <cstring>

#if defined(Q_OS_UNIX)
#include <dlfcn.h>
#endif
#if defined(Q_OS_MACOS)
#include <mach-o/dyld.h>
#endif

// Rasterize one PDF page in this Logos core process with poppler pdftoppm.
// Do not link Qt Pdf / Qt WebEngine / QPdfDocument — that crash-loads logoscore
// on Mac Basecamp. Return a short AppData path (page-<cid>-N.png). The view copies
// that PNG next to PdfPages.qml as page-<cid>-N.png via QFile of the path
// PdfPages.pathFor resolved (never file://, never data:, never a QML
// XHR PUT, never a guessed host qml dir). pdftoppm lives in
// variants/<plat>/bin so
// logoscore does not dlopen libpoppler beside the plugin.

// Lives in this core dylib's data, not logoscore. Taking the address of an
// inline empty function was inlined away on Mac 0.44.0, so dladdr pointed at
// the host and bin/pdftoppm next to the plugin was never searched.
inline const void *parallelShelfPluginAnchor()
{
    static volatile int k = 45;
    return const_cast<int *>(&k);
}

inline void parallelShelfAddPpm(QStringList *bins, const QString &path)
{
    if (!bins || path.isEmpty() || bins->contains(path))
        return;
    *bins << path;
}

// Relatives at every parent of the plugin / unpack root. Never a sibling
// named pdftoppm in the plugin directory (0.43.0 crash-opened).
inline QStringList parallelShelfPdftoppmRelatives()
{
    return QStringList()
            << QStringLiteral("bin/pdftoppm")
            << QStringLiteral("lib/bin/pdftoppm")
            << QStringLiteral("Contents/MacOS/bin/pdftoppm")
            << QStringLiteral("darwin-arm64/bin/pdftoppm")
            << QStringLiteral("darwin-arm64-dev/bin/pdftoppm")
            << QStringLiteral("linux-amd64/bin/pdftoppm")
            << QStringLiteral("linux-amd64-dev/bin/pdftoppm")
            << QStringLiteral("variants/darwin-arm64/bin/pdftoppm")
            << QStringLiteral("variants/darwin-arm64-dev/bin/pdftoppm")
            << QStringLiteral("variants/linux-amd64/bin/pdftoppm")
            << QStringLiteral("variants/linux-amd64-dev/bin/pdftoppm")
            << QStringLiteral("parallel_shelf_core/variants/darwin-arm64/bin/pdftoppm")
            << QStringLiteral("parallel_shelf_core/variants/darwin-arm64-dev/bin/pdftoppm")
            << QStringLiteral("parallel_shelf_core/variants/linux-amd64/bin/pdftoppm")
            << QStringLiteral("parallel_shelf_core/variants/linux-amd64-dev/bin/pdftoppm");
}

inline bool parallelShelfSkipPaintPath(const QString &path)
{
    if (path.isEmpty() || path.at(0) != QLatin1Char('/'))
        return true;
    if (parallelShelfIsGlobalTmp(path))
        return true;
    if (path.contains(QLatin1String("/Downloads/")))
        return true;
    return false;
}

inline QString parallelShelfPdfForCid(const QString &cid)
{
    const QString hold = parallelShelfReadHold(cid);
    if (!parallelShelfSkipPaintPath(hold) && parallelShelfFileSize(hold) > 4)
        return hold;
    const QString src = parallelShelfReadSource(cid);
    if (!parallelShelfSkipPaintPath(src) && parallelShelfFileSize(src) > 4)
        return src;
    const QString file = parallelShelfHoldFile(cid);
    if (!parallelShelfSkipPaintPath(file) && parallelShelfFileSize(file) > 4)
        return file;
    return QString();
}

inline bool parallelShelfIsViewPngDest(const QString &raw)
{
    const QString path = parallelShelfPath(raw);
    if (path.isEmpty() || path.at(0) != QLatin1Char('/'))
        return false;
    if (!path.endsWith(QLatin1String(".png")))
        return false;
    if (path.contains(QLatin1String(".."))
            || path.contains(QLatin1String("/Downloads/"))
            || parallelShelfIsGlobalTmp(path))
        return false;
    const QString name = QFileInfo(path).fileName();
    if (!name.startsWith(QLatin1String("page-"))
            || !name.endsWith(QLatin1String(".png")))
        return false;
    if (name.contains(QLatin1Char('/')) || name.contains(QLatin1Char(':')))
        return false;
    const QString dir = QFileInfo(path).absolutePath();
    if (dir.isEmpty() || dir.contains(QLatin1String(".qml")))
        return false;
    return QFileInfo(dir).isDir();
}

inline QString parallelShelfPagePngPath(const QString &cid, int page)
{
    QString dir = parallelShelfCacheDir();
    if (dir.isEmpty() || dir.at(0) != QLatin1Char('/'))
        return QString();
    QDir().mkpath(dir);
    QString key;
    for (int i = 0; i < cid.size() && key.size() < 40; ++i) {
        const QChar c = cid.at(i);
        if (c.isLetterOrNumber() || c == QLatin1Char('-') || c == QLatin1Char('_'))
            key += c;
    }
    if (key.isEmpty())
        key = QStringLiteral("page");
    return QDir(dir).filePath(QStringLiteral("%1-p%2.png").arg(key, QString::number(qMax(0, page))));
}

inline bool parallelShelfPngReady(const QString &path)
{
    if (path.isEmpty() || path.at(0) != QLatin1Char('/'))
        return false;
    if (parallelShelfFileSize(path) < 32)
        return false;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return false;
    const QByteArray head = f.read(8);
    return head.startsWith("\x89PNG");
}

inline void parallelShelfCollectPdftoppm(QStringList *bins, const QDir &start)
{
    if (!bins)
        return;
    QDir dir = start;
    const QStringList rel = parallelShelfPdftoppmRelatives();
    for (int i = 0; i < 16; ++i) {
        for (const QString &r : rel)
            parallelShelfAddPpm(bins, dir.filePath(r));
        if (!dir.cdUp())
            break;
    }
}

inline void parallelShelfCollectFromPluginFile(QStringList *bins, const QString &pluginPath)
{
    if (!bins || pluginPath.isEmpty())
        return;
    QString path = pluginPath;
    if (path.startsWith(QLatin1String("@rpath/")) || path.startsWith(QLatin1String("@")))
        return;
    QFileInfo plug(path);
    if (!plug.isAbsolute()) {
        const QString app = QCoreApplication::applicationDirPath();
        if (!app.isEmpty())
            plug = QFileInfo(QDir(app).filePath(path));
    }
    if (!plug.exists() && QFileInfo::exists(path))
        plug = QFileInfo(path);
    parallelShelfCollectPdftoppm(bins, plug.absoluteDir());
}

inline bool parallelShelfPpmLooksPresent(const QString &path)
{
    if (path.isEmpty() || path.at(0) != QLatin1Char('/'))
        return false;
    const QFileInfo fi(path);
    if (fi.isDir())
        return false;
    // Do not require isFile()/isExecutable(): Mac extract may drop +x, and
    // chmod of the bundled Mach-O invalidates codesign. Still count it found.
    return fi.exists() || QFile::exists(path);
}

inline QStringList parallelShelfPdftoppmCandidates()
{
    QStringList bins;
    if (!qgetenv("PARALLEL_SHELF_NO_PDFTOPPM").isEmpty())
        return bins;

    const QByteArray env = qgetenv("PARALLEL_SHELF_PDFTOPPM");
    if (!env.isEmpty())
        parallelShelfAddPpm(&bins, QString::fromLocal8Bit(env));

    // Prefer the binary shipped in this lgx under variants/<plat>/bin,
    // never a sibling of the plugin. Mac logoscore PATH has no pdftoppm.
#if defined(Q_OS_UNIX)
    Dl_info info;
    info.dli_fname = nullptr;
    info.dli_fbase = nullptr;
    info.dli_sname = nullptr;
    info.dli_saddr = nullptr;
    if (dladdr(parallelShelfPluginAnchor(), &info)
            && info.dli_fname && info.dli_fname[0])
        parallelShelfCollectFromPluginFile(&bins, QString::fromLocal8Bit(info.dli_fname));
#endif
#if defined(Q_OS_MACOS)
    const uint32_t nimg = _dyld_image_count();
    for (uint32_t i = 0; i < nimg; ++i) {
        const char *name = _dyld_get_image_name(i);
        if (!name || !name[0])
            continue;
        if (!std::strstr(name, "parallel_shelf_core_plugin"))
            continue;
        parallelShelfCollectFromPluginFile(&bins, QString::fromLocal8Bit(name));
    }
#endif

    const QString app = QCoreApplication::applicationDirPath();
    if (!app.isEmpty())
        parallelShelfCollectPdftoppm(&bins, QDir(app));

    const QList<QStandardPaths::StandardLocation> locs = {
        QStandardPaths::AppDataLocation,
        QStandardPaths::AppLocalDataLocation,
        QStandardPaths::GenericDataLocation,
        QStandardPaths::CacheLocation,
        QStandardPaths::HomeLocation,
    };
    for (QStandardPaths::StandardLocation loc : locs) {
        const QStringList roots = QStandardPaths::standardLocations(loc);
        for (const QString &root : roots) {
            if (root.isEmpty())
                continue;
            parallelShelfCollectPdftoppm(&bins, QDir(root));
            parallelShelfCollectPdftoppm(&bins, QDir(root + QStringLiteral("/modules")));
            parallelShelfCollectPdftoppm(&bins, QDir(root + QStringLiteral("/Logos")));
            parallelShelfCollectPdftoppm(&bins, QDir(root + QStringLiteral("/logoscore")));
            parallelShelfCollectPdftoppm(&bins, QDir(root + QStringLiteral("/Basecamp")));
        }
    }

    const QString found = QStandardPaths::findExecutable(QStringLiteral("pdftoppm"));
    if (!found.isEmpty())
        parallelShelfAddPpm(&bins, found);

    parallelShelfAddPpm(&bins, QStringLiteral("/usr/bin/pdftoppm"));
    parallelShelfAddPpm(&bins, QStringLiteral("/opt/homebrew/bin/pdftoppm"));
    parallelShelfAddPpm(&bins, QStringLiteral("/usr/local/bin/pdftoppm"));
    parallelShelfAddPpm(&bins, QStringLiteral("/opt/local/bin/pdftoppm"));
    return bins;
}

inline QString parallelShelfPdftoppmBin()
{
    const QStringList bins = parallelShelfPdftoppmCandidates();
    for (const QString &b : bins) {
        if (parallelShelfPpmLooksPresent(b))
            return QFileInfo(b).absoluteFilePath();
    }
    return QString();
}

// Do not chmod the bundled Mach-O (breaks codesign). Copy to AppData and
// chmod the copy when the extract has no +x. Dylibs stay next to that copy,
// never beside the plugin.
inline QString parallelShelfPreparePdftoppm(const QString &bin)
{
    QFileInfo fi(bin);
    if (!parallelShelfPpmLooksPresent(bin))
        return QString();
    const QString src = fi.absoluteFilePath();
    if (fi.isExecutable())
        return src;
    QString dir = parallelShelfCacheDir();
    if (dir.isEmpty() || dir.at(0) != QLatin1Char('/'))
        return src;
    dir += QStringLiteral("/pdftoppm-bin");
    QDir().mkpath(dir);
    const QString dest = QDir(dir).filePath(QStringLiteral("pdftoppm"));
    QFile::remove(dest);
    if (!QFile::copy(src, dest) && !QFile::exists(dest))
        return src;
    const QDir srcDir = fi.absoluteDir();
    const QStringList names = srcDir.entryList(QDir::Files);
    for (const QString &name : names) {
        if (name == QLatin1String("pdftoppm"))
            continue;
        if (!name.contains(QLatin1String("poppler"))
                && !name.endsWith(QLatin1String(".dylib"))
                && !name.contains(QLatin1String(".so")))
            continue;
        const QString to = QDir(dir).filePath(name);
        QFile::remove(to);
        QFile::copy(srcDir.filePath(name), to);
    }
    QFile::setPermissions(dest,
            QFileDevice::ReadOwner | QFileDevice::WriteOwner
            | QFileDevice::ExeOwner | QFileDevice::ExeUser
            | QFileDevice::ReadUser);
    return dest;
}

inline void parallelShelfKillProc(QProcess *proc)
{
    if (!proc || proc->state() == QProcess::NotRunning)
        return;
    proc->kill();
    proc->waitForFinished(1000);
}

inline QString parallelShelfRasterPng(const QString &cid, const QString &pdf, int page, int width,
                                     const QString &destHint)
{
    QString dest = destHint;
    if (!parallelShelfIsViewPngDest(dest))
        dest = parallelShelfPagePngPath(cid, page);
    if (dest.isEmpty())
        return QString();
    if (parallelShelfPngReady(dest))
        return dest;

    const QStringList cands = parallelShelfPdftoppmCandidates();
    QStringList present;
    for (const QString &c : cands) {
        if (parallelShelfPpmLooksPresent(c))
            present << QFileInfo(c).absoluteFilePath();
    }
    if (present.isEmpty())
        return QString();

    const QString dir = QFileInfo(dest).absolutePath();
    const QString prefix = QDir(dir).filePath(QStringLiteral("ppm-%1").arg(page));
    const int dpi = 72;
    auto run = [&](const QString &rawBin, bool single) -> bool {
        const QString bin = parallelShelfPreparePdftoppm(rawBin);
        if (bin.isEmpty())
            return false;
        QProcess proc;
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        // Only the bin/ dir (pdftoppm + its dylibs). Do not add the plugin
        // directory — that re-exposes poppler on logoscore's load path.
        const QString libdir = QFileInfo(bin).absolutePath();
        env.insert(QStringLiteral("LD_LIBRARY_PATH"), libdir);
        env.insert(QStringLiteral("DYLD_LIBRARY_PATH"), libdir);
        env.insert(QStringLiteral("DYLD_FALLBACK_LIBRARY_PATH"), libdir);
        proc.setProcessEnvironment(env);
        QStringList args;
        args << QStringLiteral("-png");
        if (single)
            args << QStringLiteral("-singlefile");
        args << QStringLiteral("-f") << QString::number(page + 1)
             << QStringLiteral("-l") << QString::number(page + 1)
             << QStringLiteral("-r") << QString::number(dpi)
             << pdf
             << prefix;
        proc.start(bin, args);
        if (!proc.waitForStarted(2000)) {
            parallelShelfKillProc(&proc);
            return false;
        }
        if (!proc.waitForFinished(8000)) {
            parallelShelfKillProc(&proc);
            return false;
        }
        return proc.exitStatus() == QProcess::NormalExit && proc.exitCode() == 0;
    };
    bool ran = false;
    for (const QString &raw : present) {
        if (run(raw, true) || run(raw, false)) {
            ran = true;
            break;
        }
    }
    if (!ran)
        return QString();

    QString got = prefix + QStringLiteral(".png");
    if (!QFile::exists(got))
        got = prefix + QStringLiteral("-") + QString::number(page + 1)
                + QStringLiteral(".png");
    if (!QFile::exists(got)) {
        const QString stem = QFileInfo(prefix).fileName();
        const QStringList matches = QDir(dir).entryList(
                    QStringList() << (stem + QLatin1String(".png"))
                                  << (stem + QLatin1String("-*.png")));
        if (matches.isEmpty())
            return QString();
        got = QDir(dir).filePath(matches.first());
    }
    if (got != dest) {
        QFile::remove(dest);
        if (!QFile::rename(got, dest)) {
            if (!QFile::copy(got, dest)) {
                QFile::remove(got);
                return QString();
            }
            QFile::remove(got);
        }
    }
    if (!parallelShelfPngReady(dest)) {
        QFile::remove(dest);
        return QString();
    }
    return dest;
}

inline QString parallelShelfRenderPage(const QString &rawCid, int page, int width,
                                      const QString &destHint = QString())
{
    const QString cid = rawCid.trimmed();
    if (cid.isEmpty() || page < 0)
        return QString();
    const QString cached = parallelShelfPagePngPath(cid, page);
    QString viewDest;
    if (parallelShelfIsViewPngDest(destHint))
        viewDest = parallelShelfPath(destHint);
    if (!viewDest.isEmpty()) {
        if (parallelShelfPngReady(cached)
                && parallelShelfCopyFile(cached, viewDest)
                && parallelShelfPngReady(viewDest))
            return viewDest;
        const QString pdf = parallelShelfPdfForCid(cid);
        if (pdf.isEmpty())
            return QString();
        return parallelShelfRasterPng(cid, pdf, page, qBound(400, width, 800), viewDest);
    }
    if (parallelShelfPngReady(cached))
        return cached;
    const QString pdf = parallelShelfPdfForCid(cid);
    if (pdf.isEmpty())
        return QString();
    return parallelShelfRasterPng(cid, pdf, page, qBound(400, width, 800), QString());
}

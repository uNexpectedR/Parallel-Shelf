#include "file_read.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QString>
#include <cstdio>

static bool isFileInGlobalTmp(const QString &dest)
{
    return parallelShelfIsGlobalTmp(dest)
        || parallelShelfIsGlobalTmp(QFileInfo(dest).absolutePath());
}

static int proveNeverEmpty(const char *label)
{
    const QString cases[][2] = {
        { QStringLiteral("mwgvu2lo-9qytof"), QStringLiteral("pdf") },
        { QString(), QString() },
        { QStringLiteral("!!!"), QStringLiteral("exe") },
        { QStringLiteral("ok-id"), QStringLiteral("PDF") },
        { QStringLiteral("x"), QStringLiteral("mp3") }
    };
    for (const auto &pair : cases) {
        const QString dest = parallelShelfFetchDest(pair[0], pair[1]);
        const QString dir = QFileInfo(dest).absolutePath();
        const bool existsDir = QFileInfo(dir).isDir();
        std::printf("FETCHDEST %s dest=%s dir=%s mkdir=%d empty=%d global_tmp_file=%d\n",
                    label, qPrintable(dest), qPrintable(dir),
                    existsDir ? 1 : 0, dest.isEmpty() ? 1 : 0,
                    isFileInGlobalTmp(dest) ? 1 : 0);
        if (dest.isEmpty() || dest.at(0) != QLatin1Char('/') || isFileInGlobalTmp(dest))
            return 1;
        QDir().mkpath(dir);
        if (!QFileInfo(dir).isDir())
            return 1;
    }
    return 0;
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (proveNeverEmpty("no-app-name") != 0)
        return 1;
    app.setOrganizationName(QStringLiteral("parallel-shelf"));
    app.setApplicationName(QStringLiteral("parallel-shelf"));
    if (proveNeverEmpty("named") != 0)
        return 1;
    const QByteArray oldHome = qgetenv("HOME");
    qputenv("HOME", "/tmp");
    const QString homeTmpDir = parallelShelfCacheDir();
    std::printf("CACHEDIR home-is-tmp dir=%s global_tmp=%d\n",
                qPrintable(homeTmpDir),
                (homeTmpDir.isEmpty() || isFileInGlobalTmp(homeTmpDir)) ? 1 : 0);
    if (homeTmpDir.isEmpty() || homeTmpDir.at(0) != QLatin1Char('/')
            || isFileInGlobalTmp(homeTmpDir) || proveNeverEmpty("home-is-tmp") != 0)
        return 1;
    if (!oldHome.isEmpty())
        qputenv("HOME", oldHome);
    else
        qunsetenv("HOME");
    const QString id = argc > 1 ? QString::fromLocal8Bit(argv[1]) : QStringLiteral("mwgvu2lo-9qytof");
    const QString ext = argc > 2 ? QString::fromLocal8Bit(argv[2]) : QStringLiteral("pdf");
    const QString dest = parallelShelfFetchDest(id, ext);
    const QString dir = QFileInfo(dest).absolutePath();
    std::printf("FETCHDEST dest=%s dir=%s mkdir=%d global_tmp=%d\n",
                qPrintable(dest), qPrintable(dir),
                QFileInfo(dir).isDir() ? 1 : 0, isFileInGlobalTmp(dest) ? 1 : 0);
    if (dest.isEmpty() || dest.at(0) != QLatin1Char('/') || !QFileInfo(dir).isDir()
            || isFileInGlobalTmp(dest))
        return 1;
    if (argc > 3) {
        const QString written = QString::fromLocal8Bit(argv[3]);
        const qint64 n = parallelShelfFileSize(written);
        const QString head = parallelShelfReadPiece(written, 0, 5);
        std::printf("FETCHDEST_OPEN size=%lld head=%s path=%s\n",
                    static_cast<long long>(n), qPrintable(head), qPrintable(written));
        return (n > 0 && head == QLatin1String("%PDF-")) ? 0 : 2;
    }
    return 0;
}

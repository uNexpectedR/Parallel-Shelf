#include "file_read.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QString>
#include <cstdio>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("parallel-shelf-tests"));
    app.setApplicationName(QStringLiteral("parallel-shelf-tests"));

    const QString cid = QStringLiteral("zDvHoldMapTestCid");
    const QString hold = parallelShelfHoldFile(cid);
    if (hold.isEmpty() || hold.at(0) != QLatin1Char('/') || parallelShelfIsGlobalTmp(hold)) {
        std::printf("HOLD_MAP no hold path\n");
        return 1;
    }
    const QString piece = QStringLiteral("%PDF-hold");
    if (!parallelShelfWritePiece(hold, 0, piece)) {
        std::printf("HOLD_MAP writePiece failed path=%s\n", qPrintable(hold));
        return 1;
    }
    if (!parallelShelfWriteHold(cid, hold)) {
        std::printf("HOLD_MAP writeHold failed\n");
        return 1;
    }
    const QString sidecar = hold + QStringLiteral(".cid");
    const QString index = QDir(QFileInfo(hold).absolutePath())
            .filePath(QStringLiteral("parallel-shelf-holds.json"));
    if (!QFileInfo(sidecar).isFile() || !QFileInfo(index).isFile()) {
        std::printf("HOLD_MAP missing sidecar=%d index=%d dir=%s\n",
                    QFileInfo(sidecar).isFile() ? 1 : 0,
                    QFileInfo(index).isFile() ? 1 : 0,
                    qPrintable(QFileInfo(hold).absolutePath()));
        return 1;
    }
    const QString got = parallelShelfReadHold(cid);
    std::printf("HOLD_MAP hold=%s got=%s sidecar=1 index=1\n",
                qPrintable(hold), qPrintable(got));
    if (got != hold)
        return 2;
    if (parallelShelfFileSize(got) <= 0)
        return 2;

    const QString src = QDir::temp().filePath(QStringLiteral("ps-keep-hold-src.bin"));
    QFile srcFile(src);
    if (!srcFile.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return 3;
    srcFile.write("%PDF-keep");
    srcFile.close();
    const QString key = QStringLiteral("share-keep-hold");
    if (parallelShelfHoldRead(src, 0, 9, key) != QStringLiteral("%PDF-keep"))
        return 3;
    const QString keptCid = QStringLiteral("zDvKeepHoldTestCid");
    const QString kept = parallelShelfKeepHold(key, keptCid);
    if (kept.isEmpty() || parallelShelfFileSize(kept) != 9)
        return 3;
    if (parallelShelfReadHold(keptCid) != kept)
        return 3;

    const QString choose = QStringLiteral("/Users/unexpectedr/Downloads/farewell-to-westphalia-foss-edition.pdf");
    const QString sourceCid = QStringLiteral("zDvRememberSourceCid");
    if (!parallelShelfRememberSource(sourceCid, choose)) {
        std::printf("HOLD_MAP rememberSource failed\n");
        return 4;
    }
    if (parallelShelfReadSource(sourceCid) != choose) {
        std::printf("HOLD_MAP readSource=%s\n", qPrintable(parallelShelfReadSource(sourceCid)));
        return 4;
    }
    if (!parallelShelfRememberSource(sourceCid, QString()))
        return 4;
    if (!parallelShelfReadSource(sourceCid).isEmpty())
        return 4;
    if (!parallelShelfRememberSource(sourceCid, choose))
        return 4;

    const QString copyDest = QDir(QFileInfo(hold).absolutePath())
            .filePath(QStringLiteral("parallel-shelf-copy.bin"));
    if (!parallelShelfCopyFile(hold, copyDest)) {
        std::printf("HOLD_MAP copyFile failed\n");
        return 5;
    }
    if (parallelShelfFileSize(copyDest) != parallelShelfFileSize(hold))
        return 5;
    return 0;
}

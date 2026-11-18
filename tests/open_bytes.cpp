#include "file_read.h"

#include <QByteArray>
#include <QFile>
#include <QString>
#include <cstdio>

// Dest-empty Open: downloadChunks pieces land in core memory:<cid>.
// mkdir is not consulted. No dest file is written.
int main(int argc, char **argv)
{
    const QString pdf = argc > 1
        ? QString::fromLocal8Bit(argv[1])
        : QStringLiteral("/cursor/stores/bc-a13b448c-7ad4-47f5-a01c-a53f4b3ed883/internal/farewell-to-westphalia-foss-edition.pdf");
    QFile file(pdf);
    if (!file.open(QIODevice::ReadOnly)) {
        std::printf("OPEN_BYTES missing %s\n", qPrintable(pdf));
        return 1;
    }
    const QByteArray all = file.readAll();
    file.close();
    if (all.size() != 2276462 || !all.startsWith("%PDF-")) {
        std::printf("OPEN_BYTES disk size=%lld head=%.5s\n",
                    static_cast<long long>(all.size()), all.constData());
        return 1;
    }

    const QString key = QStringLiteral("memory:zDvZRwzkzrrYB6sS1rRpRLt4gBhc1pWoyTSjkfszfmj1seaYYLCZ");
    const int piece = 8192;
    for (int at = 0; at < all.size(); at += piece) {
        const QByteArray chunk = all.mid(at, piece);
        QString latin;
        latin.resize(chunk.size());
        for (int i = 0; i < chunk.size(); ++i)
            latin[i] = QChar(static_cast<uchar>(chunk.at(i)));
        if (!parallelShelfWritePiece(key, at, latin)) {
            std::printf("OPEN_BYTES writePiece failed at %d\n", at);
            return 1;
        }
    }

    const qint64 n = parallelShelfFileSize(key);
    const QString head = parallelShelfReadPiece(key, 0, 5);
    std::printf("OPEN_BYTES size=%lld head=%s dest=none mkdir_ignored=1\n",
                static_cast<long long>(n), qPrintable(head));
    if (n != 2276462 || head != QLatin1String("%PDF-"))
        return 2;
    return 0;
}

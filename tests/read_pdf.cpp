#include "file_read.h"

#include <QString>
#include <cstdio>

int main(int argc, char **argv)
{
    const QString path = argc > 1
        ? QString::fromLocal8Bit(argv[1])
        : QStringLiteral("/tmp/parallel-shelf-tests/Users/unexpectedr/Downloads/farewell-to-westphalia-foss-edition.pdf");
    const qint64 n = parallelShelfFileSize(path);
    const QString head = parallelShelfReadPiece(path, 0, 5);
    const QString nul = parallelShelfReadPiece(path, 819, 1);
    const int nulCode = nul.isEmpty() ? -1 : int(nul.at(0).unicode());
    const QString dest = parallelShelfStageShare(path);
    const qint64 staged = dest.isEmpty() ? -1 : parallelShelfFileSize(dest);
    std::printf("FILEBYTES_OK size=%lld head=%s nul=%d path=%s staged=%s stagedSize=%lld\n",
                static_cast<long long>(n), qPrintable(head), nulCode, qPrintable(path),
                qPrintable(dest), static_cast<long long>(staged));
    const bool copied = dest.startsWith(QLatin1Char('/'))
            && !dest.contains(QLatin1String("/Downloads/"))
            && staged == n;
    return (n == 2276462 && head == QLatin1String("%PDF-") && nulCode == 0 && copied) ? 0 : 1;
}

#include "file_read.h"
#include "page_render.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QRgb>
#include <QString>
#include <cstdio>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    const QString pdf = argc > 1
        ? QString::fromLocal8Bit(argv[1])
        : QStringLiteral("/cursor/stores/bc-a13b448c-7ad4-47f5-a01c-a53f4b3ed883/internal/farewell-to-westphalia-foss-edition.pdf");
    const QString cid = QStringLiteral("zDvRenderPage48");
    if (!parallelShelfWriteHold(cid, pdf)) {
        std::fprintf(stderr, "RENDER_FAIL writeHold\n");
        return 1;
    }

    {
        const QString root = QStringLiteral("/tmp/parallel-shelf-tests/mac-unpack");
        QDir().mkpath(root + QStringLiteral("/variants/darwin-arm64/bin"));
        QFile plug(root + QStringLiteral("/variants/darwin-arm64/parallel_shelf_core_plugin.dylib"));
        if (!plug.open(QIODevice::WriteOnly) || plug.write("dylib") < 1) {
            std::fprintf(stderr, "FIND_FAIL write plugin\n");
            return 1;
        }
        plug.close();
        const QString ppm = root + QStringLiteral("/variants/darwin-arm64/bin/pdftoppm");
        QFile b(ppm);
        if (!b.open(QIODevice::WriteOnly) || b.write("ppm") < 1) {
            std::fprintf(stderr, "FIND_FAIL write bin/pdftoppm\n");
            return 1;
        }
        b.close();
        QFile sib(root + QStringLiteral("/variants/darwin-arm64/pdftoppm"));
        if (!sib.open(QIODevice::WriteOnly) || sib.write("sibling") < 1) {
            std::fprintf(stderr, "FIND_FAIL write sibling\n");
            return 1;
        }
        sib.close();
        QStringList bins;
        parallelShelfCollectFromPluginFile(&bins,
                root + QStringLiteral("/variants/darwin-arm64/parallel_shelf_core_plugin.dylib"));
        bool hit = false;
        bool sibling = false;
        const QString want = QFileInfo(ppm).absoluteFilePath();
        const QString bad = QFileInfo(sib).absoluteFilePath();
        for (const QString &p : bins) {
            if (QFileInfo(p).absoluteFilePath() == want)
                hit = true;
            if (QFileInfo(p).absoluteFilePath() == bad)
                sibling = true;
        }
        if (!hit || sibling || !parallelShelfPpmLooksPresent(ppm)) {
            std::fprintf(stderr, "FIND_FAIL hit=%d sibling=%d present=%d\n",
                         int(hit), int(sibling), int(parallelShelfPpmLooksPresent(ppm)));
            return 1;
        }
        bool relOk = false;
        const QStringList rel = parallelShelfPdftoppmRelatives();
        for (const QString &r : rel) {
            if (r == QLatin1String("variants/darwin-arm64/bin/pdftoppm")
                    || r == QLatin1String("bin/pdftoppm"))
                relOk = true;
        }
        if (!relOk) {
            std::fprintf(stderr, "FIND_FAIL relatives missing bin/pdftoppm\n");
            return 1;
        }
        std::printf("FIND_OK plugin-dir bin/pdftoppm (not sibling) relatives=%d\n",
                    int(rel.size()));
    }

    qputenv("PARALLEL_SHELF_NO_PDFTOPPM", "1");
    if (!parallelShelfPdftoppmBin().isEmpty()) {
        std::fprintf(stderr, "TIMEOUT_FAIL pdftoppm bin still found\n");
        return 1;
    }
    const QString miss = parallelShelfRenderPage(cid, 17, 800);
    if (!miss.isEmpty()) {
        std::fprintf(stderr, "TIMEOUT_FAIL missing pdftoppm returned %s\n",
                     qPrintable(miss.left(80)));
        return 1;
    }
    std::printf("TIMEOUT_OK missing pdftoppm returns empty\n");
    qputenv("PARALLEL_SHELF_NO_PDFTOPPM", QByteArray());
    qunsetenv("PARALLEL_SHELF_NO_PDFTOPPM");

    const QString path = parallelShelfRenderPage(cid, 11, 800);
    if (path.isEmpty() || path.at(0) != QLatin1Char('/')
            || !path.endsWith(QLatin1String(".png"))
            || path.startsWith(QLatin1String("data:"))) {
        std::fprintf(stderr, "RENDER_FAIL path=%s\n", qPrintable(path.left(80)));
        return 1;
    }
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        std::fprintf(stderr, "RENDER_FAIL open %s\n", qPrintable(path));
        return 1;
    }
    const QByteArray png = f.readAll();
    f.close();
    if (png.size() < 32 || !png.startsWith("\x89PNG")) {
        std::fprintf(stderr, "RENDER_FAIL png bytes=%d\n", int(png.size()));
        return 1;
    }
    const QString out = QStringLiteral("/tmp/parallel-shelf-tests/page-11.png");
    QDir().mkpath(QFileInfo(out).absolutePath());
    QFile copy(out);
    if (!copy.open(QIODevice::WriteOnly) || copy.write(png) != png.size()) {
        std::fprintf(stderr, "RENDER_FAIL write %s\n", qPrintable(out));
        return 1;
    }
    copy.close();
    const QImage img = QImage::fromData(png, "PNG");
    int ink = 0;
    for (int y = 0; y < img.height(); ++y) {
        for (int x = 0; x < img.width(); ++x) {
            const QRgb p = img.pixel(x, y);
            if ((qRed(p) + qGreen(p) + qBlue(p)) / 3 < 180)
                ++ink;
        }
    }
    const double ratio = img.width() * img.height() > 0
            ? double(ink) / double(img.width() * img.height()) : 0;
    std::printf("RENDER_OK path=%s %dx%d ink=%d ratio=%.4f renderer=pdftoppm\n",
                qPrintable(out), img.width(), img.height(), ink, ratio);
    if (img.width() < 200 || img.height() < 200 || ink < 4000 || ratio < 0.01)
        return 1;

    qputenv("PARALLEL_SHELF_NO_PDFTOPPM", "1");
    const QString cached = parallelShelfRenderPage(cid, 11, 800);
    if (cached != path) {
        std::fprintf(stderr, "CACHE_FAIL got=%s want=%s\n",
                     qPrintable(cached.left(80)), qPrintable(path.left(80)));
        return 1;
    }
    std::printf("CACHE_OK Open is a local read of %s\n", qPrintable(path));
    qunsetenv("PARALLEL_SHELF_NO_PDFTOPPM");
    return 0;
}

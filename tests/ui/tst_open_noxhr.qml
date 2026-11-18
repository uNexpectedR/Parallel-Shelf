import QtQuick 2.15
import QtTest 1.2
import Qt.labs.settings 1.0
import "../../src/qml"
import "../../src/qml/catalog.js" as Catalog

// Mac Basecamp does not allow QML XHR PUT into the view qml dir (0.47.0).
// Open must paint via core QFile of PdfPages.pathFor. This file is run with
// QML_XHR_ALLOW_FILE_WRITE unset.
Item {
    id: bench
    width: 960
    height: 680

    Component { id: networkMaker; FakeNetwork {} }
    Component { id: installMaker; Install {} }
    Component { id: memoryMaker; Settings { category: "parallel_shelf_v1" } }

    TestCase {
        name: "OpenNoXhr"
        when: windowShown

        property var network: null
        property var memory: null

        function initTestCase() {
            Qt.application.organization = "parallel-shelf-tests"
            Qt.application.domain = "parallel-shelf.test"
            memory = memoryMaker.createObject(bench)
        }

        function init() {
            memory.setValue("catalog", "")
            memory.setValue("shelf", "")
            memory.setValue("epoch", "")
            memory.sync()
            network = createTemporaryObject(networkMaker, bench)
        }

        function test_open_paints_without_qml_xhr_put() {
            var proof = "/cursor/stores/bc-a13b448c-7ad4-47f5-a01c-a53f4b3ed883/internal/farewell-to-westphalia-foss-edition.pdf"
            var ana = createTemporaryObject(installMaker, bench, { network: network })
            var library = ana.shelf.library
            tryVerify(function () {
                return library.storageState === "running" && library.deliveryState === "running"
            }, 5000, "Storage and Delivery start")
            library.share("Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", proof)
            tryVerify(function () { return !library.sharing && library.works.length === 1 }, 20000,
                      "Share finished")
            var work = library.works[0]
            ana.shelf.open({
                id: work.id,
                title: work.title,
                author: work.author,
                kind: work.kind,
                filename: work.filename,
                cid: work.cid,
                size: work.size,
                addedAt: work.addedAt
            })
            tryVerify(function () {
                var pdf = String(ana.shelf.readingPdf || "")
                return ana.shelf.readingPages.length === 381 && pdf.indexOf("%PDF-") === 0
            }, 20000, "Open loads Farewell")
            tryVerify(function () {
                var url = String(ana.shelf.readingPdfUrl)
                var item = ana.shelf.readerPanel.pdfEngine.item
                var img = item ? findChild(item, "pdfImage") : null
                return url.indexOf("page-0-") === 0
                        && url.indexOf(".png") === url.length - 4
                        && url.indexOf(":") < 0
                        && url.indexOf("/") < 0
                        && item
                        && item.status === Image.Ready
                        && img
                        && img.status === Image.Ready
                        && img.paintedWidth > 100
            }, 20000, "Image Ready from core QFile next to PdfPages, not XHR PUT")
            var item = ana.shelf.readerPanel.pdfEngine.item
            var dest = item.pathFor(String(ana.shelf.readingPdfUrl))
            verify(dest.indexOf("/src/qml/page-0-") >= 0)
            verify(dest.indexOf("file:") < 0)
            verify(String(ana.shelf.readingPdfUrl).indexOf("file") < 0)
            verify(String(ana.shelf.readingPdfUrl).indexOf("data") < 0)
        }
    }
}

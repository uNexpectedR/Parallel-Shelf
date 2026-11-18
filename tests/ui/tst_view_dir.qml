import QtQuick 2.15
import QtTest 1.2
import Qt.labs.settings 1.0
import "../../src/qml"
import "../../src/qml/catalog.js" as Catalog
import "bytes.js" as Bytes

// The view dir is the folder of PdfPages.qml — never a guessed host path.
// A missing view dir is not reported as missing pdftoppm.
Item {
    id: bench
    width: 960
    height: 680

    FileBytes { id: files }
    Component { id: pagesMaker; PdfPages {} }

    Component { id: networkMaker; FakeNetwork {} }
    Component { id: installMaker; Install {} }
    Component { id: memoryMaker; Settings { category: "parallel_shelf_v1" } }

    TestCase {
        name: "ViewDir"
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

        function test_view_dir_is_the_qml_dir_next_to_pdfpages() {
            var dir = files.viewDir()
            verify(dir.charAt(0) === "/", "view dir is an absolute folder")
            verify(dir.indexOf(".qml") < 0)
            verify(dir.indexOf("plugins/parallel_shelf/qml") < 0)
            verify(dir.indexOf("/src/qml") >= 0, "view dir is next to PdfPages.qml")
            files.hideViewDir = true
            compare(files.viewDir(), "")
        }

        function test_pdfpages_pathfor_is_this_document_dir() {
            var pages = createTemporaryObject(pagesMaker, bench)
            verify(typeof pages.pathFor === "function")
            verify(typeof pages.putPng !== "function")
            var dest = pages.pathFor("page-11-1.png")
            verify(dest.indexOf("/src/qml/page-11-1.png") >= 0)
            verify(dest.indexOf("file:") < 0)
            verify(dest.indexOf("data:") < 0)
        }

        function test_open_does_not_say_pdftoppm_missing_when_view_dir_is_gone() {
            var written = false
            var path = "/tmp/parallel-shelf-tests/tiny-view-dir.pdf"
            Bytes.writeFile(path, "%PDF-1.4 tiny", function () { written = true })
            tryVerify(function () { return written }, 5000)
            var ana = createTemporaryObject(installMaker, bench, { network: network })
            var library = ana.shelf.library
            tryVerify(function () {
                return library.storageState === "running" && library.deliveryState === "running"
            }, 5000, "Storage and Delivery start")
            library.share("Tiny PDF", "Test", path)
            tryVerify(function () { return !library.sharing && library.works.length === 1 }, 20000,
                      "tiny PDF is Shared")
            verify(library.files, "FileBytes is on the library")
            library.files.hideViewDir = true
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
                return ana.shelf.readingPages.length > 0 && pdf.indexOf("%PDF-") === 0
            }, 20000, "Open still loads bytes without a view dir")
            tryVerify(function () {
                var note = String(ana.shelf.readingNote)
                return note.indexOf("view qml dir") >= 0
                        && note.indexOf("pdftoppm is missing") < 0
            }, 8000, "view dir miss is not reported as missing pdftoppm")
            verify(String(ana.shelf.readingPdfUrl).indexOf("data:") < 0)
            verify(String(ana.shelf.readingPdfUrl).indexOf("file://") < 0)
        }
    }
}

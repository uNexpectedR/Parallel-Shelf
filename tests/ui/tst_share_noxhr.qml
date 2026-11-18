import QtQuick 2.15
import QtTest 1.2
import Qt.labs.settings 1.0
import "../../src/qml"
import "../../src/qml/catalog.js" as Catalog

// Basecamp never sets QML_XHR_ALLOW_FILE_READ, and storage_module cannot
// open ~/Downloads. Share copies the file through parallel_shelf_core
// (callModuleAsync stageShare) then storage_module.uploadUrl of that cache
// path. The view does not import tests/TestFileBytes.
Item {
    id: bench
    width: 960
    height: 680

    Component { id: networkMaker; FakeNetwork {} }
    Component { id: installMaker; Install {} }
    Component { id: memoryMaker; Settings { category: "parallel_shelf_v1" } }

    TestCase {
        name: "ShareNoXhr"
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
            memory.sync()
            network = createTemporaryObject(networkMaker, bench)
        }

        function test_share_of_the_pdf_finishes_without_file_xhr_of_downloads() {
            if (Catalog.fileXhrAllowed()) {
                console.log("NOXHR_SHARE skipped: QML_XHR_ALLOW_FILE_READ is set")
                verify(true)
                return
            }
            compare(Catalog.fileXhrAllowed(), false)
            var pdf = "/tmp/parallel-shelf-tests/Users/unexpectedr/Downloads/farewell-to-westphalia-foss-edition.pdf"
            var ana = createTemporaryObject(installMaker, bench, { network: network })
            var library = ana.shelf.library
            compare(library.files.nativeImpl, null)
            tryVerify(function () {
                return library.storageState === "running" && library.deliveryState === "running"
            }, 5000, "Storage and Delivery start")
            tryVerify(function () {
                return library.files && typeof library.files.fileSize === "function"
            }, 3000, "FileBytes loaded in the view")
            var t0 = Date.now()
            library.share("Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", pdf)
            tryVerify(function () { return !library.sharing && library.works.length === 1 }, 20000,
                      "Share finished without file:// XHR of Downloads")
            var ms = Date.now() - t0
            console.log("NOXHR_SHARE ms=" + ms + " title=" + library.works[0].title
                        + " size=" + library.works[0].size
                        + " head=" + ana.basecamp.firstFileChunk)
            compare(library.works[0].title, "Farewell to Westphalia")
            compare(library.works[0].author, "Jarrad Hope and Peter Ludlow")
            compare(library.works[0].size, 2276462)
            compare(network.files[library.works[0].cid].length, 2276462)
            compare(ana.basecamp.firstFileChunk, "%PDF-")
            var i
            var uploadUrl = 0
            var init = 0
            var chunk = 0
            var fin = 0
            var stage = 0
            for (i = 0; i < ana.basecamp.calls.length; i++) {
                if (ana.basecamp.calls[i].module === "parallel_shelf_core"
                        && ana.basecamp.calls[i].method === "stageShare")
                    stage++
                if (ana.basecamp.calls[i].module !== "storage_module") continue
                if (ana.basecamp.calls[i].method === "uploadUrl") {
                    uploadUrl++
                    verify(String(ana.basecamp.calls[i].args[0]).indexOf("/Downloads/") < 0,
                           "uploadUrl is the staged cache path, not Downloads")
                }
                if (ana.basecamp.calls[i].method === "uploadInit") init++
                if (ana.basecamp.calls[i].method === "uploadChunk") chunk++
                if (ana.basecamp.calls[i].method === "uploadFinalize") fin++
            }
            verify(uploadUrl >= 1, "Share uses uploadUrl of the staged cache path")
            verify(stage >= 1, "Share calls parallel_shelf_core.stageShare")
            verify(init >= 1, "catalog still uses uploadInit")
            verify(fin >= 1, "catalog still uses uploadFinalize")
            compare(network.mistakes, [])
        }
    }
}

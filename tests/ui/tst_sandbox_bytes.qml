import QtQuick 2.15
import QtTest 1.2
import Qt.labs.settings 1.0
import "../../src/qml"
import "../../src/qml/catalog.js" as Catalog

// Proof for 1.0.0: QML_XHR_ALLOW_FILE_READ unset, FileBytes.nativeImpl null
// (tests/TestFileBytes is not imported by the view). Share stages the Farewell
// PDF through logos.callModuleAsync("parallel_shelf_core", "stageShare") and
// storage_module.uploadUrl. First bytes start with %PDF-, full size 2276462.
Item {
    id: bench
    width: 960
    height: 680

    readonly property string pdf: "/cursor/stores/bc-a13b448c-7ad4-47f5-a01c-a53f4b3ed883/internal/farewell-to-westphalia-foss-edition.pdf"

    Component { id: networkMaker; FakeNetwork {} }
    Component { id: memoryMaker; Settings { category: "parallel_shelf_v1" } }
    Component { id: installMaker; Install {} }

    TestCase {
        name: "ShareCoreBytes"
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

        function prefixOf(text) {
            if (text === undefined || text === null) return "<null>"
            var s = String(text)
            if (!s.length) return "<empty>"
            var n = Math.min(5, s.length)
            var out = ""
            var i
            for (i = 0; i < n; i++) {
                var c = s.charCodeAt(i)
                out += (c >= 32 && c < 127) ? s.charAt(i) : ("\\x" + ("0" + c.toString(16)).slice(-2))
            }
            return out
        }

        function test_share_uploadUrl_pdf_body_via_core() {
            if (Catalog.fileXhrAllowed()) {
                console.log("CORE_SHARE skipped: QML_XHR_ALLOW_FILE_READ is set")
                verify(true)
                return
            }
            compare(Catalog.fileXhrAllowed(), false)
            var ana = createTemporaryObject(installMaker, bench, { network: network })
            var library = ana.shelf.library
            compare(library.files.nativeImpl, null)
            compare(String(ana.shelf.nativeFilesSource), "")
            tryVerify(function () {
                return library.storageState === "running" && library.deliveryState === "running"
            }, 5000, "Storage and Delivery start")

            library.share("Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", pdf)
            tryVerify(function () { return !library.sharing && library.works.length === 1 }, 20000,
                      "Share finished through parallel_shelf_core")

            console.log("CORE_SHARE head=" + ana.basecamp.firstFileChunk
                        + " size=" + library.works[0].size
                        + " stored=" + network.files[library.works[0].cid].length
                        + " nativeImpl=" + (library.files.nativeImpl ? "yes" : "no")
                        + " xhr=" + Catalog.fileXhrAllowed())

            compare(ana.basecamp.firstFileChunk, "%PDF-")
            compare(library.works[0].size, 2276462)
            compare(network.files[library.works[0].cid].length, 2276462)
            compare(network.files[library.works[0].cid].substring(0, 5), "%PDF-")

            var i
            var uploadUrl = 0
            var init = 0
            var chunk = 0
            var fin = 0
            var stage = 0
            var coreSize = 0
            for (i = 0; i < ana.basecamp.calls.length; i++) {
                if (ana.basecamp.calls[i].module === "parallel_shelf_core"
                        && ana.basecamp.calls[i].method === "stageShare")
                    stage++
                if (ana.basecamp.calls[i].module === "parallel_shelf_core"
                        && ana.basecamp.calls[i].method === "fileSize")
                    coreSize++
                if (ana.basecamp.calls[i].module !== "storage_module") continue
                if (ana.basecamp.calls[i].method === "uploadUrl") {
                    uploadUrl++
                    verify(String(ana.basecamp.calls[i].args[0]).indexOf("/Downloads/") < 0)
                    compare(ana.basecamp.calls[i].args[1], 65536)
                    compare(ana.basecamp.calls[i].args[2], true)
                }
                if (ana.basecamp.calls[i].method === "uploadInit") init++
                if (ana.basecamp.calls[i].method === "uploadChunk") chunk++
                if (ana.basecamp.calls[i].method === "uploadFinalize") fin++
            }
            console.log("CORE_SHARE_CALLS uploadUrl=" + uploadUrl
                        + " uploadInit=" + init
                        + " uploadChunk=" + chunk
                        + " uploadFinalize=" + fin
                        + " core.stageShare=" + stage
                        + " core.fileSize=" + coreSize)
            verify(uploadUrl >= 1, "Share uses uploadUrl of the staged cache path")
            verify(stage >= 1, "view calls parallel_shelf_core.stageShare")
            verify(init >= 1, "catalog still uses uploadInit")
            verify(fin >= 1, "catalog still uses uploadFinalize")
            compare(network.mistakes, [])
        }
    }
}

import QtQuick 2.15
import QtTest 1.2
import "../../src/qml/catalog.js" as Catalog

// Proves the 0.11.0 first-bar hang: without QML_XHR_ALLOW_FILE_READ, an async
// file:// GET never reaches readyState 4, so Catalog.loadFile never calls back.
// Run this file with that env unset. tests/run-ui.sh sets the env, so this
// case is skipped there.
TestCase {
    name: "XhrHang"
    when: windowShown

    readonly property string pdf: "/tmp/parallel-shelf-tests/farewell-to-westphalia-foss-edition.pdf"

    function test_loadFile_never_returns_when_file_xhr_is_blocked() {
        if (Catalog.fileXhrAllowed()) {
            console.log("XHR_HANG skipped: QML_XHR_ALLOW_FILE_READ is set (Basecamp does not set it)")
            verify(true)
            return
        }
        var got = "unset"
        Catalog.loadFile(pdf, function (view) { got = view })
        wait(3000)
        compare(got, "unset")
        console.log("HANG_PROVEN loadFile did not call back in 3s without QML_XHR_ALLOW_FILE_READ")
    }
}

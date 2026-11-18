import QtQuick 2.15
import QtTest 1.2
import "../../src/qml/catalog.js" as Catalog

// One-off: time loadFile + first chunk of the proof PDF. Not part of the
// shelf suite's required path — run-ui.sh still picks it up.
TestCase {
    name: "PdfLoad"
    when: windowShown

    readonly property string pdf: "/tmp/parallel-shelf-tests/farewell-to-westphalia-foss-edition.pdf"

    function test_loadFile_of_the_pdf() {
        if (!Catalog.fileXhrAllowed()) {
            console.log("LOADFILE skipped: file:// XHR is disabled (this is the Basecamp hang)")
            verify(true)
            return
        }
        var got = undefined
        var t0 = Date.now()
        Catalog.loadFile(pdf, function (view) { got = view })
        tryVerify(function () { return got !== undefined }, 20000, "loadFile returned")
        var ms = Date.now() - t0
        console.log("LOADFILE bytes=" + (got ? got.length : "null") + " ms=" + ms)
        verify(got && got.length > 2000000, "PDF bytes were read")
        var t1 = Date.now()
        var n = Catalog.blockSizeFor(got.length)
        var piece = Catalog.chunkOf(got, 0, n)
        console.log("FIRST_CHUNK len=" + piece.length + " blockSize=" + n + " ms=" + (Date.now() - t1))
        t1 = Date.now()
        var json = JSON.stringify(piece)
        console.log("JSON_CHUNK bytes=" + json.length + " ms=" + (Date.now() - t1) + " firstNul=" + piece.indexOf("\u0000"))
        // Mimic Basecamp IPC: JSON round-trip of the first uploadChunk.
        t1 = Date.now()
        var back = JSON.parse(json)
        console.log("ROUNDTRIP len=" + back.length + " ms=" + (Date.now() - t1) + " nulKept=" + (back.indexOf("\u0000") >= 0))
    }
}

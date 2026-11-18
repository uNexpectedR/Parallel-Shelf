import QtQuick 2.15
import QtTest 1.2
import "../../src/qml/catalog.js" as Catalog

// FileBytes is QFile in this process. qmltestrunner has no QmlSandbox, so
// tests/TestFileBytes loads. Basecamp 0.3.2 cannot dlopen that plugin.
Item {
    width: 100
    height: 100

    Loader {
        id: nativeFiles
        source: Qt.resolvedUrl("FileNative.qml")
    }

    TestCase {
        name: "FileBytesQFile"
        when: windowShown

        function test_qfile_reads_downloads_path_without_file_xhr() {
            if (Catalog.fileXhrAllowed()) {
                console.log("FILEBYTES skipped: QML_XHR_ALLOW_FILE_READ is set")
                verify(true)
                return
            }
            compare(Catalog.fileXhrAllowed(), false)
            tryVerify(function () { return nativeFiles.status === Loader.Ready }, 3000,
                      "FileNative loaded (status=" + nativeFiles.status + ")")
            var files = nativeFiles.item.impl
            verify(files, "FileBytes plugin loaded in the view")
            var pdf = "/tmp/parallel-shelf-tests/Users/unexpectedr/Downloads/farewell-to-westphalia-foss-edition.pdf"
            compare(files.fileSize(pdf), 2276462)
            compare(files.readPiece(pdf, 0, 5), "%PDF-")
            compare(files.readPiece(pdf, 819, 1).charCodeAt(0), 0)
            console.log("FILEBYTES_OK size=2276462 path=" + pdf)
        }

        function test_mkdir_never_returns_empty() {
            tryVerify(function () { return nativeFiles.status === Loader.Ready }, 3000,
                      "FileNative loaded (status=" + nativeFiles.status + ")")
            var files = nativeFiles.item.impl
            verify(files, "FileBytes plugin loaded in the view")
            var dir = files.mkdir("/tmp/parallel-shelf-tests/appdata/parallel-shelf/book.pdf")
            verify(dir.length > 0 && dir.charAt(0) === "/", "mkdir returns a path")
            verify(files.writePiece("/tmp/parallel-shelf-tests/appdata/parallel-shelf/book.pdf", 0, ""))
            console.log("MKDIR_QML dir=" + dir)
        }
    }
}

import QtQuick 2.15
import QtTest 1.2
import "../../src/qml"

// Packaged FileBytes.qml: FolderListModel fileSize, no qmldir plugin.
// This is the path Basecamp 0.3.2 can import after QmlSandbox blocked
// `plugin filebytesplugin` and type:ui QQuickWidget crashed on open.
Item {
    width: 120
    height: 120

    FileBytes { id: disk }

    TestCase {
        name: "FileBytesQmlFolderList"
        when: windowShown

        function test_folderlist_size_of_the_pdf() {
            var pdf = "/tmp/parallel-shelf-tests/Users/unexpectedr/Downloads/farewell-to-westphalia-foss-edition.pdf"
            var got = -2
            disk.stat(pdf, function (n) { got = n })
            tryVerify(function () { return got !== -2 }, 3000, "FolderListModel listed Downloads")
            compare(got, 2276462)
            compare(disk.fileSize(pdf), 2276462)
            console.log("QML_FILEBYTES_SIZE size=2276462 path=" + pdf)
        }
    }
}

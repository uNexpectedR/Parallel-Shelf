import QtQuick 2.15
import QtTest 1.2
import "../../src/qml"

// 0.15.0 type:ui IComponent crashed Basecamp when opening the shelf.
// 1.0.0 is still ui_qml Main.qml (empty main), the same kind of package 0.14.0 opened.
// Bytes live in parallel_shelf_core, not in this view.
Item {
    width: 960
    height: 680

    Main {
        id: shelf
        logosHost: null
    }

    TestCase {
        name: "OpenUiQml"
        when: windowShown

        function test_main_opens_without_a_host_plugin() {
            compare(shelf.visible, true)
            tryVerify(function () { return shelf.width > 0 && shelf.height > 0 }, 2000)
            var title = ""
            function walk(item) {
                if (!item) return
                if (item.text === "Parallel Shelf") title = item.text
                var i
                if (item.children) {
                    for (i = 0; i < item.children.length; i++) walk(item.children[i])
                }
            }
            walk(shelf)
            compare(title, "Parallel Shelf")
            verify(shelf.library.files)
            verify(typeof shelf.library.files.fileSize === "function")
            verify(typeof shelf.library.files.readPiece === "function")
            verify(typeof shelf.library.files.stat === "function")
            console.log("OPEN_UI_QML ok files=" + (shelf.library.files ? "FileBytes.qml" : "null"))
        }
    }
}

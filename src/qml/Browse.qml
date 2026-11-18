import QtQuick 2.15
import Qt.labs.folderlistmodel 2.15

// Lists files in this view, where the user's home folder is visible.
// The plugin process often cannot read ~/Downloads (Mac TCC). Native
// FileDialog sheets onto Basecamp's hidden Offscreen window.
Item {
    id: box

    property var pal
    property bool picking: false
    property bool saveFolder: false
    property string here: ""
    readonly property int fileCount: scan.item ? scan.item.count : 0

    signal picked(string path, var bytes)
    signal listed(string path)
    signal folderChosen(string path)

    function openAt(path) {
        go(path)
        picking = true
    }

    function close() {
        picking = false
    }

    function show(path, rows) {
        go(path)
        picking = true
    }

    function go(path) {
        var s = String(path || "").replace(/^\s+|\s+$/g, "")
        if (s.indexOf("file:") === 0) {
            s = s.replace(/^file:\/\//, "")
            if (s.charAt(0) !== "/") s = "/" + s
        }
        if (!s || s.charAt(0) !== "/") s = rootForThisOs()
        if (s.length > 1 && s.charAt(s.length - 1) === "/") s = s.substring(0, s.length - 1)
        here = s
        // Recreate the model with a real folder. An empty FolderListModel
        // sticks on the working directory and never picks up the new path.
        scan.active = false
        scan.sourceComponent = folderComp
        scan.active = true
    }

    function rootForThisOs() {
        var os = Qt.platform.os
        if (os === "osx" || os === "macos") return "/Users"
        if (os === "linux") return "/home"
        return "/"
    }

    function up() {
        if (!here || here === "/") return
        var slash = here.lastIndexOf("/")
        go(slash <= 0 ? "/" : here.substring(0, slash))
    }

    function pickNamed(name) {
        var listing = scan.item
        if (!listing) return ""
        var i
        for (i = 0; i < listing.count; i++) {
            if (listing.get(i, "fileName") !== name) continue
            var path = listing.get(i, "filePath")
            if (!path) {
                path = String(listing.get(i, "fileUrl")).replace(/^file:\/\//, "")
                if (path.charAt(0) !== "/") path = "/" + path
            }
            picking = false
            picked(path, listing.get(i, "fileSize"))
            return path
        }
        return ""
    }

    function looksLikeFile(path) {
        var slash = path.lastIndexOf("/")
        if (slash <= 0) return false
        var last = path.substring(slash + 1)
        if (last.indexOf(".") > 0) return true
        var parent = path.substring(0, slash)
        var pslash = parent.lastIndexOf("/")
        var folder = pslash >= 0 ? parent.substring(pslash + 1) : parent
        return ["Downloads", "Desktop", "Documents", "Movies", "Music", "Pictures"].indexOf(folder) >= 0
            && last.length > 0
    }

    visible: picking

    Component {
        id: folderComp
        FolderListModel {
            showDirs: true
            showFiles: true
            showDirsFirst: true
            showDotAndDotDot: false
            nameFilters: ["*.txt", "*.md", "*.pdf", "*.mp3", "*.m4a", "*.ogg"]
            folder: "file://" + box.here
            onStatusChanged: {
                if (status !== FolderListModel.Ready) return
                if (count > 0) return
                if (box.looksLikeFile(box.here)) box.up()
            }
        }
    }

    Loader { id: scan }

    Rectangle {
        anchors.fill: parent
        color: box.pal ? box.pal.white : "#fffcf7"
        radius: 10
        border.color: box.pal ? box.pal.line : "#d5cec0"
    }

    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        Row {
            width: parent.width
            spacing: 10

            ShelfButton {
                pal: box.pal
                text: "Up"
                enabled: box.here !== "/" && box.here !== ""
                onClicked: box.up()
            }

            ShelfButton {
                pal: box.pal
                text: "Close"
                onClicked: box.close()
            }

            ShelfButton {
                pal: box.pal
                primary: true
                visible: box.saveFolder
                text: "Save here"
                onClicked: {
                    box.picking = false
                    box.folderChosen(box.here)
                }
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.WrapAnywhere
            textFormat: Text.PlainText
            color: box.pal ? box.pal.mute : "#5c675f"
            font.pixelSize: 12
            text: box.here
        }

        ListView {
            id: list
            width: parent.width
            height: parent.height - 86
            clip: true
            model: scan.item
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                width: list.width
                height: 32
                color: tap.containsMouse ? (box.pal ? box.pal.paperDeep : "#e7dfd0") : "transparent"
                radius: 4

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                    textFormat: Text.PlainText
                    color: box.pal ? box.pal.ink : "#1c2321"
                    font.pixelSize: 13
                    text: fileIsDir ? fileName + "/" : fileName
                }

                MouseArea {
                    id: tap
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        var path = ""
                        try { path = filePath } catch (e) { path = "" }
                        if (!path) {
                            path = String(fileUrl).replace(/^file:\/\//, "")
                            if (path.charAt(0) !== "/") path = "/" + path
                        }
                        if (fileIsDir) box.go(path)
                        else if (box.saveFolder) {
                            return
                        } else {
                            var bytes = 0
                            try { bytes = fileSize } catch (e2) { bytes = 0 }
                            box.picking = false
                            box.picked(path, bytes)
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: !scan.item || scan.item.count === 0
                color: box.pal ? box.pal.mute : "#5c675f"
                font.pixelSize: 13
                text: "Nothing to choose here."
            }
        }
    }
}

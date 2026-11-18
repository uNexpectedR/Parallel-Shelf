import QtQuick 2.15
import "catalog.js" as Catalog

// The "Add to the shelf" form.
Rectangle {
    id: panel

    property var pal
    property var listFolder
    property var files: null
    property string homeDir: ""
    property bool busy: false
    property real progress: 0
    property string note: ""
    property string chosen: ""

    signal share(string title, string author, string source)
    signal cancel()
    signal pickRequested()

    // The picker is a list in this panel. Native FileDialog attaches to
    // Basecamp's hidden Offscreen window.
    readonly property bool hasDialog: dialog.status === Loader.Ready
    readonly property bool picking: dialog.item && dialog.item.picking
    readonly property bool listsInView: dialog.source.toString().indexOf("Browse.qml") >= 0
        && dialog.status === Loader.Ready

    property alias shareButton: shareBtn
    property alias chooseButton: choose
    property alias pathInput: pathField
    readonly property var picker: dialog.item
    readonly property string pickerHere: dialog.item ? dialog.item.here : ""

    function reset() {
        titleField.text = ""
        authorField.text = ""
        pathField.text = ""
        chosen = ""
        note = ""
    }

    function setSource(url) {
        chosen = url
        var path = Catalog.pathOf(url)
        if (path) pathField.text = path
        note = ""
    }

    function startDir() {
        var path = Catalog.folderOf(pathField.text ? pathField.text : panel.chosen)
        if (path) return path
        if (panel.homeDir) return panel.homeDir
        var os = Qt.platform.os
        if (os === "osx" || os === "macos") return "/Users"
        if (os === "linux") return "/home"
        return "/"
    }

    function fillList(path, rows) {
        if (dialog.item) dialog.item.show(path, rows)
    }

    function openPicker() {
        if (!dialog.item) return
        if (dialog.item.pal !== panel.pal) dialog.item.pal = panel.pal
        var start = panel.startDir()
        dialog.item.openAt(start)
        if (!panel.listsInView && panel.listFolder)
            panel.listFolder(start, panel.fillList)
    }

    function chooseFile() {
        if (panel.hasDialog) {
            panel.openPicker()
            return
        }
        panel.pickRequested()
    }

    width: Math.min(parent.width - 32, 460)
    height: picking ? Math.min(parent.height, 520) : form.height + 44
    radius: 10
    color: pal.white
    border.color: pal.line

    MouseArea {
        z: -1
        anchors.fill: parent
    }

    DropArea {
        z: -1
        anchors.fill: parent
        onDropped: function (drop) {
            if (drop.hasUrls && drop.urls.length) panel.setSource(String(drop.urls[0]))
        }
    }

    Loader {
        id: dialog
        z: 4
        anchors.fill: parent
        source: "Browse.qml"
        onLoaded: if (item) item.pal = panel.pal
        onStatusChanged: {
            if (status === Loader.Error && source.toString().indexOf("Browse.qml") >= 0)
                source = "Picker.qml"
        }
        Component.onCompleted: {
            if (status === Loader.Error && source.toString().indexOf("Browse.qml") >= 0)
                source = "Picker.qml"
        }
    }

    Connections {
        target: dialog.item
        function onPicked(url, bytes) {
            panel.setSource(url)
            if (panel.files && typeof panel.files.remember === "function")
                panel.files.remember(url, bytes)
        }
        function onListed(path) {
            if (!panel.listsInView && panel.listFolder)
                panel.listFolder(path, panel.fillList)
        }
    }

    Column {
        id: form
        z: 1
        x: 22
        y: 22
        width: parent.width - 44
        spacing: 10
        visible: !panel.picking

        Text {
            text: "Add to the shelf"
            color: panel.pal.ink
            font.pixelSize: 20
            font.family: "Georgia"
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: panel.pal.mute
            font.pixelSize: 12
            text: "Only add a work you have the right to share. Everyone with Parallel Shelf can open it, and it cannot be taken back."
        }

        ShelfField {
            id: titleField
            width: parent.width
            pal: panel.pal
            placeholder: "Title"
            maximumLength: Catalog.TITLE_MAX
        }

        ShelfField {
            id: authorField
            width: parent.width
            pal: panel.pal
            placeholder: "Author"
            maximumLength: Catalog.AUTHOR_MAX
        }

        Row {
            z: 2
            width: parent.width
            spacing: 10

            ShelfButton {
                id: choose
                pal: panel.pal
                text: "Choose file"
                enabled: !panel.busy
                onClicked: panel.chooseFile()
            }

            Text {
                width: parent.width - choose.width - 10
                anchors.verticalCenter: choose.verticalCenter
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
                color: panel.chosen ? panel.pal.ink : panel.pal.mute
                font.pixelSize: 13
                text: panel.chosen ? Catalog.fileNameOf(panel.chosen) : "or drop a file here"
            }
        }

        ShelfField {
            id: pathField
            width: parent.width
            pal: panel.pal
            wrap: true
            placeholder: "Full path to the file, or drop it here"
        }

        Text {
            color: panel.pal.mute
            font.pixelSize: 11
            text: "Books: txt, md, pdf. Audiobooks: mp3, m4a, ogg."
        }

        Rectangle {
            width: parent.width
            height: 4
            radius: 2
            color: panel.pal.paperDeep
            visible: panel.busy

            Rectangle {
                id: shareFill
                objectName: "shareFill"
                width: parent.width * Math.max(0.03, Math.min(1, panel.progress))
                height: parent.height
                radius: 2
                color: panel.pal.teal
                Behavior on width {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            color: panel.pal.tealDeep
            font.pixelSize: 12
            visible: text.length > 0
            text: panel.busy ? "Putting it on Logos Storage…" : panel.note
        }

        Item {
            width: parent.width
            height: 36

            ShelfButton {
                pal: panel.pal
                text: "Cancel"
                onClicked: panel.cancel()
            }

            ShelfButton {
                id: shareBtn
                anchors.right: parent.right
                pal: panel.pal
                primary: true
                enabled: !panel.busy
                text: "Share"
                onClicked: panel.share(titleField.text, authorField.text,
                                       pathField.text ? pathField.text : panel.chosen)
            }
        }
    }
}

import QtQuick 2.15

// A file list drawn in this view. Native FileDialog attaches a sheet to
// Basecamp's hidden Offscreen window, so it never appears. This list is
// ordinary QML in the panel.
Item {
    id: box

    property var pal
    property bool picking: false
    property string here: ""
    property var entries: []
    property bool waiting: false

    signal picked(string path, var bytes)
    signal listed(string path)

    function rootForThisOs() {
        var os = Qt.platform.os
        if (os === "osx" || os === "macos") return "/Users"
        if (os === "linux") return "/home"
        return "/"
    }

    function openAt(path) {
        here = path || rootForThisOs()
        waiting = true
        picking = true
        listed(here)
    }

    function close() {
        picking = false
    }

    function show(path, rows) {
        here = path || here
        entries = rows || []
        waiting = false
        picking = true
    }

    function up() {
        if (!here || here === "/") return
        var slash = here.lastIndexOf("/")
        listed(slash <= 0 ? "/" : here.substring(0, slash))
    }

    visible: picking

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
            model: box.entries
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
                    text: modelData.dir ? modelData.name + "/" : modelData.name
                }

                MouseArea {
                    id: tap
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (modelData.dir) box.listed(modelData.path)
                        else {
                            box.picking = false
                            box.picked(modelData.path, modelData.size || 0)
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                color: box.pal ? box.pal.mute : "#5c675f"
                font.pixelSize: 13
                text: box.waiting ? "Looking for files…" : "Nothing to choose here."
            }
        }
    }
}

import QtQuick 2.15
import "catalog.js" as Catalog

// The strip along the bottom while an audiobook is open.
Rectangle {
    id: bar

    property var pal
    property var work: null
    property var player: null     // the loaded Player.qml, or null if audio is unavailable
    property string note: ""      // shown in place of the scrubber while fetching or on failure
    property real fetching: 0

    signal closed()

    readonly property bool ready: player !== null && note === ""

    height: 72
    radius: 8
    color: pal.tealDeep

    ShelfButton {
        id: toggle
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        pal: bar.pal
        visible: bar.ready
        text: bar.player && bar.player.playing ? "Pause" : "Play"
        color: bar.pal.white
        onClicked: bar.player.toggle()
    }

    ShelfButton {
        id: close
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        pal: bar.pal
        text: "Close"
        color: bar.pal.white
        onClicked: bar.closed()
    }

    Column {
        anchors.left: toggle.visible ? toggle.right : parent.left
        anchors.right: close.left
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: bar.pal.white
            font.pixelSize: 14
            text: bar.work ? bar.work.title + " · " + bar.work.author : ""
        }

        Rectangle {
            id: track
            width: parent.width
            height: 6
            radius: 3
            color: "#55ffffff"

            readonly property real filled: bar.ready
                ? (bar.player.duration > 0 ? bar.player.position / bar.player.duration : 0)
                : bar.fetching

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, track.filled))
                height: parent.height
                radius: 3
                color: bar.pal.white
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                enabled: bar.ready && bar.player.duration > 0
                function seek(x) {
                    bar.player.seek(Math.round(Math.max(0, Math.min(1, x / track.width)) * bar.player.duration))
                }
                onPressed: function (mouse) { seek(mouse.x - 8) }
                onPositionChanged: function (mouse) { if (pressed) seek(mouse.x - 8) }
            }
        }

        Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: bar.pal.white
            opacity: 0.85
            font.pixelSize: 11
            text: bar.ready ? Catalog.clock(bar.player.position) + " / " + Catalog.clock(bar.player.duration)
                            : bar.note
        }
    }
}

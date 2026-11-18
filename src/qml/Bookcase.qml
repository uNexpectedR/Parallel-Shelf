import QtQuick 2.15
import "catalog.js" as Catalog

Item {
    id: bay
    property var pal
    property var app
    property var library
    property var works: []
    property string heading: ""
    property string emptyLine: ""
    property alias grid: grid
    property int post: 18
    property int rail: 16

    Image {
        anchors.fill: parent
        source: "wood-wall.png"
        fillMode: Image.Tile
        asynchronous: false
        cache: false
    }

    Rectangle {
        anchors.fill: parent
        color: "#22000000"
    }

    Image {
        id: crown
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: bay.rail
        source: "wood-plank.png"
        fillMode: Image.Tile
        asynchronous: false
        cache: false
        z: 5
    }

    Image {
        id: foot
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: bay.rail
        source: "wood-plank.png"
        fillMode: Image.Tile
        asynchronous: false
        cache: false
        z: 5
    }

    Image {
        id: leftPost
        anchors.left: parent.left
        anchors.top: crown.bottom
        anchors.bottom: foot.top
        width: bay.post
        source: "wood-wall.png"
        fillMode: Image.Tile
        asynchronous: false
        cache: false
        z: 5
    }

    Rectangle {
        anchors.top: leftPost.top
        anchors.bottom: leftPost.bottom
        anchors.right: leftPost.right
        width: 2
        color: "#2a160c"
        z: 6
    }

    Image {
        id: rightPost
        anchors.right: parent.right
        anchors.top: crown.bottom
        anchors.bottom: foot.top
        width: bay.post
        source: "wood-wall.png"
        fillMode: Image.Tile
        asynchronous: false
        cache: false
        z: 5
    }

    Rectangle {
        anchors.top: rightPost.top
        anchors.bottom: rightPost.bottom
        anchors.left: rightPost.left
        width: 2
        color: "#2a160c"
        z: 6
    }

    Rectangle {
        anchors.left: leftPost.right
        anchors.right: rightPost.left
        anchors.top: crown.bottom
        anchors.bottom: foot.top
        color: "#7a100806"
    }

    Text {
        id: cap
        anchors.top: crown.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 6
        color: "#f5fbff"
        font.pixelSize: 16
        font.family: "Avenir Next"
        font.letterSpacing: 1.4
        style: Text.Outline
        styleColor: "#071018"
        text: bay.heading
        z: 6
    }

    Item {
        id: bays
        anchors.top: cap.bottom
        anchors.topMargin: 4
        anchors.left: leftPost.right
        anchors.right: rightPost.left
        anchors.bottom: foot.top
        clip: true

        Repeater {
            model: Math.max(3, Math.ceil(bays.height / Math.max(1, grid.cellHeight)) + 1)
            Item {
                width: bays.width
                height: grid.cellHeight
                y: index * grid.cellHeight - (grid.cellHeight > 0 ? (grid.contentY % grid.cellHeight) : 0)

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 22
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#44000000" }
                        GradientStop { position: 1.0; color: "#00000000" }
                    }
                }

                Image {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 22
                    source: "wood-plank.png"
                    fillMode: Image.Tile
                    asynchronous: false
                    cache: false
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 4
                    color: "#140c08"
                    opacity: 0.65
                }
            }
        }

        GridView {
            id: grid
            objectName: "shelfGrid"
            anchors.fill: parent
            cellWidth: Math.max(168, Math.floor(width / Math.max(1, Math.floor(width / 188))))
            cellHeight: 268
            clip: false
            model: bay.works
            interactive: true
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            highlight: Item {}
            highlightFollowsCurrentItem: false

            delegate: Item {
                id: card
                width: grid.cellWidth
                height: grid.cellHeight

                required property var modelData
                required property int index

                Rectangle {
                    id: sitShadow
                    width: face.width + 8
                    height: 12
                    radius: 6
                    color: "#88000000"
                    anchors.horizontalCenter: face.horizontalCenter
                    anchors.top: face.bottom
                    anchors.topMargin: -4
                    transform: Scale {
                        origin.x: sitShadow.width / 2
                        origin.y: sitShadow.height / 2
                        xScale: hover.containsMouse ? 0.92 : 1
                        yScale: 0.5
                    }
                }

                Item {
                    id: face
                    objectName: "cardFace"
                    width: 164
                    height: 196
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: hover.containsMouse ? 38 : 32

                    Rectangle {
                        z: -1
                        anchors.right: parent.right
                        anchors.rightMargin: -6
                        width: 7
                        height: parent.height
                        color: "#120c08"
                    }

                    Rectangle {
                        id: spine
                        width: 14
                        height: parent.height
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.darker(spine.cloth, 1.7) }
                            GradientStop { position: 0.4; color: spine.cloth }
                            GradientStop { position: 0.85; color: Qt.lighter(spine.cloth, 1.08) }
                            GradientStop { position: 1.0; color: Qt.darker(spine.cloth, 1.35) }
                        }
                        property color cloth: {
                            var list = bay.pal.cloth
                            return list[card.index % list.length]
                        }

                        Rectangle {
                            y: 16
                            width: parent.width
                            height: 4
                            color: "#c9a227"
                            opacity: 0.9
                        }

                        Rectangle {
                            y: parent.height - 24
                            width: parent.width
                            height: 4
                            color: "#c9a227"
                            opacity: 0.75
                        }
                    }

                    Rectangle {
                        id: cover
                        objectName: "cardCover"
                        anchors.left: spine.right
                        width: 138
                        height: parent.height
                        color: Qt.darker(spine.cloth, 1.1)
                        clip: true

                        Image {
                            id: coverArt
                            objectName: "cardCoverImage"
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: false
                            cache: false
                            visible: status === Image.Ready
                            property string coverRel: {
                                var cid = card.modelData ? card.modelData.cid : ""
                                var key = Catalog.holdName(cid)
                                if (!key || (card.modelData && card.modelData.kind === "audiobook"))
                                    return ""
                                return "page-" + key + "-0.png"
                            }
                            property string coverSrc: ""
                            source: coverSrc
                            function armCover() {
                                var cid = card.modelData ? card.modelData.cid : ""
                                coverSrc = coverRel
                                if (cid && card.modelData && card.modelData.kind !== "audiobook" && bay.app)
                                    bay.app.paintCover(cid)
                                if (coverRel)
                                    coverRetry.restart()
                            }
                            Component.onCompleted: armCover()
                            onCoverRelChanged: armCover()
                            onStatusChanged: {
                                var name = String(coverSrc || coverRel || "")
                                console.log("parallel-shelf: Image.source=" + name
                                            + " status=" + status
                                            + " dest=" + (bay.app ? bay.app.pathFor(name) : ""))
                                if (status === Image.Ready) {
                                    coverRetry.stop()
                                    console.log("parallel-shelf: cover ready " + name)
                                    return
                                }
                                if (!name || name.indexOf("page-") !== 0) return
                                coverRetry.restart()
                            }
                        }

                        Timer {
                            id: coverRetry
                            interval: 120
                            repeat: true
                            running: false
                            onTriggered: {
                                if (coverArt.status === Image.Ready) {
                                    stop()
                                    return
                                }
                                var cid = card.modelData ? card.modelData.cid : ""
                                var name = coverArt.coverRel
                                if (!name || name.indexOf("page-") !== 0) {
                                    stop()
                                    return
                                }
                                if (cid && bay.app)
                                    bay.app.paintCover(cid)
                                console.log("parallel-shelf: dest skip core "
                                            + (bay.app ? bay.app.pathFor(name) : "") + " rel=" + name)
                                coverArt.coverSrc = ""
                                Qt.callLater(function () { coverArt.coverSrc = name })
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: cover
                        z: 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "#44000000" }
                            GradientStop { position: 0.18; color: "#00000000" }
                            GradientStop { position: 0.72; color: "#00000000" }
                            GradientStop { position: 1.0; color: "#33000000" }
                        }
                    }

                    Rectangle {
                        id: pages
                        anchors.left: cover.right
                        width: 10
                        height: parent.height
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "#e8dcc0" }
                            GradientStop { position: 0.35; color: "#f6eedc" }
                            GradientStop { position: 1.0; color: "#cbb992" }
                        }

                        Repeater {
                            model: 11
                            Rectangle {
                                x: 1
                                y: 4 + index * ((pages.height - 8) / 11)
                                width: pages.width - 2
                                height: 1
                                color: "#bba67a"
                                opacity: 0.7
                            }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: pages.right
                        anchors.bottom: parent.bottom
                        height: 5
                        color: "#1a1008"
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (bay.app)
                                bay.app.open(bay.library.filledWork(card.modelData) || card.modelData)
                        }
                    }

                    Rectangle {
                        id: cardSaveBar
                        objectName: "cardSaveBar"
                        z: 2
                        anchors.left: cover.left
                        anchors.right: cover.right
                        anchors.bottom: cover.bottom
                        anchors.bottomMargin: 8
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        height: 6
                        radius: 2
                        color: "#66ffffff"
                        visible: bay.library && bay.library.saveBusy && bay.app
                                 && bay.app.saving && card.modelData
                                 && bay.app.saving.id === card.modelData.id

                        Rectangle {
                            objectName: "cardSaveFill"
                            width: parent.width * Math.max(0.03, Math.min(1, bay.library.saveProgress))
                            height: parent.height
                            radius: 2
                            color: bay.pal.teal
                            Behavior on width {
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }

                Text {
                    objectName: "downloadButton"
                    z: 6
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    color: "#f5fbff"
                    font.pixelSize: 13
                    font.family: "Avenir Next"
                    font.bold: true
                    style: Text.Outline
                    styleColor: "#071018"
                    text: {
                        var mb = Catalog.sizeLabel(card.modelData.size)
                        return mb ? "Download(" + mb + ")" : "Download"
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (bay.app)
                                bay.app.download(bay.library.filledWork(card.modelData) || card.modelData)
                        }
                    }
                }

                Text {
                    objectName: "cardSize"
                    visible: false
                    text: Catalog.sizeLabel(card.modelData.size)
                }
            }
        }

        Text {
            anchors.centerIn: parent
            width: parent.width - 24
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: bay.works.length === 0 && bay.emptyLine.length > 0
            color: "#9a7a52"
            font.pixelSize: 13
            font.family: "Georgia"
            text: bay.emptyLine
            z: 2
        }
    }
}

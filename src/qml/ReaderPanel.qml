import QtQuick 2.15

// Shows a book one screen of text at a time.
Rectangle {
    id: panel

    property var pal
    property var work: null
    property var pages: []
    property int page: 0
    property string note: ""
    property string pdfBytes: ""
    property string pdfUrl: ""
    property real progress: 0
    readonly property bool showingPdf: String(pdfBytes).indexOf("%PDF-") === 0
    readonly property bool fetching: panel.pages.length === 0
            && (panel.note.indexOf("Opening") === 0 || panel.note.indexOf("Fetching") === 0)
    property var files: null
    property alias fetchBar: fetchTrack
    property alias pdfEngine: pdfEngine
    readonly property bool pdfReady: pdfEngine.status === Loader.Ready
            && pdfEngine.item
            && (pdfEngine.item.documentStatus === 1
                || pdfEngine.item.documentStatus === 2
                || pdfEngine.item.status === Image.Ready)
            && (!pdfEngine.item.pageCount || pdfEngine.item.pageCount > 0)

    signal closed()
    property bool fullScreen: false
    property real zoom: 1
    property bool zoomFit: true

    readonly property real zoomMin: 0.4
    readonly property real zoomMax: 4

    function setZoom(v) {
        var z = Math.max(panel.zoomMin, Math.min(panel.zoomMax, Number(v)))
        if (isNaN(z))
            z = 1
        panel.zoomFit = Math.abs(z - 1) < 0.03
        panel.zoom = panel.zoomFit ? 1 : z
        console.log("parallel-shelf: zoom " + panel.zoom)
    }
    function zoomIn() {
        panel.setZoom(Number(panel.zoom || 1) * 1.35)
    }
    function zoomOut() {
        panel.setZoom(Number(panel.zoom || 1) / 1.35)
    }
    function fitPage() {
        panel.setZoom(1)
        console.log("parallel-shelf: zoom fit")
    }
    function zoomFromMouse(mx, trackWidth) {
        var w = Number(trackWidth)
        if (!(w > 0))
            return
        var t = Math.max(0, Math.min(1, Number(mx) / w))
        panel.setZoom(panel.zoomMin + t * (panel.zoomMax - panel.zoomMin))
    }

    property alias pdfPan: paperPan

    function centerPan() {
        if (!paperPan.width)
            return
        paperPan.contentX = Math.max(0, (paperPan.contentWidth - paperPan.width) / 2)
        paperPan.contentY = Math.max(0, (paperPan.contentHeight - paperPan.height) / 2)
    }

    function panToCorner() {
        paperPan.contentX = Math.max(0, paperPan.contentWidth - paperPan.width)
        paperPan.contentY = Math.max(0, paperPan.contentHeight - paperPan.height)
        console.log("parallel-shelf: pan " + paperPan.contentX + ","
                    + paperPan.contentY + " zoom=" + panel.zoom)
    }

    onZoomChanged: Qt.callLater(panel.centerPan)

    function skipToPage(raw) {
        var n = parseInt(String(raw !== undefined ? raw : jump.text), 10)
        if (isNaN(n))
            return
        var last = panel.pages.length
        if (last < 1)
            return
        if (n < 1)
            n = 1
        if (n > last)
            n = last
        jump.text = String(n)
        panel.page = n - 1
        console.log("parallel-shelf: skip to " + n + " of " + last)
    }



    onPagesChanged: {
        page = 0
        jump.text = panel.pages.length ? "1" : ""
        if (pdfEngine.item)
            pdfEngine.sizeItem()
    }
    onPageChanged: {
        scroll.contentY = 0
        jump.text = panel.pages.length ? String(panel.page + 1) : ""
        Qt.callLater(panel.centerPan)
    }

    width: panel.fullScreen && parent ? parent.width : Math.min(parent ? parent.width - 32 : 720, 720)
    height: panel.fullScreen && parent ? parent.height : Math.min(parent ? parent.height - 32 : 620, 620)
    radius: panel.fullScreen ? 0 : 10
    color: pal.white
    border.color: pal.line

    MouseArea { anchors.fill: parent }

    Row {
        id: tools
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 18
        spacing: 8

        ShelfButton {
            pal: panel.pal
            text: "−"
            onClicked: panel.zoomOut()
        }
        ShelfButton {
            pal: panel.pal
            text: "Fit"
            onClicked: panel.fitPage()
        }
        ShelfButton {
            pal: panel.pal
            text: "+"
            onClicked: panel.zoomIn()
        }
        ShelfButton {
            pal: panel.pal
            text: panel.fullScreen ? "Exit full screen" : "Full screen"
            onClicked: {
                panel.fullScreen = !panel.fullScreen
                console.log("parallel-shelf: fullscreen " + panel.fullScreen)
            }
        }
        ShelfButton {
            id: close
            pal: panel.pal
            text: "Close"
            onClicked: panel.closed()
        }
    }

    Column {
        id: heading
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: tools.left
        anchors.margins: 22
        spacing: 2

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: panel.pal.ink
            font.pixelSize: 22
            font.family: "Georgia"
            text: panel.work ? panel.work.title : ""
        }

        Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: panel.pal.mute
            font.pixelSize: 13
            text: panel.work ? panel.work.author : ""
        }
    }

    Rectangle {
        id: rule
        anchors.top: heading.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        height: 1
        color: panel.pal.line
    }

    Item {
        id: zoomBar
        objectName: "zoomBar"
        anchors.top: rule.bottom
        anchors.left: rule.left
        anchors.right: rule.right
        anchors.topMargin: panel.showingPdf ? 10 : 0
        height: panel.showingPdf ? 28 : 0
        visible: panel.showingPdf

        Text {
            id: zoomLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Zoom"
            color: panel.pal.ink
            font.pixelSize: 13
        }

        Rectangle {
            id: zoomTrack
            objectName: "zoomSlider"
            anchors.left: zoomLabel.right
            anchors.right: zoomPct.left
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 8
            radius: 4
            color: panel.pal.line

            Rectangle {
                height: parent.height
                width: zoomThumb.x + zoomThumb.width / 2
                radius: 4
                color: panel.pal.teal
            }

            Rectangle {
                id: zoomThumb
                objectName: "zoomThumb"
                width: 18
                height: 18
                radius: 9
                color: panel.pal.white
                border.color: panel.pal.ink
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(zoomTrack.width - width,
                    (zoomTrack.width - width)
                    * ((panel.zoom - panel.zoomMin) / (panel.zoomMax - panel.zoomMin))))
            }

            MouseArea {
                anchors.fill: parent
                anchors.topMargin: -12
                anchors.bottomMargin: -12
                cursorShape: Qt.PointingHandCursor
                onPressed: panel.zoomFromMouse(mouse.x, zoomTrack.width)
                onPositionChanged: {
                    if (pressed)
                        panel.zoomFromMouse(mouse.x, zoomTrack.width)
                }
            }
        }

        Text {
            id: zoomPct
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 48
            horizontalAlignment: Text.AlignRight
            text: Math.round(panel.zoom * 100) + "%"
            color: panel.pal.mute
            font.pixelSize: 12
        }
    }

    Rectangle {
        id: fetchTrack
        objectName: "fetchBar"
        anchors.top: rule.bottom
        anchors.left: rule.left
        anchors.right: rule.right
        anchors.topMargin: 14
        height: 6
        radius: 3
        color: panel.pal.line
        visible: panel.fetching

        Rectangle {
            id: fetchFill
            objectName: "fetchFill"
            width: parent.width * Math.max(0.03, Math.min(1, panel.progress))
            height: parent.height
            radius: 3
            color: panel.pal.teal
            Behavior on width {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
        }
    }

    Flickable {
        id: scroll
        anchors.top: rule.bottom
        anchors.bottom: turner.top
        anchors.left: rule.left
        anchors.right: rule.right
        anchors.topMargin: 14
        anchors.bottomMargin: 14
        contentHeight: body.height
        clip: true
        visible: panel.pages.length > 0 && !panel.showingPdf

        // Plain text on purpose. The book comes from a stranger, so it is
        // never treated as markup.
        Text {
            id: body
            width: scroll.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            color: panel.pal.ink
            font.pixelSize: 15
            font.family: "Georgia"
            lineHeight: 1.35
            text: panel.pages.length ? panel.pages[panel.page] : ""
        }
    }

    Item {
        id: pdfPane
        objectName: "pdfPane"
        z: 2
        anchors.top: zoomBar.bottom
        anchors.bottom: turner.top
        anchors.left: rule.left
        anchors.right: rule.right
        anchors.topMargin: 10
        anchors.bottomMargin: 14
        clip: true

        Flickable {
            id: paperPan
            objectName: "pdfPan"
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: panel.zoom > 1.02
            contentWidth: width * Math.max(1, panel.zoom)
            contentHeight: height * Math.max(1, panel.zoom)

            Loader {
                id: pdfEngine
                objectName: "pdfEngine"
                width: paperPan.contentWidth
                height: paperPan.contentHeight
                active: panel.showingPdf
                source: Qt.resolvedUrl("PdfPages.qml")
                visible: status === Loader.Ready
                onLoaded: sizeItem()
                onWidthChanged: sizeItem()
                onHeightChanged: sizeItem()
                onStatusChanged: {
                    if (status === Loader.Error)
                        console.log("parallel-shelf: PdfPages failed to load")
                }

                function sizeItem() {
                    if (!item) return
                    item.anchors.fill = pdfEngine
                    if (pdfEngine.width > 0) item.width = pdfEngine.width
                    if (pdfEngine.height > 0) item.height = pdfEngine.height
                    item.pageCount = panel.pages.length
                    item.page = panel.page
                    item.failText = panel.note
                    if (String(item.source) !== String(panel.pdfUrl))
                        item.source = panel.pdfUrl
                }
            }
        }
    }

    Connections {
        target: panel
        function onPageChanged() {
            if (pdfEngine.item)
                pdfEngine.item.page = panel.page
        }
        function onPdfUrlChanged() {
            if (pdfEngine.item && String(pdfEngine.item.source) !== String(panel.pdfUrl))
                pdfEngine.item.source = panel.pdfUrl
            }
        function onPagesChanged() {
            if (pdfEngine.item)
                pdfEngine.item.pageCount = panel.pages.length
        }
        function onNoteChanged() {
            if (pdfEngine.item)
                pdfEngine.item.failText = panel.note
        }
    }

    // Never the "PDF" / title card. Mac 0.36.0 showed that cover when
    // the page Image was not Ready even though pageCount was 381.
    Rectangle {
        id: paper
        objectName: "pdfCover"
        z: 1
        anchors.top: rule.bottom
        anchors.bottom: turner.top
        anchors.left: rule.left
        anchors.right: rule.right
        anchors.topMargin: 14
        anchors.bottomMargin: 14
        color: "#f4f1ea"
        border.color: panel.pal.line
        visible: panel.showingPdf && panel.pages.length === 0
                && pdfEngine.status !== Loader.Ready
    }

    Text {
        anchors.centerIn: parent
        width: parent.width - 80
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        color: panel.pal.mute
        font.pixelSize: 14
        visible: panel.pages.length === 0
        text: panel.note
    }

    Item {
        id: turner
        anchors.bottom: parent.bottom
        anchors.left: rule.left
        anchors.right: rule.right
        anchors.bottomMargin: 18
        height: 38
        visible: panel.pages.length > 0

        ShelfButton {
            id: prevBtn
            pal: panel.pal
            text: "Previous"
            enabled: panel.page > 0
            onClicked: panel.page--
        }

        Row {
            id: skipRow
            anchors.centerIn: parent
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: panel.pal.mute
                font.pixelSize: 12
                text: "Go to"
            }

            ShelfField {
                id: jump
                width: 56
                height: 36
                pal: panel.pal
                placeholder: "Page"
                maximumLength: 5
                Component.onCompleted: text = panel.pages.length ? String(panel.page + 1) : ""
                onAccepted: panel.skipToPage()
            }

            ShelfButton {
                pal: panel.pal
                text: "Go"
                onClicked: panel.skipToPage()
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: panel.pal.mute
                font.pixelSize: 12
                text: "Page " + (panel.page + 1) + " of " + panel.pages.length
            }
        }

        ShelfButton {
            anchors.right: parent.right
            pal: panel.pal
            text: "Next"
            enabled: panel.page < panel.pages.length - 1
            onClicked: panel.page++
        }
    }
}

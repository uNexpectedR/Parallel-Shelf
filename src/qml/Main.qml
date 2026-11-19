import QtQuick 2.15
import "palette.js" as Palette
import "catalog.js" as Catalog

// The shelf screen. Everything that touches Logos is in Library.qml.
Item {
    id: root
    anchors.fill: parent
    implicitWidth: 960
    implicitHeight: 680
    clip: true
    focus: true

    property var pal: Palette.tokens()
    readonly property var roomPal: ({
        paper: "#2a1c14",
        paperDeep: "#1c120c",
        ink: "#f5fbff",
        mute: "#c5d0d8",
        teal: "#f5fbff",
        tealDeep: "#d0e4f0",
        line: "#8a9aa4",
        white: "#1c120c",
        wood: "#1c100a",
        woodLip: "#f5fbff",
        cloth: pal.cloth
    })
    property string query: ""
    property var shown: []
    property var shownMine: []
    property var shownOthers: []
    property string notice: ""

    property bool adding: false
    property var saving: null
    property var reading: null
    property var readingPages: []
    property string readingNote: ""
    property string readingPdf: ""
    property string readingPdfUrl: ""
    property string readingPath: ""
    property var listening: null
    property string listeningNote: ""
    property string listeningPath: ""

    readonly property var player: audio.status === Loader.Ready ? audio.item : null
    property alias library: library
    property alias addButton: add
    property alias uploadPanel: upload
    property alias savePicker: saveBrowse
    property alias readerPanel: reader
    property alias fetchBar: reader.fetchBar

    function findNamed(node, name) {
        if (!node)
            return null
        if (node.objectName === name)
            return node
        var kids = node.children || []
        var i
        for (i = 0; i < kids.length; i++) {
            var hit = findNamed(kids[i], name)
            if (hit)
                return hit
        }
        return null
    }

    function cardBar() {
        return findNamed(room, "cardSaveBar")
    }

    function downloadButton() {
        return findNamed(room, "downloadButton")
    }

    // Basecamp 0.3.2 injects `logos`. Tests pass logosHost. File bytes come
    // from parallel_shelf_core via logos.callModuleAsync. nativeFilesSource is
    // tests-only and must stay empty in the Share proof.
    property var logosHost: null
    property url nativeFilesSource: ""

    Component.onCompleted: {
        if (!root.logosHost) {
            try { root.logosHost = logos } catch (e) {}
        }
    }

    Keys.onEscapePressed: {
        if (reading) closeReader()
        else if (saveBrowse.picking) {
            saveBrowse.close()
            saving = null
        } else if (adding && !library.sharing) adding = false
    }

    // Basecamp PluginLoader used to call this. ui_qml Mac 0.3.2 delivers
    // Storage events on logos.moduleEventReceived instead. Share does not
    // need them (callVia answers). Open does.
    function onModuleEvent(moduleName, eventName, data) {
        library.handleEvent(moduleName, eventName, data)
    }

    Connections {
        target: root.logosHost
        ignoreUnknownSignals: true
        function onModuleEventReceived(moduleName, eventName, data) {
            library.handleEvent(moduleName, eventName, data)
        }
    }

    function pathFor(name) {
        name = String(name || "")
        if (!name || name.indexOf("/") >= 0 || name.indexOf(":") >= 0
                || name.indexOf("..") >= 0 || name.indexOf("file") === 0
                || name.indexOf("data") === 0)
            return ""
        var u = String(Qt.resolvedUrl(name) || "")
        if (u.indexOf("file:") === 0) {
            u = u.replace(/^file:\/\//i, "")
            if (u.indexOf("localhost/") === 0)
                u = u.substring("localhost".length)
            try { u = decodeURIComponent(u) } catch (e) {}
        }
        if (u.charAt(0) === "/" && u.indexOf(".png") > 0 && u.indexOf(":") < 0)
            return u
        return ""
    }

    function paintCover(cid) {
        cid = Catalog.cleanText(cid, 200)
        if (!cid || !disk || typeof disk.renderPage !== "function")
            return
        var key = Catalog.holdName(cid)
        if (key)
            console.log("parallel-shelf: cover wanted " + key)
        disk.renderPage(cid, 0, 640, function () {}, { pathFor: root.pathFor })
    }

    function paintAllCovers() {
        var i
        for (i = 0; i < library.works.length; i++) {
            var w = library.works[i]
            if (w && w.cid && w.kind !== "audiobook")
                root.paintCover(w.cid)
        }
    }

    function isOwn(work) {
        return !!(library && library.isMine(work))
    }

    function refresh() {
        var mine = []
        var others = []
        var i
        for (i = 0; i < library.works.length; i++) {
            var w = library.works[i]
            if (!Catalog.matches(w, query))
                continue
            if (root.isOwn(w))
                mine.push(w)
            else
                others.push(w)
        }
        shownMine = Catalog.byAddTime(Catalog.uniqueCid(mine))
        shownOthers = Catalog.byAddTime(Catalog.uniqueCid(others))
        shown = mine.concat(others)
        root.paintAllCovers()
    }

    function networkLine() {
        var words = { starting: "starting", running: "running", down: "not running" }
        return "Logos Storage: " + words[library.storageState] + " · Logos Delivery: " + words[library.deliveryState]
    }

    function bookCountLine() {
        var count = library.works.length
        return count + (count === 1 ? " book" : " books")
    }

    function emptyTitle() {
        if (library.works.length) return "Nothing matches that search"
        if (library.storageState === "starting" || library.deliveryState === "starting") return "Looking for the shelf…"
        if (library.storageState === "down" && library.deliveryState === "down") return "The shelf cannot be reached"
        return "Nothing on the shelf yet"
    }

    function emptyBody() {
        if (library.works.length) return "Try another title or author."
        if (library.storageState === "starting" || library.deliveryState === "starting")
            return "Starting Logos Storage and Logos Delivery."
        if (library.storageState === "down" && library.deliveryState === "down")
            return "Logos Storage and Logos Delivery are not running. Parallel Shelf needs both, and it will not show made-up titles in their place."
        if (library.deliveryState === "down")
            return "Logos Delivery is not running."
        if (library.storageState === "down")
            return "Logos Storage is not running, so a file cannot be Shared."
        return "Choose a file to add a book. Books you Share stand on Your Shelf. Books other people Share stand on Parallel Shelf."
    }

    property int paintGen: 0
    property int paintTimeoutMs: 12000

    Timer {
        id: paintWatch
        interval: 12000
        repeat: false
        property int gen: 0
        onTriggered: {
            if (paintWatch.gen !== root.paintGen) return
            var url = String(root.readingPdfUrl)
            var item = root.readerPanel && root.readerPanel.pdfEngine
                       && root.readerPanel.pdfEngine.item
            var ready = url.indexOf("page-") === 0
                    && url.indexOf(".png") > 0
                    && url.indexOf(":") < 0
                    && url.indexOf("/") < 0
                    && item
                    && item.status === Image.Ready
            if (ready)
                return
            root.readingNote = "Could not draw this page."
        }
    }

    Timer {
        id: paintWait
        interval: 50
        repeat: true
        property int gen: 0
        property var work: null
        property int page: 0
        property int tries: 0
        onTriggered: {
            if (paintWait.gen !== root.paintGen) {
                stop()
                return
            }
            var engine = root.readerPanel ? root.readerPanel.pdfEngine : null
            var item = engine && engine.status === Loader.Ready ? engine.item : null
            paintWait.tries++
            if (item || paintWait.tries > 20) {
                stop()
                root.startCorePaint(paintWait.work, paintWait.page, paintWait.gen, item)
            }
        }
    }

    function startCorePaint(work, page, gen, item) {
        if (gen !== root.paintGen) return
        if (!work || !root.isOpen(root.reading, work)) return
        disk.paintPdfPath = ""
        if (library && typeof library.destPath === "function")
            disk.paintPdfPath = library.destPath(work) || ""
        disk.renderPage(work.cid, page, 640, function (url, err) {
            if (gen !== root.paintGen) return
            if (!root || !root.isOpen(root.reading, work)) return
            var v = url
            if (typeof v === "string" && v.charAt(0) === "{") {
                try { var p = JSON.parse(v); v = (p && p.value) ? p.value : "" } catch (e) {}
            }
            if (v && v.indexOf("page-") === 0 && v.indexOf(".png") > 0
                    && v.indexOf(":") < 0 && v.indexOf("/") < 0
                    && v.indexOf("file") !== 0 && v.indexOf("data") !== 0) {
                root.readingNote = ""
                // Interceptor canonicalizes only an existing PNG. Clear first
                // so Image retries the relative name after core QFile-wrote it.
                root.readingPdfUrl = ""
                Qt.callLater(function () {
                    if (gen !== root.paintGen) return
                    root.readingPdfUrl = v
                })
                return
            }
            paintWatch.stop()
            var msg = String(err || "")
            if (msg.indexOf("Could not draw") === 0)
                root.readingNote = msg
            else if (msg)
                root.readingNote = "Could not draw this page. " + msg
            else
                root.readingNote = "Could not draw this page."
        }, item)
    }

    function paintCorePage(work, page) {
        if (!work || !Catalog.isPdf(root.readingPdf)) return
        var gen = ++root.paintGen
        paintWatch.gen = gen
        paintWatch.interval = Math.max(400, root.paintTimeoutMs)
        paintWatch.restart()
        paintWait.stop()
        paintWait.gen = gen
        paintWait.work = work
        paintWait.page = page
        paintWait.tries = 0
        var engine = root.readerPanel ? root.readerPanel.pdfEngine : null
        var item = engine && engine.status === Loader.Ready ? engine.item : null
        if (item) {
            root.startCorePaint(work, page, gen, item)
            return
        }
        paintWait.start()
    }

    function open(work) {
        root.notice = ""
        if (library && typeof library.filledWork === "function")
            work = library.filledWork(work) || work
        if (work.kind === "audiobook") {
            if (player) player.stop()
            listening = work
            listeningPath = ""
            listeningNote = "Fetching from Logos Storage…"
            audio.active = true
        } else {
            reading = work
            readingPages = []
            readingNote = "Opening…"
            readingPdf = ""
            readingPdfUrl = ""
            readingPath = ""
        }
        library.fetch(work)
    }

    function download(work) {
        saving = work
        var start = library.downloadsDir()
        if (!start) start = library.homeDir
        if (saveBrowse.pal !== root.pal) saveBrowse.pal = root.pal
        saveBrowse.saveFolder = true
        saveBrowse.openAt(start)
    }

    function closeReader() {
        reading = null
        readingPages = []
        readingPdf = ""
        readingPdfUrl = ""
        readingPath = ""
        readingNote = ""
    }

    function closePlayer() {
        if (player) player.stop()
        listening = null
    }

    function isOpen(current, work) {
        return current !== null && current.id === work.id
    }

    FileBytes {
        id: disk
        caller: function (module, method, args, done, timeoutMs) {
            library.call(module, method, args, done, timeoutMs)
        }
    }

    Loader {
        id: nativeFiles
        active: String(root.nativeFilesSource).length > 0
        source: root.nativeFilesSource
        onStatusChanged: if (status === Loader.Error)
            console.log("parallel-shelf: test FileBytes plugin not loaded from " + source)
    }

    Library {
        id: library
        host: root.logosHost
        files: disk

        onWorksChanged: root.refresh()

        onShared: function (title, announced) {
            root.adding = false
            upload.reset()
            root.notice = announced
                ? "“" + title + "” is on the shelf."
                : "“" + title + "” is on Logos Storage. Other people will see it once Logos Delivery is running and the list has been sent."
        }

        onShareFailed: function (why) {
            upload.note = why
        }

        onTextReady: function (work, text) {
            if (!root.isOpen(root.reading, work)) return
            root.readingPages = Catalog.paginate(text, Catalog.PAGE_CHARS)
            root.readingNote = root.readingPages.length ? "" : "This file is empty."
        }

        onBytesReady: function (work, bytes) {
            if (!root.isOpen(root.reading, work)) return
            var pdf = String(bytes || "")
            if (!pdf.length) {
                root.readingNote = "Could not fetch this book. Logos Storage returned an empty file."
                return
            }
            root.readingPdf = pdf
            root.readingPages = Catalog.isPdf(pdf) ? Catalog.pdfPages(pdf) : Catalog.paginate(pdf, Catalog.PAGE_CHARS)
            if (!root.readingPages.length) {
                root.readingNote = "Could not fetch this book. Logos Storage returned an empty file."
                return
            }
            root.readingNote = ""
            if (!Catalog.isPdf(pdf)) return
            // Core copyFile of the Choose/stage PDF into the hold, then
            // QFile-writes page-<cid>-N.png to PdfPages.pathFor (this Loader
            // document). Image.source is that relative name. Never file://,
            // never data:, never a QML XHR PUT. Never a guessed qml dir.
            if (library.isMine(work)) {
                var staged = library && library.lastShareFile
                             ? library.lastShareFile[work.cid] : ""
                disk.persistHold(work.cid, pdf, function () {}, staged)
            }
            root.paintCorePage(work, root.readerPanel ? root.readerPanel.page : 0)
        }

        onFileReady: function (work, path) {
            if (root.isOpen(root.listening, work)) {
                root.listeningPath = path
                if (root.player) {
                    root.listeningNote = ""
                    root.player.load("file://" + path)
                } else {
                    root.listeningNote = "Saved to " + path + ". This Basecamp cannot play audio inside the app."
                }
            } else if (root.isOpen(root.reading, work)) {
                root.readingPath = path
                if (root.readingPages.length) return
                if (String(root.readingPdf).indexOf("%PDF-") === 0) {
                    root.readingPages = Catalog.pdfPages(root.readingPdf)
                    root.readingNote = root.readingPages.length ? ""
                        : "Could not fetch this book. Logos Storage returned an empty file."
                    return
                }
                root.readingNote = "Could not fetch this book. Logos Storage returned an empty file."
            }
        }

        onFetchFailed: function (work, why) {
            var note = String(why || "")
            if (library.isMine(work) && note.indexOf("Choose file") >= 0) {
                if (root.isOpen(root.listening, work)) root.listeningNote = Catalog.CHOOSE_AGAIN
                else if (root.isOpen(root.reading, work)) root.readingNote = Catalog.CHOOSE_AGAIN
                return
            }
            if (root.isOpen(root.listening, work)) root.listeningNote = "Could not fetch this audiobook. " + why
            else if (root.isOpen(root.reading, work)) root.readingNote = "Could not fetch this book. " + why
        }

        onFileChosen: function (path) {
            if (path) upload.setSource(path)
        }

        onSaveReady: function (work, path) {
            root.saving = null
            root.notice = "Saved “" + work.title + "” to " + path
        }

        onSaveFailed: function (work, why) {
            root.saving = null
            root.notice = why
        }
    }

    // Audio is loaded the first time an audiobook is opened. If this Basecamp
    // has no audio playback the shelf still works; the file is saved instead.
    Loader {
        id: audio
        active: false
        source: "Player.qml"
    }

    Connections {
        target: root.player
        function onFailed(why) {
            root.listeningNote = "Saved to " + root.listeningPath + ", but it could not be played here. " + why
        }
    }

    Item {
        id: room
        objectName: "readingRoom"
        anchors.fill: parent
        clip: true

        Image {
            anchors.fill: parent
            source: "wood-wall.png"
            fillMode: Image.Tile
            asynchronous: false
            cache: false
        }

        Rectangle {
            anchors.fill: parent
            color: "#3a080604"
        }

        Image {
            id: floor
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 56
            source: "wood-floor.png"
            fillMode: Image.Tile
            asynchronous: false
            cache: false
            z: 1
        }

        Text {
            z: 8
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            color: "#f5fbff"
            font.pixelSize: 12
            font.family: "Avenir Next"
            style: Text.Outline
            styleColor: "#071018"
            text: root.networkLine()
        }

        Text {
            z: 8
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            color: "#f5fbff"
            font.pixelSize: 12
            font.family: "Avenir Next"
            style: Text.Outline
            styleColor: "#071018"
            text: root.bookCountLine()
        }

        Bookcase {
            id: leftCase
            objectName: "leftCase"
            pal: root.pal
            app: root
            library: root.library
            works: root.shownMine
            heading: "Your Shelf"
            emptyLine: ""
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.top: parent.top
            anchors.topMargin: 148
            anchors.bottom: floor.top
            width: (parent.width - 168) / 2
            z: 2
        }

        Bookcase {
            id: rightCase
            objectName: "rightCase"
            pal: root.pal
            app: root
            library: root.library
            works: root.shownOthers
            heading: "Parallel Shelf"
            emptyLine: ""
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.top: parent.top
            anchors.topMargin: 148
            anchors.bottom: floor.top
            width: (parent.width - 168) / 2
            z: 2
        }

        Item {
            id: neon
            objectName: "neonLight"
            property bool lit: false
            width: 92
            height: 14
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: leftCase.top
            anchors.topMargin: 12
            z: 4

            Rectangle {
                visible: neon.lit
                anchors.centerIn: tube
                width: tube.width + 6
                height: 7
                radius: 3
                color: "#8830a0ff"
            }

            Canvas {
                id: cone
                visible: neon.lit
                z: -1
                width: Math.max(320, height * 0.95)
                height: Math.max(120, floor.y - neon.y)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: tube.top
                onVisibleChanged: if (visible) requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    if (!ctx || width < 4 || height < 4)
                        return
                    ctx.clearRect(0, 0, width, height)
                    var cx = width / 2
                    var halfPipe = tube.width / 2
                    var topY = tube.height / 2
                    var spread = (height - topY) * 0.325
                    ctx.beginPath()
                    ctx.moveTo(cx - halfPipe, topY)
                    ctx.lineTo(cx + halfPipe, topY)
                    ctx.lineTo(cx + halfPipe + spread, height)
                    ctx.lineTo(cx - halfPipe - spread, height)
                    ctx.closePath()
                    var g = ctx.createLinearGradient(cx, topY, cx, height)
                    g.addColorStop(0.0, "rgba(48, 150, 255, 0.62)")
                    g.addColorStop(0.22, "rgba(32, 120, 255, 0.38)")
                    g.addColorStop(0.62, "rgba(20, 100, 255, 0.18)")
                    g.addColorStop(1.0, "rgba(16, 80, 255, 0.0)")
                    ctx.fillStyle = g
                    ctx.fill()
                }
            }

            Rectangle {
                id: tube
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 20
                height: 3
                radius: 1
                color: neon.lit ? "#f2f8ff" : "#8a9298"
                border.width: 1
                border.color: neon.lit ? "#c8dcff" : "#6a7278"
            }

            Rectangle {
                width: 6
                height: 8
                radius: 1
                color: "#b8c0c4"
                border.color: "#6a7278"
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 2
            }

            Rectangle {
                width: 6
                height: 8
                radius: 1
                color: "#b8c0c4"
                border.color: "#6a7278"
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 2
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onClicked: neon.lit = !neon.lit
            }
        }

        ShelfButton {
            id: add
            z: 9
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 16
            anchors.rightMargin: 18
            pal: root.roomPal
            primary: true
            text: "Add to the shelf"
            onClicked: {
                upload.note = ""
                root.adding = true
            }
        }

        Row {
            id: heading
            z: 9
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: 12
            anchors.leftMargin: 18
            anchors.right: add.left
            anchors.rightMargin: 12
            spacing: 12

            Image {
                id: brand
                objectName: "shelfIcon"
                width: 48
                height: 48
                fillMode: Image.PreserveAspectFit
                asynchronous: false
                cache: false
                source: "shelf-icon.png"
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                width: heading.width - brand.width - heading.spacing

                Text {
                    text: "Parallel Shelf"
                    color: "#f5fbff"
                    font.pixelSize: 26
                    font.family: "Avenir Next"
                    font.letterSpacing: 0.4
                    style: Text.Outline
                    styleColor: "#071018"
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#f5fbff"
                    font.pixelSize: 14
                    font.family: "Avenir Next"
                    style: Text.Outline
                    styleColor: "#071018"
                    text: "A public library where anyone can add books."
                }
            }
        }

        Text {
            z: 9
            anchors.left: heading.left
            anchors.top: heading.bottom
            anchors.topMargin: 2
            anchors.right: add.left
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            color: "#f5fbff"
            font.pixelSize: 12
            font.family: "Avenir Next"
            style: Text.Outline
            styleColor: "#071018"
            visible: root.notice.length > 0
            text: root.notice
        }

        ShelfField {
            id: search
            z: 9
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 96
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            pal: root.roomPal
            placeholder: "Search titles and authors"
            onTextChanged: {
                root.query = text
                root.refresh()
            }
        }

        PlayerBar {
            id: playerBar
            z: 9
            anchors.bottom: parent.bottom
            width: parent.width
            visible: root.listening !== null
            pal: root.pal
            work: root.listening
            player: root.player
            note: root.listeningNote
            fetching: root.listeningPath ? 0 : library.fetchProgress
            onClosed: root.closePlayer()
        }
    }


    // Dims the shelf behind a panel. A click outside the panel closes it.
    Rectangle {
        anchors.fill: parent
        color: "#aa1c2321"
        visible: root.adding || root.reading !== null || saveBrowse.picking

        MouseArea {
            anchors.fill: parent
            onWheel: function (wheel) { wheel.accepted = true }
            onClicked: {
                if (root.reading) root.closeReader()
                else if (saveBrowse.picking) {
                    saveBrowse.close()
                    root.saving = null
                } else if (!library.sharing) root.adding = false
            }
        }
    }

    UploadPanel {
        id: upload
        anchors.centerIn: parent
        visible: root.adding
        pal: root.pal
        listFolder: function (path, done) { library.listFolder(path, done) }
        files: disk
        homeDir: library.homeDir
        busy: library.sharing
        progress: library.shareProgress
        onShare: function (title, author, source) {
            note = ""
            library.share(title, author, source)
        }
        onCancel: {
            if (library.sharing) library.cancelShare()
            root.adding = false
        }
        onPickRequested: {
            if (upload.hasDialog) {
                upload.openPicker()
                return
            }
            note = "Paste the full path below, or drop a file on this form."
        }
    }

    Browse {
        id: saveBrowse
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 460)
        height: Math.min(parent.height - 32, 520)
        pal: root.pal
        saveFolder: true
        onFolderChosen: function (path) {
            var work = root.saving
            if (!work) return
            library.saveCopy(work, path)
        }
    }

    ReaderPanel {
        id: reader
        anchors.centerIn: parent
        visible: root.reading !== null
        pal: root.pal
        files: disk
        work: root.reading
        pages: root.readingPages
        note: root.readingNote
        pdfBytes: root.readingPdf
        progress: library.fetchProgress
        pdfUrl: root.readingPdfUrl
        onClosed: root.closeReader()
        onPageChanged: {
            if (root.reading && Catalog.isPdf(root.readingPdf))
                root.paintCorePage(root.reading, reader.page)
        }
    }

}

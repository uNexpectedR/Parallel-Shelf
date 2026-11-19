import QtQuick 2.15
import Qt.labs.settings 1.0
import Qt.labs.platform 1.1
import "catalog.js" as Catalog

// The Logos side of Parallel Shelf. Nothing in here draws anything.
//
// How this view talks to Logos is copied from backpack's Basecamp view:
// every call goes through callVia → logos.callModuleAsync, never a blocking
// logos.callModule, never logos.module() on this view. Storage and Delivery
// are real modules, so that call is allowed.
//
// Sizes come from FolderListModel in this view. Bytes come from
// parallel_shelf_core (type:core, separate Logos host process) through
// logos.callModuleAsync, the same path backpack_ui uses for backpack_core.
// QmlSandbox cannot QFile; type:ui QQuickWidget crashed open; Storage
// cannot uploadUrl of ~/Downloads. Share/Open do not run in the Logos
// Execution Zone (LEZ is a zkVM program, not a Basecamp app). This view
// is ui_qml like backpack: logos.callModuleAsync to storage_module and
// parallel_shelf_core (muster uses lp_invoke from its Nim plugin; the
// QML equivalent is callModuleAsync, never logos.module on this view).
// Share is muster's fileshare_share: parallel_shelf_core reads the
// Choose file in 65536-byte chunks into AppData (swarmWorkDir) and
// storage_module.uploadUrl(staged, 65536, true) waits on
// storageUploadDone. If core cannot copy ~/Downloads (Mac TCC), Share
// still uploadUrl's the original path Storage can QFile-open — never
// a copy-failed error. During Share the view reads those same bytes
// into lastShare (a JS string map keyed by CID in this QML process).
// Open and Download use lastShare first. Mac logoscore does not share
// a QHash with this view, so Open must not depend on core remembering
// a path across the click. Core pdftoppm writes AppData page-N.png
// and the view writes it next to PdfPages.qml as page-<cid>-N.png. Never a
// Downloads path (Mac TCC), never file:// Image, never data: Image,
// never PdfPageView, never Qt Pdf in the core dylib, and never the
// title-card cover when the PDF has pages.
// Your Shelf is books this install Shared. Parallel Shelf is books
// other people Shared, from Logos Delivery catalogs. Settings stay
// parallel_shelf_v1 / 1.0.0 so this install’s shelf is not wiped.
// persistShelf stores only mine. Incoming catalogs merge without
// mine. Open of others fetches from Storage. Page count is a relative
// count-<cid>.png (width = pages), never file:// listing.
// The card CID is storageUploadDone's; manifests() never replaces it.
// Two CIDs stay two cards. Dest write is optional. A fetch that
// finishes with 0 bytes is a failure, not an empty reader. Empty dest
// still opens from the held bytes. Never downloadCancel. Never /tmp
// or /var/tmp. Do not call exists.
// Treat "Context already initialized" as success on every Storage method.
Item {
    id: lib
    visible: false

    property var works: []
    onWorksChanged: saveShelf.restart()
    property string storageState: "starting"   // starting, running or down
    property string deliveryState: "starting"  // starting, running or down
    property bool sharing: false
    property real shareProgress: 0
    property real fetchProgress: 0
    property real saveProgress: 0
    property bool saveBusy: false
    property string lastFetchFrom: ""
    property var saveAfter: null
    property string lastLocalMiss: ""
    property var shelfOwned: ({})

    signal shared(string title, bool announced)
    signal shareFailed(string why)
    signal textReady(var work, string text)
    signal fileReady(var work, string path)
    signal bytesReady(var work, string bytes)
    signal fetchFailed(var work, string why)
    signal fileChosen(string path)
    signal saveReady(var work, string path)
    signal saveFailed(var work, string why)

    onFetchFailed: {
        openWatch.stop()
        openingWork = null
        holdLoading = false
    }

    property var host: null                 // the logos object, from Main or Basecamp
    property var bridge: null
    property int bridgeTries: 0
    readonly property int callTimeoutMs: 30000
    readonly property string homeDir: ""
    property bool fileDone: false

    property int deliveryTries: 0
    property int storePeer: 0
    property var seenMessages: ({})
    property string unannounced: ""

    property var queue: []
    property var job: null
    property string jobBytes: ""
    property int jobWant: 0
    property int jobSeen: 0
    property string lastCall: ""
    property string lastCallError: ""
    property bool lastStorageNoise: false
    property var fetchedCatalogs: ({})
    property int largestCatalog: 0
    property string lastEventKey: ""

    property var draft: null
    property string fileSession: ""
    property var files: null                 // FileBytes.qml: FolderListModel sizes, core readPiece
    property string fileDisk: ""
    property string fileSource: ""
    property string filePending: ""
    property int fileAt: 0
    property int fileLen: 0
    property int fileChunk: 65536
    property int fileGen: 0
    property string fileHold: ""
    property var fileParts: []
    property var shareHold: ({})
    property var lastShare: ({})
    property var lastShareFile: ({})
    property string lastShareCid: ""
    property string lastShareBytes: ""
    property string pendingShareBytes: ""
    property string sharePullCid: ""
    property string sharePullBytes: ""
    property var sharePullFinish: null
    property var byCid: ({})
    readonly property string shelfEpoch: "1.0.0"
    property var openingWork: null
    property var pendingUpload: null
    property bool holdLoading: false
    property bool freezePersist: false

    property bool catalogBusy: false
    property bool catalogStale: false
    property string catalogSession: ""
    property var catalogParts: []
    property int catalogPart: 0
    property int catalogCount: 0
    property int catalogFailures: 0
    property int catalogGen: 0

    readonly property var storePeers: [
        "/dns4/delivery-01.do-ams3.logos.dev.status.im/tcp/30303/p2p/16Uiu2HAmTUbnxLGT9JvV6mu9oPyDjqHK4Phs1VDJNUgESgNSkuby",
        "/dns4/delivery-02.do-ams3.logos.dev.status.im/tcp/30303/p2p/16Uiu2HAmMK7PYygBtKUQ8EHp7EfaD3bCEsJrkFooK8RQ2PVpJprH",
        "/dns4/delivery-01.gc-us-central1-a.logos.dev.status.im/tcp/30303/p2p/16Uiu2HAm4S1JYkuzDKLKQvwgAhZKs9otxXqt8SCGtB4hoJP1S397",
        "/dns4/delivery-02.gc-us-central1-a.logos.dev.status.im/tcp/30303/p2p/16Uiu2HAm8Y9kgBNtjxvCnf1X6gnZJW5EGE4UwwCL3CCm55TwqBiH"
    ]

    Settings {
        id: saved
        category: "parallel_shelf_v1"
        property string catalog: ""
        property string shelf: ""
        property string locals: ""
        property string holds: ""
        property string epoch: ""
    }

    onHostChanged: if (lib.host && !lib.bridge) lib.findBridge()

    Timer { id: bridgeSearch; interval: 100; running: true; repeat: true; onTriggered: lib.findBridge() }
    Timer { id: giveUp; interval: 25000; onTriggered: lib.stopWaiting() }
    Timer { id: deliveryRetry; interval: 1500; onTriggered: lib.startDelivery() }
    Timer { id: jobWatch; interval: 60000; onTriggered: lib.jobTimedOut() }
    Timer { id: jobPoll; interval: 400; repeat: true; onTriggered: lib.pollJob() }
    Timer { id: jobGrace; interval: 800; onTriggered: lib.jobStreamClosed() }
    Timer { id: republish; onTriggered: if (lib.works.length > lib.largestCatalog) lib.publishCatalog() }
    Timer { id: saveShelf; interval: 500; onTriggered: lib.persistShelf() }
    Timer { id: openWatch; interval: 1800; onTriggered: lib.openTimedOut() }

    function log(line) {
        console.log("parallel-shelf: " + line)
    }

    // ---- Talking to Basecamp (backpack callVia) --------------------------

    function _deliver(cb, raw) {
        if (!cb) return
        try { cb(raw === undefined || raw === null ? "" : raw) } catch (e) { log(String(e)) }
    }

    // The only way this view talks to a module. Copied from backpack_ui
    // Main.qml: logos.callModuleAsync, and if that is missing, a deferred
    // logos.callModule so the current frame still paints.
    function callVia(module, method, args, cb, timeoutMs) {
        var a = args || []
        var ms = timeoutMs || lib.callTimeoutMs
        var label = module + "." + method
        var api = lib.bridge || lib.host
        function fail(why) {
            lib._deliver(cb, JSON.stringify({ success: false, value: null, error: label + ": " + why }))
        }
        function wrap(raw) {
            if (raw === undefined || raw === null || raw === "") {
                fail("no answer")
                return
            }
            lib._deliver(cb, raw)
        }
        if (!api) {
            Qt.callLater(function () { fail("no Logos bridge") })
            return
        }
        if (typeof api.callModuleAsync === "function") {
            try {
                api.callModuleAsync(module, method, a, wrap, ms)
            } catch (e) {
                Qt.callLater(function () { fail(String(e)) })
            }
            return
        }
        Qt.callLater(function () {
            var raw = ""
            try { raw = api.callModule(module, method, a) } catch (e) {
                fail(String(e))
                return
            }
            wrap(raw)
        })
    }

    function missingDestStat(msg) {
        var s = String(msg || "").toLowerCase()
        if (s.indexOf("not found") < 0) return false
        return s.indexOf("filesize") >= 0 || s.indexOf("file not found") >= 0
    }

    function setLastCallError(msg) {
        if (Catalog.alreadyInitialized(msg) || Catalog.storageNoise({ error: msg }, msg))
            return
        if (missingDestStat(msg))
            return
        var s = String(msg || "")
        if (s.indexOf("no writable dest") >= 0 || s.indexOf("fetchDest") >= 0)
            return
        if (s.indexOf("downloadCancel") >= 0)
            return
        lastCallError = msg
    }

    function readerWhy(why) {
        var s = String(why || "")
        if (s.indexOf("no writable dest") >= 0 || s.indexOf("fetchDest") >= 0)
            return "Logos Storage could not find it."
        if (s.indexOf("no file at") >= 0)
            return "Logos Storage could not find it."
        if (s.indexOf("downloadCancel") >= 0)
            return "Logos Storage could not find it."
        return s
    }

    function call(module, method, args, done, timeoutMs) {
        if (module === "parallel_shelf") {
            done({ ok: false, value: null, error: "view modules must be called via logos.module()" })
            return
        }
        var label = module + "." + method
        lastCall = label
        lastStorageNoise = false
        lib.callVia(module, method, args, function (raw) {
            var r = Catalog.readResult(raw)
            if (module === "storage_module" && Catalog.storageNoise(r, raw)) {
                lastStorageNoise = true
                log(label + ": context already initialized (ignored)")
                done({ ok: true, value: r.value, error: "" })
                return
            }
            if (!r.ok && r.error) {
                var labeled = r.error.indexOf(label) === 0 ? r.error : (label + ": " + r.error)
                if (Catalog.alreadyInitialized(labeled)) {
                    lastStorageNoise = true
                    done({ ok: true, value: r.value, error: "" })
                    return
                }
                if (labeled.indexOf("No hold") >= 0 || labeled.indexOf("No source") >= 0) {
                    done(r)
                    return
                }
                if (!missingDestStat(labeled)) {
                    setLastCallError(labeled)
                    log(labeled)
                }
            }
            done(r)
        }, timeoutMs)
    }

    function findBridge() {
        var found = lib.host
        try {
            if (!found && typeof logos !== "undefined") found = logos
        } catch (e) {
        }
        if (!found) {
            if (bridge) return
            if (++bridgeTries > 30) {
                bridgeSearch.stop()
                storageState = "down"
                deliveryState = "down"
                log("no Logos bridge, so this is not running inside Basecamp")
            }
            return
        }
        if (bridge) return
        try {
            if (found.callModuleAsync || found.callModule) bridge = found
        } catch (e) {
            log("bridge: " + e)
        }
        if (bridge) {
            bridgeSearch.stop()
            restoreShelf()
            listen()
            giveUp.start()
            startStorage()
            startDelivery()
            return
        }
        if (++bridgeTries > 30) {
            bridgeSearch.stop()
            storageState = "down"
            deliveryState = "down"
            log("no Logos bridge, so this is not running inside Basecamp")
        }
    }

    function listFolder(path, done) {
        var start = path || ""
        if (!start) {
            var os = Qt.platform.os
            start = (os === "osx" || os === "macos") ? "/Users" : (os === "linux" ? "/home" : "/")
        }
        done(start, [])
    }

    function listen() {
        var events = {
            "storage_module": ["storageStart", "storageUploadProgress", "storageUploadDone",
                               "storageDownloadProgress", "storageDownloadDone",
                               "storageDownloadManifestDone"],
            "delivery_module": ["messageReceived"]
        }
        var module
        for (module in events) {
            var i
            for (i = 0; i < events[module].length; i++)
                watchModule(module, events[module][i])
        }
    }

    // Mac Basecamp delivers Storage events on logos.watch / moduleEventReceived,
    // not by calling the view's onModuleEvent. Share never needed that (each
    // uploadChunk is a callVia answer). Open pieces come the other way.
    function watchModule(module, event) {
        var api = lib.bridge || lib.host
        if (!api) return
        if (typeof api.onModuleEvent === "function") {
            try {
                if (api.onModuleEvent(module, event) !== true)
                    log("could not listen for " + module + "." + event)
            } catch (e) {
                log("onModuleEvent " + module + "." + event + ": " + e)
            }
        }
        if (typeof api.watch === "function") {
            try {
                api.watch(module, event, function (data) {
                    lib.handleEvent(module, event, data)
                })
            } catch (e) {
            }
        }
    }

    function handleEvent(module, event, data) {
        var key = module + "." + event + ":" + String(data && data.length !== undefined ? data[0] : data).substring(0, 96)
        if (key && key === lastEventKey) return
        lastEventKey = key
        if (module === "storage_module") {
            var payload = Catalog.eventPayload(data)
            if (payload) onStorage(event, payload)
        } else if (module === "delivery_module" && event === "messageReceived") {
            onMessage(part(data, 0), part(data, 1), part(data, 2), part(data, 4))
        }
    }

    function part(data, index) {
        try {
            var value = data[index]
            return value === null || value === undefined ? "" : String(value)
        } catch (e) {
            return ""
        }
    }

    function stopWaiting() {
        if (storageState === "starting") storageState = "down"
        if (deliveryState === "starting") deliveryState = "down"
    }

    // ---- Logos Storage ----------------------------------------------------

    function startStorage() {
        call("storage_module", "isRunning", [], function (running) {
            if (running.ok && running.value === true) {
                storageReady()
                return
            }
            call("storage_module", "loadConfigOrDefault", [], function (config) {
                var text = typeof config.value === "string" ? config.value : JSON.stringify(config.value)
                if (!config.ok || !config.value) {
                    log("storage config: " + config.error)
                    storageState = "down"
                    return
                }
                call("storage_module", "init", [text], function (inited) {
                    if (!inited.ok && !Catalog.alreadyDone(inited.error)) {
                        log("storage init: " + inited.error)
                        storageState = "down"
                        return
                    }
                    call("storage_module", "start", [], function (started) {
                        if (!started.ok && !Catalog.alreadyDone(started.error)) {
                            log("storage start: " + started.error)
                            storageState = "down"
                        }
                    })
                })
            })
        })
    }

    function storageReady() {
        if (storageState === "running") return
        storageState = "running"
        restoreShelf()
        wantCatalog(saved.catalog)
        next()
    }

    readonly property alias savedEpoch: saved.epoch
    readonly property alias savedShelf: saved.shelf

    function persistShelf() {
        if (freezePersist) return
        saved.epoch = shelfEpoch
        var mine = onlyMine(works)
        if (!mine.length) {
            saved.shelf = ""
            return
        }
        saved.shelf = Catalog.shelfDocument(mine)
    }

    function forgetOldShelf() {
        if (saved.epoch === shelfEpoch) return
        saved.catalog = ""
        saved.shelf = ""
        saved.locals = ""
        saved.holds = ""
        saved.epoch = shelfEpoch
    }

    function readLocals() {
        try {
            var obj = JSON.parse(saved.locals || "{}")
            return obj && typeof obj === "object" ? obj : {}
        } catch (e) {
            return {}
        }
    }

    function rememberLocal(cid, path) {
        cid = Catalog.cleanText(cid, 200)
        if (!cid) return
        var map = readLocals()
        var prev = Catalog.safeSource(map[cid])
        var next = Catalog.safeSource(path)
        if (next && next.indexOf(".missing") < 0)
            map[cid] = next
        else if (map[cid] === undefined)
            map[cid] = prev || ""
        saved.locals = JSON.stringify(map)
    }

    function forgetLocal(cid) {
        cid = Catalog.cleanText(cid, 200)
        if (!cid) return
        var map = readLocals()
        delete map[cid]
        saved.locals = JSON.stringify(map)
        var next = {}
        var k
        var rec
        for (k in byCid) {
            if (String(k) === cid) {
                rec = byCid[k] || {}
                next[k] = { source: "", holdPath: rec.holdPath || "" }
            } else {
                next[k] = byCid[k]
            }
        }
        byCid = next
    }

    function localPath(cid) {
        return Catalog.safeSource(readLocals()[cid])
    }

    function readHolds() {
        try {
            var obj = JSON.parse(saved.holds || "{}")
            return obj && typeof obj === "object" ? obj : {}
        } catch (e) {
            return {}
        }
    }

    function rememberHold(cid, path) {
        cid = Catalog.cleanText(cid, 200)
        if (!cid) return
        var map = readHolds()
        var next = Catalog.safeSource(path)
        if (next) map[cid] = next
        saved.holds = JSON.stringify(map)
    }

    function holdSaved(cid) {
        return Catalog.safeSource(readHolds()[cid])
    }

    function stampHoldPath(cid, path) {
        path = Catalog.safeSource(path)
        cid = Catalog.cleanText(cid, 200)
        if (!cid || !path) return
        rememberHold(cid, path)
        var next = []
        var i
        var changed = false
        for (i = 0; i < works.length; i++) {
            var w = works[i]
            if (w && String(w.cid) === String(cid) && w.holdPath !== path) {
                var item = {}
                var k
                for (k in w) item[k] = w[k]
                item.holdPath = path
                item.mine = true
                next.push(item)
                changed = true
            } else {
                next.push(w)
            }
        }
        if (changed) works = next
        persistShelf()
    }

    function isMine(work) {
        if (!work) return false
        if (work.mine) return true
        var cid = Catalog.cleanText(work.cid, 200)
        if (!cid) return false
        if (shelfOwned[cid]) return true
        if (localPath(cid)) return true
        return false
    }

    function ownCid(cid) {
        cid = Catalog.cleanText(cid, 200)
        if (!cid) return
        var next = {}
        var k
        for (k in shelfOwned) next[k] = shelfOwned[k]
        next[cid] = true
        shelfOwned = next
    }

    function onLocalShelf(work) {
        if (isMine(work)) return true
        return !!(work && work.cid && shelfOwned[work.cid])
    }

    function stampLocals(list) {
        var i
        for (i = 0; i < (list || []).length; i++) {
            var w = list[i]
            if (!w || !w.cid) continue
            if (shelfOwned[w.cid] || w.mine) {
                w.mine = true
                ownCid(w.cid)
            }
        }
        return list
    }

    function onlyMine(list) {
        var next = []
        var i
        for (i = 0; i < (list || []).length; i++) {
            var w = list[i]
            if (!w || !w.cid) continue
            if (!(w.mine || shelfOwned[w.cid] || localPath(w.cid)))
                continue
            w.mine = true
            ownCid(w.cid)
            var src = localPath(w.cid)
            if (src && !Catalog.safeSource(w.source))
                w.source = src
            next.push(w)
        }
        return next
    }

    function restoreShelf() {
        forgetOldShelf()
        if (works.length) {
            var owned = 0
            var i
            for (i = 0; i < works.length; i++) {
                if (isMine(works[i])) owned++
            }
            if (!owned && saved.shelf)
                restoreMine()
            return
        }
        var listed = onlyMine(Catalog.readCatalog(saved.shelf, true) || [])
        if (listed.length) {
            works = stampLocals(listed)
            persistShelf()
        }
    }

    function destPdfReady(n) {
        n = Number(n) || 0
        if (n < 1000) return false
        if (!job || job.kind !== "file" || !job.path) return false
        if (!(job.work && Catalog.extensionOf(job.work.filename) === "pdf"))
            return false
        var want = jobWant || (job.work.size > 0 ? job.work.size : 0)
        if (want > 0) return n >= want
        return n > 1000
    }

    function fetchedEnough() {
        if (destPdfReady(jobSeen)) return true
        if (!job || !jobBytes.length) return false
        if (job.kind === "catalog") return false
        if (job.kind === "file" && job.work && Catalog.extensionOf(job.work.filename) === "pdf"
                && !Catalog.isPdf(jobBytes))
            return false
        if (jobWant > 0 && jobBytes.length < jobWant) return false
        return true
    }

    function onDownloadDone(p) {
        if (!job || (p.sessionId && p.sessionId !== job.cid)) return
        if (job.kind === "catalog") {
            if (p.success === false && !Catalog.alreadyInitialized(p.error))
                finishJob(false, p.error || "The catalog could not be read.")
            else
                finishJob(!!jobBytes.length, jobBytes.length ? "" : "The catalog was empty.")
            return
        }
        if (p.success === false && !Catalog.alreadyInitialized(p.error)) {
            if (fetchedEnough()) finishJob(true, "")
            else openHoldThenFinish(job, p.error || "Logos Storage could not find it.")
            return
        }
        job.streamDone = true
        if (fetchedEnough()) finishJob(true, "")
        else openIfDestReady(job, function () {
            if (!job) return
            if (fetchedEnough()) finishJob(true, "")
            else openHoldThenFinish(job, "")
        })
    }

    function jobStreamClosed() {
        if (!job) return
        if (fetchedEnough()) finishJob(true, "")
        else if (retryWithoutLocal(job))
            return
        else if (!jobBytes.length)
            finishJob(false, "Logos Storage returned an empty file.")
    }

    function retryWithoutLocal(started) {
        if (!started || job !== started) return false
        if (started.kind === "catalog") return false
        if (started.triedNetwork) return false
        if (fetchedEnough()) return false
        started.triedNetwork = true
        started.local = false
        started.asked = false
        started.pulled = false
        lastEventKey = ""
        jobGrace.stop()
        jobWatch.restart()
        log("fetch local miss, retry downloadChunks local=false cid=" + started.cid)
        startDownload(started)
        return true
    }

    function onStorage(event, p) {
        if (event === "storageStart") {
            if (p.success === true) storageReady()
            else storageState = "down"
        } else if (event === "storageUploadProgress") {
            if (catalogSession && p.sessionId === catalogSession) catalogProgress(p)
            else if (fileSession && p.sessionId === fileSession) fileProgress(p)
        } else if (event === "storageUploadDone") {
            if (fileSession && p.sessionId === fileSession)
                onFileUploadDone(p)
            else if (sharing && !fileDone && !fileSession)
                pendingUpload = p
        } else if (event === "storageDownloadProgress") {
            if (sharePullCid && p.sessionId === sharePullCid) {
                if (p.chunk) sharePullBytes += Catalog.b64decode(p.chunk)
                return
            }
            jobProgress(p)
        } else if (event === "storageDownloadDone") {
            if (sharePullCid && p.sessionId === sharePullCid) {
                finishSharePull(sharePullBytes)
                return
            }
            onDownloadDone(p)
        } else if (event === "storageDownloadManifestDone") {
            onManifest(p)
        }
    }

    // ---- Logos Delivery ---------------------------------------------------

    function startDelivery() {
        call("delivery_module", "createNode", ['{"mode":"Edge","preset":"logos.dev"}'], function (created) {
            if (!created.ok && !Catalog.alreadyDone(created.error)) return deliveryFailed("createNode", created.error)
            call("delivery_module", "start", [], function (started) {
                if (!started.ok && !Catalog.alreadyDone(started.error)) return deliveryFailed("start", started.error)
                call("delivery_module", "subscribe", [Catalog.TOPIC], function (subscribed) {
                    if (!subscribed.ok && !Catalog.alreadyDone(subscribed.error))
                        return deliveryFailed("subscribe", subscribed.error)
                    deliveryState = "running"
                    readHistory()
                    announce()
                })
            })
        })
    }

    function deliveryFailed(step, why) {
        log("delivery " + step + ": " + why)
        if (deliveryTries < 2) {
            deliveryTries++
            deliveryRetry.restart()
        } else {
            deliveryState = "down"
        }
    }

    function onMessage(hash, topic, body, timestamp) {
        if (topic && topic !== Catalog.TOPIC) return
        if (hash) {
            if (seenMessages[hash]) return
            seenMessages[hash] = true
        }
        var pointer = Catalog.readPointer(body)
        if (pointer)
            wantCatalog(pointer, timestamp)
    }

    function readHistory() {
        if (storePeer >= storePeers.length) return
        var query = JSON.stringify({
            requestId: "parallel-shelf-" + storePeer,
            includeData: true,
            paginationForward: false,
            contentTopics: [Catalog.TOPIC],
            paginationLimit: 50
        })
        call("delivery_module", "storeQuery", [query, storePeers[storePeer], 15000], function (answer) {
            var page = typeof answer.value === "string" ? Catalog.readJson(answer.value) : answer.value
            var messages = page && page.messages ? page.messages : []
            if (!answer.ok || !messages.length) {
                storePeer++
                readHistory()
                return
            }
            var i
            for (i = 0; i < messages.length; i++) {
                var message = messages[i] && messages[i].message ? messages[i].message : messages[i]
                var pointer = Catalog.readPointer(message ? message.payload : "")
                if (pointer)
                    wantCatalog(pointer, message ? message.timestamp : 0)
            }
        }, 20000)
    }

    function announce() {
        if (!unannounced || deliveryState !== "running") return
        var cid = unannounced
        call("delivery_module", "send", [Catalog.TOPIC, Catalog.catalogPointer(cid)], function (sent) {
            if (!sent.ok) log("announce: " + sent.error)
            else if (unannounced === cid) unannounced = ""
        })
    }

    // ---- Fetching from Storage --------------------------------------------

    function wantCatalog(cid, deliveredAt) {
        cid = Catalog.cleanText(cid, 200)
        if (!cid || fetchedCatalogs[cid] || queue.length >= Catalog.QUEUE_MAX) return
        fetchedCatalogs[cid] = true
        log("want catalog " + cid)
        queue = queue.concat([{
            cid: cid,
            kind: "catalog",
            work: null,
            path: "",
            limit: Catalog.CATALOG_BYTES_MAX,
            deliveredAt: Catalog.stampAddedAt(deliveredAt)
        }])
        next()
    }

    function applyCatalogList(listed, cid, deliveredAt) {
        if (!listed) return
        if (listed.length >= largestCatalog) {
            largestCatalog = listed.length
            if (cid) saved.catalog = cid
        }
        var at = Catalog.stampAddedAt(deliveredAt)
        var i
        if (at) {
            for (i = 0; i < listed.length; i++) {
                if (listed[i] && !Catalog.stampAddedAt(listed[i].addedAt))
                    listed[i].addedAt = at
            }
        }
        var before = works.length
        works = Catalog.merge(works, listed)
        var names = []
        for (i = 0; i < listed.length; i++) {
            if (listed[i] && listed[i].title)
                names.push(listed[i].title)
        }
        log("catalog " + (cid || "") + " listed=" + listed.length
            + " shelf=" + works.length + " added=" + (works.length - before)
            + (names.length ? (" titles=" + names.join(", ")) : ""))
    }

    function ingestCatalog(text, cid, announce) {
        var listed = Catalog.readCatalog(text)
        if (!listed) {
            log("catalog ingest failed")
            return 0
        }
        applyCatalogList(listed, cid || "", 0)
        if (announce === false)
            largestCatalog = Math.max(largestCatalog, works.length)
        return listed.length
    }

    function tryLocation(loc) {
        try {
            var root = String(StandardPaths.writableLocation(loc) || "").replace(/\/+$/, "")
            if (root && root.charAt(0) === "/" && !Catalog.isGlobalTmp(root))
                return root
        } catch (e) {
        }
        return ""
    }

    function destRoot() {
        // Muster swarmWorkDir is instance persistence / AppData, not Cache.
        var keys = []
        try { keys.push(StandardPaths.AppDataLocation) } catch (e) {}
        try { keys.push(StandardPaths.AppLocalDataLocation) } catch (e) {}
        try { keys.push(StandardPaths.GenericDataLocation) } catch (e) {}
        try { keys.push(StandardPaths.CacheLocation) } catch (e) {}
        try { keys.push(StandardPaths.GenericCacheLocation) } catch (e) {}
        try { keys.push(StandardPaths.TempLocation) } catch (e) {}
        try { keys.push(StandardPaths.DocumentsLocation) } catch (e) {}
        try { keys.push(StandardPaths.DesktopLocation) } catch (e) {}
        try { keys.push(StandardPaths.HomeLocation) } catch (e) {}
        var i, root
        for (i = 0; i < keys.length; i++) {
            root = tryLocation(keys[i])
            if (root) return root
        }
        return ""
    }

    function destPath(work) {
        return Catalog.destPath(work, destRoot())
    }

    function downloadsDir() {
        var root = ""
        try {
            root = String(StandardPaths.writableLocation(StandardPaths.DownloadLocation) || "")
        } catch (e) {
            root = ""
        }
        root = root.replace(/\/+$/, "")
        if (root && root.charAt(0) === "/" && !Catalog.isGlobalTmp(root)) {
            if (root.indexOf("/Downloads") >= 0) return root
            return root + "/Downloads"
        }
        try {
            root = String(StandardPaths.writableLocation(StandardPaths.HomeLocation) || "")
        } catch (e2) {
            root = ""
        }
        root = root.replace(/\/+$/, "")
        if (root && root.charAt(0) === "/" && !Catalog.isGlobalTmp(root))
            return root + "/Downloads"
        if (homeDir) return String(homeDir).replace(/\/+$/, "") + "/Downloads"
        return ""
    }

    function paintPathOf(path) {
        path = Catalog.safeSource(path)
        if (!path || path.charAt(0) !== "/") return ""
        if (Catalog.isGlobalTmp(path)) return ""
        if (path.indexOf("/Downloads/") >= 0 || path.indexOf("/Downloads") === path.length - 10)
            return ""
        return path
    }

    function keepLastShare(cid, bytes, path, own) {
        cid = Catalog.cleanText(cid, 200)
        if (!cid || !bytes || !bytes.length) return
        var copy = ["", bytes].join("")
        var next = {}
        var k
        var cur = lastShare
        for (k in cur) next[k] = cur[k]
        next[cid] = copy
        lastShare = next
        lastShareCid = cid
        lastShareBytes = copy
        // PdfDocument must not open ~/Downloads (Mac TCC). Prefer the
        // staged AppData copy this view still holds.
        path = paintPathOf(path) || paintPathOf(fileDisk) || paintPathOf(fileSource)
        if (path) {
            var filesNext = {}
            var curFiles = lastShareFile
            for (k in curFiles) filesNext[k] = curFiles[k]
            filesNext[cid] = path
            lastShareFile = filesNext
        }
        if (own !== false)
            ownCid(cid)
    }

    // PdfDocument URL from this view (not logoscore). file:// of the
    // staged AppData copy, never ~/Downloads. Open must not ask core.
    function viewPaintUrl(work) {
        var cid = work && Catalog.cleanText(work.cid, 200)
        var path = paintPathOf(cid && lastShareFile && lastShareFile[cid])
        if (path) return "file://" + path
        return ""
    }

    function lastShareOf(cid) {
        cid = Catalog.cleanText(cid, 200)
        if (!cid || !lastShare) return ""
        return lastShare[cid] || ""
    }

    // Bytes this QML view already holds. Open/Download use this first.
    // lastShare is not cleared here, on Open, or on Close.
    function viewBytes(work) {
        var cid = work && work.cid
        var want = work && work.size > 0 ? work.size : 0
        var filename = work && work.filename
        var cached = lastShareOf(cid)
        if (Catalog.shareHit(cached, want, filename)) return cached
        if (cid && cid === lastShareCid && Catalog.shareHit(lastShareBytes, want, filename))
            return lastShareBytes
        cached = heldShared(cid, want, filename)
        if (cached) return cached
        return ""
    }

    function holdShared(cid, bytes, skipDisk) {
        cid = Catalog.cleanText(cid, 200)
        if (!cid || !bytes || !bytes.length) return
        keepLastShare(cid, bytes)
        var next = {}
        var k
        var cur = shareHold
        for (k in cur) next[k] = cur[k]
        next[cid] = lastShareOf(cid)
        shareHold = next
        if (files && typeof files.writeAll === "function")
            files.writeAll("memory:" + cid, bytes, function () {})
        if (!skipDisk && files && typeof files.persistHold === "function") {
            files.persistHold(cid, bytes, function () {})
        }
    }

    function heldShared(cid, want, filename) {
        cid = Catalog.cleanText(cid, 200)
        if (!cid) return ""
        var bytes = lastShareOf(cid)
        if (!bytes && cid === lastShareCid) bytes = lastShareBytes
        if (!bytes) bytes = (shareHold && shareHold[cid]) || ""
        if (Catalog.shareHit(bytes, want, filename)) return bytes
        return ""
    }

    function workByCid(cid) {
        cid = Catalog.cleanText(cid, 200)
        if (!cid) return null
        var i
        for (i = 0; i < works.length; i++) {
            if (works[i] && Catalog.cleanText(works[i].cid, 200) === cid)
                return works[i]
        }
        return null
    }

    function rememberCard(cid, source, holdPath) {
        cid = Catalog.cleanText(cid, 200)
        if (!cid) return
        var rec = {
            source: Catalog.safeSource(source),
            holdPath: Catalog.safeSource(holdPath)
        }
        var next = {}
        var k
        for (k in byCid) next[k] = byCid[k]
        next[cid] = rec
        byCid = next
        rememberLocal(cid, rec.source)
        if (rec.holdPath) rememberHold(cid, rec.holdPath)
        ownCid(cid)
    }

    function cardSource(work) {
        var cid = work && work.cid
        var rec = byCid[cid]
        return Catalog.safeSource(work && work.source)
            || localPath(cid)
            || (rec && rec.source)
            || ""
    }

    function cardHold(work) {
        var cid = work && work.cid
        var rec = byCid[cid]
        return Catalog.safeSource(work && work.holdPath)
            || holdSaved(cid)
            || (rec && rec.holdPath)
            || ""
    }

    function filledWork(work) {
        if (!work) return work
        var found = workByCid(work.cid)
        var view = {}
        var k
        var src = found || work
        for (k in src) view[k] = src[k]
        for (k in work) {
            if (view[k] === undefined) view[k] = work[k]
        }
        if (isMine(view)) {
            var source = cardSource(view)
            var hold = cardHold(view)
            if (source) view.source = source
            if (hold) view.holdPath = hold
            view.mine = true
        }
        return view
    }

    // Books this install Shared (saved.shelf / locals) are mine again.
    // Catalog extras stay not-mine. In-memory un-own from proofs is undone
    // without wiping persist.
    function restoreMine() {
        freezePersist = false
        var listed = onlyMine(Catalog.readCatalog(saved.shelf, true) || [])
        var i, k
        for (i = 0; i < listed.length; i++) {
            if (listed[i] && listed[i].cid)
                ownCid(listed[i].cid)
        }
        var owned = {}
        for (i = 0; i < listed.length; i++) {
            if (listed[i] && listed[i].cid)
                owned[listed[i].cid] = listed[i]
        }
        var list = []
        var seen = {}
        for (i = 0; i < works.length; i++) {
            var w = works[i]
            if (!w || !w.cid) continue
            var cid = String(w.cid)
            var item = {}
            for (k in w) item[k] = w[k]
            var savedWork = owned[cid]
            if (savedWork || shelfOwned[cid] || localPath(cid)) {
                item.mine = true
                if (savedWork) {
                    if (savedWork.source) item.source = savedWork.source
                    if (savedWork.holdPath) item.holdPath = savedWork.holdPath
                    if (savedWork.addedAt && (!item.addedAt || savedWork.addedAt < item.addedAt))
                        item.addedAt = savedWork.addedAt
                }
                var src = localPath(cid)
                if (src && !Catalog.safeSource(item.source))
                    item.source = src
                ownCid(cid)
            } else {
                delete item.mine
                delete item.source
                delete item.holdPath
            }
            list.push(item)
            seen[cid] = true
        }
        for (i = 0; i < listed.length; i++) {
            var mine = listed[i]
            if (!mine || !mine.cid || seen[mine.cid]) continue
            mine.mine = true
            ownCid(mine.cid)
            list.push(mine)
        }
        works = Catalog.byAddTime(stampLocals(list))
        persistShelf()
        log("restore mine n=" + onlyMine(works).length + " shelf=" + works.length)
        return onlyMine(works).length
    }

    function stampByCid(list) {
        var i
        for (i = 0; i < (list || []).length; i++) {
            var w = list[i]
            if (!w || !w.cid) continue
            var rec = byCid[w.cid]
            if (!rec) continue
            if (!Catalog.safeSource(w.source) && rec.source) w.source = rec.source
            if (!Catalog.safeSource(w.holdPath) && rec.holdPath) w.holdPath = rec.holdPath
            w.mine = true
        }
        return list
    }

    function openFromHold(work, bytes) {
        openWatch.stop()
        openingWork = null
        fetchProgress = 1
        log("open bytes cid=" + work.cid + " bytes=" + bytes.length)
        if (Catalog.isText(work.filename)) {
            textReady(work, Catalog.utf8decode(bytes))
            return
        }
        if (work.kind === "audiobook") {
            var audioDest = destPath(work)
            if (audioDest && audioDest.charAt(0) === "/" && !Catalog.isGlobalTmp(audioDest)
                    && files && typeof files.writeAll === "function") {
                files.ensureDir(audioDest, function () {
                    files.writeAll(audioDest, bytes, function (ok) {
                        if (ok) fileReady(work, audioDest)
                        else fetchFailed(work, Catalog.CHOOSE_AGAIN)
                    })
                })
                return
            }
            fetchFailed(work, Catalog.CHOOSE_AGAIN)
            return
        }
        bytesReady(work, bytes)
        // Count stubs and Storage dest PDFs must not be overwritten.
        if (lastFetchFrom === "downloadToUrl" || lastFetchFrom === "hold")
            return
        var dest = destPath(work)
        if (dest && dest.charAt(0) === "/" && !Catalog.isGlobalTmp(dest)
                && files && typeof files.writeAll === "function") {
            files.ensureDir(dest, function () {
                files.writeAll(dest, bytes, function (ok) {
                    if (ok) fileReady(work, dest)
                })
            })
        }
    }

    function destFor(work, done) {
        if (typeof done !== "function") return
        var dest = destPath(work)
        if (!(dest && dest.charAt(0) === "/" && !Catalog.isGlobalTmp(dest))) {
            var root = ""
            if (files && typeof files.holdRoot === "function")
                root = files.holdRoot() || ""
            if (!root)
                root = "/Users/unexpectedr/Library/Application Support/Logos/LogosBasecamp"
            dest = Catalog.destPath(work, root)
        }
        log("destFor cid=" + (work && work.cid) + " dest=" + dest)
        if (dest && dest.charAt(0) === "/" && !Catalog.isGlobalTmp(dest))
            done(dest)
        else
            done("")
    }

    function dropJob() {
        if (job && job.kind === "catalog" && job.cid) {
            var cid = job.cid
            var i, queued = false
            for (i = 0; i < queue.length; i++) {
                if (queue[i] && queue[i].kind === "catalog" && queue[i].cid === cid)
                    queued = true
            }
            if (!queued) {
                fetchedCatalogs[cid] = true
                queue = [{ cid: cid, kind: "catalog", work: null, path: "",
                           limit: Catalog.CATALOG_BYTES_MAX,
                           deliveredAt: job.deliveredAt || 0 }].concat(queue)
            }
        }
        jobWatch.stop()
        jobPoll.stop()
        jobGrace.stop()
        job = null
        jobBytes = ""
        jobWant = 0
        jobSeen = 0
    }

    function retrieveFromStorage(work) {
        destFor(work, function (dest) {
            if (!openingWork || openingWork.cid !== work.cid) return
            if (dest && dest.charAt(0) === "/" && !Catalog.isGlobalTmp(dest)) {
                log("open dest cid=" + work.cid + " path=" + dest)
                fetchFromStorage(work, dest)
                return
            }
            fetchFailed(work, isMine(work) ? Catalog.CHOOSE_AGAIN
                        : "Logos Storage could not find it.")
        })
    }

    function fetch(work) {
        lastLocalMiss = ""
        lastFetchFrom = ""
        holdLoading = true
        openingWork = work
        openWatch.restart()
        fetchProgress = 0
        if (!work || !work.cid) {
            fetchFailed(work, isMine(work) ? Catalog.CHOOSE_AGAIN
                        : "Logos Storage could not find it.")
            return
        }
        var cached = viewBytes(work)
        if (cached) {
            lastFetchFrom = "lastShare"
            fetchProgress = 1
            log("fetch lastShare cid=" + work.cid + " bytes=" + cached.length)
            dropJob()
            openFromHold(work, cached)
            next()
            return
        }

        function beginDisk(path) {
            function openDisk(n) {
                n = Number(n) || 0
                // Miss (0) must not become 1 page: that hides Prev/Next
                // and "Page X of Y". Wait for the sidecar count marker.
                if (n < 1)
                    return
                holdLoading = false
                var stub = "%PDF-1.4\n"
                var i
                for (i = 0; i < n; i++) stub += "/Type/Page\n"
                lastFetchFrom = "hold"
                fetchProgress = 1
                log("fetch disk cid=" + work.cid + " path=" + path + " pages=" + n)
                keepLastShare(work.cid, stub, path, isMine(work))
                dropJob()
                openFromHold(work, stub)
                next()
            }
            holdLoading = true
            if (files && typeof files.readPageCount === "function")
                files.readPageCount(work.cid, path, openDisk)
            else {
                holdLoading = false
                openDisk(1)
            }
        }

        function beginStorage() {
            if (!openingWork || openingWork.cid !== work.cid) return
            log("open start cid=" + work.cid + " downloadToUrl")
            retrieveFromStorage(work)
        }

        function considerPath(path) {
            if (!path || path.charAt(0) !== "/") {
                beginStorage()
                return
            }
            if (!files || typeof files.probe !== "function") {
                beginDisk(path)
                return
            }
            files.probe(path, function (n) {
                if (!openingWork || openingWork.cid !== work.cid) return
                if (n > 1000)
                    beginDisk(path)
                else {
                    log("open miss local cid=" + work.cid + " path=" + path + " n=" + n)
                    beginStorage()
                }
            })
        }

        var filled = filledWork(work)
        var disk = ""
        if (isMine(work)) {
            disk = cardHold(filled) || cardSource(filled) || ""
            if (!disk && files && typeof files.holdPath === "function")
                disk = files.holdPath(work.cid)
        }
        if (disk)
            considerPath(disk)
        else
            beginStorage()
    }

    function openHoldOrFail(work) {
        var want = work && work.size > 0 ? work.size : 0
        if (!isMine(work) || !files || typeof files.loadHold !== "function") {
            fetchFailed(work, isMine(work) ? Catalog.CHOOSE_AGAIN
                        : "Logos Storage could not find it.")
            return
        }
        files.loadHold(work.cid, want, function (bytes) {
            if (Catalog.shareHit(bytes, want, work.filename)) {
                lastFetchFrom = "hold"
                log("fetch hold cid=" + work.cid + " bytes=" + bytes.length)
                lastLocalMiss = ""
                openFromHold(work, bytes)
                return
            }
            fetchFailed(work, Catalog.CHOOSE_AGAIN)
        }, function (p) {
            if (p > fetchProgress && p < 1) fetchProgress = p
        })
    }

    function openTimedOut() {
        var work = openingWork
        if (!work) return
        log("open timeout cid=" + work.cid)
        if (holdLoading) return
        if (job && job.work && job.work.cid === work.cid) return
        fetchFailed(work, isMine(work) ? Catalog.CHOOSE_AGAIN
                    : "Logos Storage did not answer in time.")
    }

    function readLocal(work, want, done, onProgress) {
        if (typeof done !== "function") return
        var cached = lastShareOf(work.cid)
        if (Catalog.shareHit(cached, want, work.filename)) {
            lastFetchFrom = "lastShare"
            log("fetch lastShare cid=" + work.cid + " bytes=" + cached.length)
            done(cached)
            return
        }
        cached = heldShared(work.cid, want, work.filename)
        if (cached) {
            lastFetchFrom = "ram"
            log("fetch ram cid=" + work.cid + " bytes=" + cached.length)
            done(cached)
            return
        }
        function tryRam() {
            cached = heldShared(work.cid, want, work.filename)
            if (cached) {
                lastFetchFrom = "ram"
                log("fetch ram cid=" + work.cid + " bytes=" + cached.length)
                done(cached)
                return
            }
            var mem = "memory:" + work.cid
            var n = files && typeof files.fileSize === "function" ? files.fileSize(mem) : -1
            if (n > 0 && (want <= 0 || n >= want) && files && typeof files.readPiece === "function") {
                files.readPiece(mem, 0, n, function (bytes) {
                    if (Catalog.shareHit(bytes, want, work.filename)) {
                        lastFetchFrom = "memory"
                        log("fetch memory cid=" + work.cid + " bytes=" + bytes.length)
                        holdShared(work.cid, bytes, true)
                        done(bytes)
                        return
                    }
                    done("")
                })
                return
            }
            done("")
        }
        function trySource() {
            var path = cardSource(work)
            if (!path || !files || typeof files.readAll !== "function") {
                tryRam()
                return
            }
            files.readAll(path, want, onProgress, function (bytes) {
                if (Catalog.shareHit(bytes, want, work.filename)
                        || Catalog.shareHit(bytes, bytes.length, work.filename)) {
                    lastFetchFrom = "source"
                    log("fetch source cid=" + work.cid + " bytes=" + bytes.length)
                    lastLocalMiss = ""
                    keepLastShare(work.cid, bytes)
                    holdShared(work.cid, bytes, true)
                    done(bytes)
                    return
                }
                tryRam()
            })
        }
        if (files && typeof files.loadHold === "function") {
            files.loadHold(work.cid, want, function (bytes) {
                if (Catalog.shareHit(bytes, want, work.filename)) {
                    lastFetchFrom = "hold"
                    log("fetch hold cid=" + work.cid + " bytes=" + bytes.length)
                    lastLocalMiss = ""
                    holdShared(work.cid, bytes, true)
                    done(bytes)
                    return
                }
                trySource()
            }, onProgress)
            return
        }
        trySource()
    }

    function takeBytes(work, done, onProgress) {
        if (typeof done !== "function") return
        var want = work && work.size > 0 ? work.size : 0
        if (!work || !work.cid) {
            done("")
            return
        }
        var cached = viewBytes(work)
        if (cached) {
            lastFetchFrom = "lastShare"
            if (typeof onProgress === "function") onProgress(1)
            done(cached)
            return
        }
        if (!files) {
            done("")
            return
        }
        function fromDest() {
            destFor(work, function (dest) {
                if (!dest || !files || typeof files.readAll !== "function") {
                    done("")
                    return
                }
                files.readAll(dest, want, onProgress, function (bytes) {
                    if (Catalog.shareHit(bytes, want, work.filename)) {
                        lastFetchFrom = "downloadToUrl"
                        done(bytes)
                        return
                    }
                    done("")
                })
            })
        }
        function fromQml() {
            var path = cardSource(filledWork(work))
            if (!path || typeof files.readAll !== "function") {
                fromDest()
                return
            }
            files.readAll(path, want, onProgress, function (bytes) {
                if (Catalog.shareHit(bytes, want, work.filename)) {
                    lastFetchFrom = "source"
                    done(bytes)
                    return
                }
                fromDest()
            })
        }
        function fromSource() {
            if (typeof files.loadSource !== "function") {
                fromQml()
                return
            }
            files.loadSource(work.cid, want, function (bytes) {
                if (Catalog.shareHit(bytes, want, work.filename)) {
                    lastFetchFrom = "source"
                    done(bytes)
                    return
                }
                fromQml()
            }, onProgress)
        }
        if (typeof files.loadHold !== "function") {
            fromSource()
            return
        }
        files.loadHold(work.cid, want, function (bytes) {
            if (Catalog.shareHit(bytes, want, work.filename)) {
                lastFetchFrom = "hold"
                done(bytes)
                return
            }
            fromSource()
        }, onProgress)
    }

    function saveCopy(work, dir) {
        var folder = Catalog.pathOf(dir)
        if (!folder || folder.charAt(0) !== "/" || Catalog.isGlobalTmp(folder)) {
            saveFailed(work, "Choose a folder on this computer.")
            return
        }
        if (folder.length > 1 && folder.charAt(folder.length - 1) === "/")
            folder = folder.substring(0, folder.length - 1)
        var dest = folder + "/" + Catalog.saveName(work)
        saveBusy = true
        saveProgress = 0.03
        function fail(why) {
            saveAfter = null
            saveBusy = false
            saveProgress = 0
            saveFailed(work, why)
        }
        function finishOk() {
            saveBusy = false
            saveProgress = 1
            saveReady(work, dest)
        }
        function write(bytes) {
            if (!files || typeof files.writeAll !== "function") {
                fail("Could not write the file.")
                return
            }
            files.ensureDir(dest, function () {
                files.writeAll(dest, bytes, function (ok) {
                    if (ok) {
                        finishOk()
                        return
                    }
                    if (typeof files.putFile === "function") {
                        files.putFile(dest, bytes, function (put) {
                            if (put) finishOk()
                            else openHoldInstead("Could not write the file.")
                        })
                        return
                    }
                    openHoldInstead("Could not write the file.")
                }, function (p) { saveProgress = p })
            })
        }
        function openHoldInstead(why) {
            takeBytes(work, function (bytes) {
                if (Catalog.shareHit(bytes, work && work.size > 0 ? work.size : 0, work.filename)) {
                    saveBusy = false
                    saveProgress = 1
                    openFromHold(work, bytes)
                    saveFailed(work, why)
                    return
                }
                fail(why)
            })
        }
        function copyPath(path, next) {
            if (!path || !files || typeof files.copyFile !== "function") {
                next()
                return
            }
            files.copyFile(path, dest, function (ok) {
                if (!ok) {
                    next()
                    return
                }
                var n = files.fileSize(dest)
                var want = work && work.size > 0 ? work.size : 0
                if (want > 0 && !(n >= want)) {
                    next()
                    return
                }
                finishOk()
            })
        }
        function fromDest() {
            destFor(work, function (stored) {
                copyPath(stored, function () {
                    takeBytes(work, function (bytes) {
                        if (Catalog.shareHit(bytes, work && work.size > 0 ? work.size : 0, work.filename)) {
                            write(bytes)
                            return
                        }
                        openHoldInstead(Catalog.CHOOSE_AGAIN)
                    }, function (p) { saveProgress = Math.min(0.45, p * 0.45) })
                })
            })
        }
        function fromSource() {
            if (!files || typeof files.caller !== "function") {
                fromDest()
                return
            }
            files.caller("parallel_shelf_core", "readSource", [work.cid], function (r) {
                copyPath(Catalog.pathOf(r && r.value), fromDest)
            })
        }
        if (files && typeof files.caller === "function") {
            files.caller("parallel_shelf_core", "readHold", [work.cid], function (r) {
                copyPath(Catalog.pathOf(r && r.value), fromSource)
            })
            return
        }
        fromSource()
    }

    function openFromDest(work, dest) {
        dest = Catalog.safeSource(dest)
        if (!work || !dest || dest.charAt(0) !== "/") {
            fetchFailed(work, Catalog.CHOOSE_AGAIN)
            return
        }
        function openDisk(n) {
            n = Number(n) || 0
            if (n < 1)
                return
            holdLoading = false
            var stub = "%PDF-1.4\n"
            var i
            for (i = 0; i < n; i++) stub += "/Type/Page\n"
            lastFetchFrom = "downloadToUrl"
            fetchProgress = 1
            log("fetch disk cid=" + work.cid + " path=" + dest + " pages=" + n)
            keepLastShare(work.cid, stub, dest, isMine(work))
            dropJob()
            openFromHold(work, stub)
        }
        holdLoading = true
        openingWork = work
        openWatch.restart()
        if (files && typeof files.readPageCount === "function")
            files.readPageCount(work.cid, dest, openDisk)
        else {
            holdLoading = false
            openDisk(1)
        }
    }

    function fetchFromStorage(work, dest) {
        if (!dest || dest.charAt(0) !== "/" || Catalog.isGlobalTmp(dest)) {
            openHoldOrFail(work)
            return
        }
        // Do not wait on hung QtRO mkdir. downloadToUrl writes the dest
        // file; the sidecar rasters from that path.
        if (files && typeof files.ensureDir === "function") {
            try { files.ensureDir(dest, function () {}) } catch (e) {}
        }
        queueMusterFetch(work, dest)
    }

    function queueMusterFetch(work, dest) {
        var isText = Catalog.isText(work.filename)
        var wanted = {
            cid: work.cid, kind: isText ? "text" : "file", work: work, path: dest,
            local: false,
            limit: isText ? Catalog.TEXT_BYTES_MAX : Catalog.FILE_BYTES_MAX
        }
        queue = [wanted].concat(queue)
        next()
    }

    function queueFetch(work, path) {
        var isText = Catalog.isText(work.filename)
        var wanted = {
            cid: work.cid, kind: isText ? "text" : "file", work: work, path: path,
            local: false,
            limit: isText ? Catalog.TEXT_BYTES_MAX : Catalog.FILE_BYTES_MAX
        }
        queue = [wanted].concat(queue)
        next()
    }

    // Open of a dest file is downloadChunks + core writePiece. exists
    // is not called. "Context already initialized" is success on every
    // Storage method. "no answer" must not look like still-running.
    function stillGoing(answer) {
        if (!answer || answer.ok) return true
        if (Catalog.storageNoise(answer, answer.error)) return true
        var e = String(answer.error || "").toLowerCase()
        return e === "" || e === "no answer" || e.indexOf("timeout") >= 0
    }

    function openIfDestReady(started, notYet) {
        if (fetchedEnough()) {
            finishJob(true, "")
            return
        }
        if (!started.path || !files || typeof files.stat !== "function") {
            notYet()
            return
        }
        files.stat(started.path, function (n) {
            if (job !== started) return
            var want = jobWant || (started.work && started.work.size > 0 ? started.work.size : 0)
            if (n > 0 && (want <= 0 || n >= want)) {
                if (destPdfReady(n)) {
                    finishJob(true, "")
                    return
                }
                readDestIntoJob(started, n, notYet)
            } else notYet()
        })
    }

    function readDestIntoJob(started, n, notYet) {
        if (!files || typeof files.readAll !== "function") {
            if (typeof notYet === "function") notYet()
            return
        }
        files.readAll(started.path, n, function (p) {
            if (p > fetchProgress && p < 1) fetchProgress = p
        }, function (held) {
            if (job !== started) return
            if (held && held.length) {
                jobBytes = held
                if (fetchedEnough()) {
                    lastFetchFrom = "downloadToUrl"
                    finishJob(true, "")
                    return
                }
            }
            if (typeof notYet === "function") notYet()
        })
    }

    function next() {
        if (storageState !== "running" || job) return
        if (!queue.length) {
            shelfSettled()
            return
        }
        var started = queue[0]
        queue = queue.slice(1)
        job = started
        jobBytes = ""
        jobWant = (started.work && started.work.size > 0) ? started.work.size : 0
        jobSeen = 0
        fetchProgress = 0
        started.asked = false
        if (started.local === undefined)
            started.local = started.kind === "file" || started.kind === "text"
        lastCallError = ""
        jobWatch.interval = fileJobTimeout(started)
        jobWatch.restart()
        if (started.path) jobPoll.start()
        else jobPoll.stop()
        log("fetch " + started.kind + " cid=" + started.cid
            + (started.path ? (" path=" + started.path) : "")
            + (started.kind === "catalog" ? " downloadChunks" : " downloadToUrl"))
        startDownload(started)
    }

    function fileJobTimeout(started) {
        var base = 60000
        var want = jobWant || (started.work && started.work.size > 0 ? started.work.size : 0)
        if (want > 0)
            return Math.min(600000, Math.max(base, Math.floor(want / 40000) * 1000))
        return base
    }

    function startDownload(started) {
        if (job !== started || started.asked) return
        if (started.kind === "catalog") {
            started.asked = true
            started.local = false
            log("fetch catalog cid=" + started.cid + " downloadChunks")
            call("storage_module", "downloadChunks",
                 [started.cid, false, Catalog.BLOCK, false, false], function (accepted) {
                if (job !== started) return
                if (accepted && accepted.ok) return
                if (lastStorageNoise || Catalog.storageNoise(accepted, accepted && accepted.error))
                    return
                if (stillGoing(accepted)) return
                finishJob(false, (accepted && accepted.error) || "The catalog could not be read.")
            }, 60000)
            return
        }
        if (!started.path || started.path.charAt(0) !== "/" || Catalog.isGlobalTmp(started.path)) {
            openHoldThenFinish(started, "no dest")
            return
        }
        started.asked = true
        function asked(accepted) {
            if (job !== started) return
            if (accepted && accepted.ok) {
                finishJob(true, "")
                return
            }
            openIfDestReady(started, function () {
                if (job !== started) return
                if (lastStorageNoise || Catalog.storageNoise(accepted, accepted && accepted.error))
                    return
                if (stillGoing(accepted)) return
                openHoldThenFinish(started, lastCallError || (accepted && accepted.error)
                                   || "Logos Storage could not find it.")
            })
        }
        log("fetch downloadToUrl local=false " + started.path)
        call("storage_module", "downloadToUrl",
             [started.cid, started.path, false, Catalog.BLOCK, false, false], asked, 60000)
    }

    function openHoldThenFinish(started, why) {
        if (!started || job !== started) return
        if (started.kind === "catalog") {
            finishJob(false, why || "The catalog could not be read.")
            return
        }
        var miss = readerWhy(why) || "Logos Storage could not find it."
        if (started.triedHold) {
            finishJob(false, isMine(started.work) ? Catalog.CHOOSE_AGAIN : miss)
            return
        }
        started.triedHold = true
        var work = started.work
        if (!isMine(work) || !work || !files || typeof files.loadHold !== "function") {
            finishJob(false, isMine(work) ? Catalog.CHOOSE_AGAIN : miss)
            return
        }
        var want = work.size > 0 ? work.size : 0
        files.loadHold(work.cid, want, function (bytes) {
            if (job !== started) return
            if (Catalog.shareHit(bytes, want, work.filename)) {
                lastFetchFrom = "hold"
                log("fetch hold cid=" + work.cid + " bytes=" + bytes.length)
                jobBytes = bytes
                finishJob(true, "")
                return
            }
            finishJob(false, Catalog.CHOOSE_AGAIN)
        }, function (p) {
            if (p > fetchProgress && p < 1) fetchProgress = p
        })
    }

    function onManifest(p) {
        if (!job || (p.cid && p.cid !== job.cid)) return
        if (p.success === false) {
            if (Catalog.alreadyInitialized(p.error)) return
            finishJob(false, p.error || "The description of this file could not be found.")
            return
        }
        if (p.manifest && p.manifest.datasetSize > 0)
            jobWant = p.manifest.datasetSize
        startDownload(job)
    }

    function pollJob() {
        if (!job || !job.path || !files || typeof files.stat !== "function") return
        if (fetchedEnough()) {
            finishJob(true, "")
            return
        }
        var started = job
        var want = jobWant
        files.stat(started.path, function (n) {
            if (job !== started) return
            if (n > jobSeen) {
                jobSeen = n
                jobWatch.restart()
            }
            if (want > 0 && n > 0) fetchProgress = n / want
            if (fetchedEnough()) {
                finishJob(true, "")
                return
            }
            if (n > 0 && (want <= 0 || n >= want)) {
                if (destPdfReady(n)) {
                    finishJob(true, "")
                    return
                }
                readDestIntoJob(started, n, function () {})
            }
        })
    }

    function jobProgress(p) {
        if (!job || (p.sessionId && p.sessionId !== job.cid)) return
        if (p.success === false) {
            if (!fetchedEnough()) retryWithoutLocal(job)
            return
        }
        jobWatch.restart()
        var size = 0
        if (p.chunk) {
            var piece = Catalog.b64decode(p.chunk)
            var at = jobBytes.length
            jobBytes += piece
            size = jobBytes.length
            var dest = job.path ? job.path : ("memory:" + job.cid)
            if (files && typeof files.writePiece === "function" && piece.length)
                files.writePiece(dest, at, piece, function () {})
            if (jobWant > 0) fetchProgress = Math.min(1, size / jobWant)
            if (size > jobSeen) jobSeen = size
            if (fetchedEnough()) {
                finishJob(true, "")
                return
            }
        } else if (p.bytes || p.total) {
            size = p.total > 0 ? p.total : 0
            if (size) fetchProgress = p.bytes / size
            if (p.bytes > jobSeen) jobSeen = p.bytes
            if (p.total > jobWant) jobWant = p.total
        }
        if (!job) return
        if (size > job.limit)
            finishJob(false, "It is larger than Parallel Shelf will open.")
    }

    // Reverse of Share's sendFilePart: size from manifests(), pieces into
    // jobBytes / memory:<cid>. downloadChunks may already be streaming;
    // this fills jobWant so Open can finish without downloadCancel.
    function pullPieces(started) {
        if (!started || started.kind === "catalog" || started.pulled) return
        started.pulled = true
        call("storage_module", "manifests", [], function (listed) {
            if (job !== started) return
            var found = Catalog.listedCids(listed && listed.value)
            var size = started.work && started.work.size > 0 ? started.work.size : 0
            var i
            for (i = 0; i < found.length; i++) {
                if (found[i].cid === started.cid && found[i].size > 0)
                    size = found[i].size
            }
            if (size > 0) jobWant = size
            if (fetchedEnough()) finishJob(true, "")
        })
    }

    function jobTimedOut() {
        if (!job) return
        var started = job
        if (fetchedEnough()) {
            finishJob(true, "")
            return
        }
        if (jobBytes.length > jobSeen) {
            jobSeen = jobBytes.length
            jobWatch.restart()
            return
        }
        if (jobBytes.length > 0 && Catalog.isPdf(jobBytes)) {
            finishJob(true, "")
            return
        }
        if (started.path && files && typeof files.stat === "function") {
            files.stat(started.path, function (n) {
                if (job !== started) return
                if (n > 0 && (jobWant <= 0 || n >= jobWant)) {
                    if (destPdfReady(n)) {
                        finishJob(true, "")
                        return
                    }
                    readDestIntoJob(started, n, function () {
                        if (job !== started) return
                        openHoldThenFinish(started, lastCallError || "Logos Storage could not find it.")
                    })
                    return
                }
                openHoldThenFinish(started, lastCallError || "Logos Storage could not find it.")
            })
            return
        }
        openHoldThenFinish(started, lastCallError || "Logos Storage could not find it.")
    }

    function finishJob(ok, why) {
        if (!job) return
        if (!ok && job.kind !== "catalog" && !job.triedHold) {
            openHoldThenFinish(job, why)
            return
        }
        var done = job
        var bytes = jobBytes
        job = null
        jobBytes = ""
        jobWant = 0
        jobSeen = 0
        jobWatch.stop()
        jobPoll.stop()
        jobGrace.stop()

        if (done.kind === "catalog") {
            var listed = ok ? Catalog.readCatalog(Catalog.utf8decode(bytes)) : null
            if (listed)
                applyCatalogList(listed, done.cid, done.deliveredAt)
            else {
                log("catalog " + done.cid + " could not be read: " + (why || "empty"))
                if (done.cid)
                    delete fetchedCatalogs[done.cid]
            }
        } else if (ok && done.path && done.work && Catalog.extensionOf(done.work.filename) === "pdf") {
            openFromDest(done.work, done.path)
            next()
            return
        } else if (!ok) {
            if (saveAfter && saveAfter.work && done.work && saveAfter.work.id === done.work.id) {
                var saveWhy = Catalog.alreadyInitialized(why) ? "Logos Storage could not find it."
                    : (readerWhy(why) || "Logos Storage could not find it.")
                saveAfter = null
                saveBusy = false
                saveProgress = 0
                saveFailed(done.work, saveWhy)
            } else {
                fetchFailed(done.work, Catalog.alreadyInitialized(why) ? "Logos Storage could not find it."
                    : (readerWhy(why) || "Logos Storage could not find it."))
            }
        } else if (saveAfter && saveAfter.work && done.work && saveAfter.work.id === done.work.id) {
            var dest = saveAfter.dest
            saveAfter = null
            if (!bytes.length || (Catalog.extensionOf(done.work.filename) === "pdf" && !Catalog.isPdf(bytes))) {
                saveBusy = false
                saveProgress = 0
                saveFailed(done.work, "Logos Storage returned an empty file.")
            } else if (files && typeof files.writeAll === "function") {
                files.writeAll(dest, bytes, function (wrote) {
                    saveBusy = false
                    saveProgress = wrote ? 1 : 0
                    if (wrote) saveReady(done.work, dest)
                    else saveFailed(done.work, "Could not write the file.")
                    next()
                }, function (p) { saveProgress = 0.5 + p * 0.5 })
                return
            } else {
                saveBusy = false
                saveProgress = 0
                saveFailed(done.work, "Could not write the file.")
            }
        } else if (done.kind === "text") {
            if (!bytes.length) {
                fetchFailed(done.work, "Logos Storage returned an empty file.")
            } else {
                textReady(done.work, Catalog.utf8decode(bytes))
            }
        } else if (bytes.length && (Catalog.extensionOf(done.work && done.work.filename) !== "pdf"
                || Catalog.isPdf(bytes))) {
            holdShared(done.work.cid, bytes)
            if (!lastFetchFrom)
                lastFetchFrom = done.path ? "downloadToUrl" : "hold"
            bytesReady(done.work, bytes)
            if (done.path) fileReady(done.work, done.path)
        } else {
            fetchFailed(done.work, "Logos Storage returned an empty file.")
        }
        next()
    }

    function saveFetchedBytes(done, bytes) {
        function opened() {
            bytesReady(done.work, bytes)
            next()
        }
        if (!done.path || !files || typeof files.writeAll !== "function") {
            opened()
            return
        }
        files.writeAll(done.path, bytes, function (ok) {
            if (ok) fileReady(done.work, done.path)
            opened()
        })
    }

    function confirmFetchedFile(done) {
        if (!files || typeof files.stat !== "function") {
            fileReady(done.work, done.path)
            next()
            return
        }
        files.stat(done.path, function (n) {
            var want = done.work && done.work.size > 0 ? done.work.size : 0
            if (n > 0 && (want <= 0 || n >= want))
                fileReady(done.work, done.path)
            else
                fetchFailed(done.work, "Logos Storage could not find it.")
            next()
        })
    }

    function shelfSettled() {
        if (works.length > largestCatalog && !catalogBusy && !republish.running && catalogFailures < 5) {
            republish.interval = 2000 + Math.floor(Math.random() * 4000)
            republish.start()
        }
    }

    // ---- Adding a work ----------------------------------------------------

    function share(title, author, source) {
        if (sharing) return
        var path = Catalog.pathOf(source)
        var filename = Catalog.fileNameOf(source)
        var problem = ""
        if (!Catalog.cleanText(title, Catalog.TITLE_MAX)) problem = "Give it a title."
        else if (!path) problem = "Choose a file."
        else if (path.charAt(0) !== "/") problem = "Use the full path to the file, starting with /."
        else if (!Catalog.kindOf(filename)) problem = "That file type is not supported. Use txt, md, pdf, mp3, m4a or ogg."
        else if (works.length >= Catalog.WORKS_MAX) problem = "The shelf is full."
        else if (storageState === "starting") problem = "Logos Storage is still starting. Try again in a moment."
        else if (storageState !== "running") problem = "Logos Storage is not running, so nothing can be added."
        if (problem) {
            shareFailed(problem)
            return
        }

        draft = { title: Catalog.cleanText(title, Catalog.TITLE_MAX), author: author, filename: filename, size: 0 }
        sharing = true
        shareProgress = 0.03
        fileSession = ""
        fileSource = path
        fileDisk = path
        filePending = "share-" + Catalog.newId()
        fileAt = 0
        fileLen = 0
        fileChunk = Catalog.IPC_PIECE
        fileGen = 0
        fileHold = ""
        fileParts = []
        fileDone = false
        pendingShareBytes = ""

        function shareUsable(staged) {
            return staged && staged.charAt(0) === "/" && !Catalog.isGlobalTmp(staged)
                    && staged.indexOf("/Downloads/") < 0
        }

        function stashFrom(from, n, then) {
            if (!from || !files || typeof files.readAll !== "function") {
                then()
                return
            }
            files.readAll(from, n, function (p) {
                if (p > shareProgress && p < 0.45)
                    shareProgress = Math.min(0.45, 0.05 + p * 0.4)
            }, function (bytes) {
                if (Catalog.shareHit(bytes, n, filename))
                    pendingShareBytes = bytes
                then()
            })
        }

        function shareUpload(disk) {
            if (!sharing) return
            function begin(n) {
                if (!sharing) return
                if (!(n > 0)) {
                    failShare("File not found: " + path)
                    return
                }
                fileDisk = disk
                filePending = disk
                fileLen = n
                draft.size = n
                shareProgress = 0.05
                function go() {
                    startUploadUrl(disk)
                }
                stashFrom(disk, n, function () {
                    if (pendingShareBytes.length || disk === path) {
                        go()
                        return
                    }
                    stashFrom(path, n, go)
                })
            }
            var n = files && typeof files.fileSize === "function" ? files.fileSize(disk) : 0
            if (n > 0) begin(n)
            else if (files && typeof files.stat === "function") files.stat(disk, begin)
            else begin(0)
        }

        if (files && typeof files.stageShare === "function") {
            files.stageShare(path, function (staged) {
                shareUpload(shareUsable(staged) ? staged : path)
            })
            return
        }
        shareUpload(path)
    }

    function startUploadUrl(staged) {
        pendingUpload = null
        call("storage_module", "uploadUrl", [staged, Catalog.BLOCK, true], function (opened) {
            if (!sharing) return
            if (!opened.ok || !opened.value) {
                failShare(opened.error || "Logos Storage did not open an upload.")
                return
            }
            fileSession = String(opened.value)
            if (pendingUpload && pendingUpload.sessionId === fileSession) {
                var p = pendingUpload
                pendingUpload = null
                onFileUploadDone(p)
            }
        }, 60000)
    }

    function onFileUploadDone(p) {
        if (!sharing || fileDone) return
        if (p.success === false || !p.cid) {
            failShare(p.error || "The upload failed.")
            return
        }
        fileUploaded({ success: true, cid: String(p.cid), size: fileLen || (draft ? draft.size : 0) })
    }

    function fileProgress(p) {
        if (p.success === false) {
            failShare(p.error || "The upload failed.")
            return
        }
        var total = fileLen || (draft ? draft.size : p.total)
        if (total > 0) {
            var next = Math.min(1, p.bytes / total)
            if (next > shareProgress) shareProgress = next
        }
    }

    function fileUploaded(p) {
        if (!sharing || !draft || fileDone) return
        if (p.success === false || !p.cid) {
            failShare(p.error || "The upload failed.")
            return
        }
        fileDone = true
        fileSession = ""
        shareProgress = 1
        if (p.size) draft.size = p.size
        var cid = Catalog.cleanText(String(p.cid), 200)
        ownCid(cid)
        var staged = fileDisk
        var source = fileSource || staged
        function stagedUsable(path) {
            return path && path.charAt(0) === "/" && !Catalog.isGlobalTmp(path)
                    && path.indexOf("/Downloads/") < 0
        }
        function keepView(bytes) {
            if (Catalog.shareHit(bytes, draft.size, draft.filename))
                keepLastShare(cid, bytes, stagedUsable(staged) ? staged : "")
        }
        function putCard() {
            works = Catalog.keepShare(works, {
                id: Catalog.newId(),
                title: draft.title,
                author: draft.author,
                filename: draft.filename,
                cid: cid,
                size: draft.size,
                addedAt: Date.now(),
                mine: true
            })
            persistShelf()
            publishCatalog()
        }
        function afterHold(ok, holdPath) {
            if (ok) rememberHold(cid, holdPath)
            rememberCard(cid, source, ok ? holdPath : "")
            putCard()
        }
        function afterView() {
            keepView(pendingShareBytes)
            bindStaged()
        }
        function bindStaged() {
            function go() {
            if (stagedUsable(staged) && files && typeof files.bindHold === "function") {
                files.bindHold(cid, staged, afterHold)
                return
            }
            if (!files || typeof files.caller !== "function") {
                afterHold(false, "")
                return
            }
            files.caller("parallel_shelf_core", "holdFile", [cid], function (r) {
                var holdPath = Catalog.pathOf(r && r.value)
                if (!holdPath || holdPath.charAt(0) !== "/" || Catalog.isGlobalTmp(holdPath)
                        || holdPath.indexOf("/Downloads/") >= 0) {
                    afterHold(false, "")
                    return
                }
                files.ensureDir(holdPath, function () {
                    call("storage_module", "downloadToUrl",
                         [cid, holdPath, false, Catalog.BLOCK, false, false], function () {
                        function waitReady(left) {
                            files.probe(holdPath, function (n) {
                                if (n > 0) {
                                    files.bindHold(cid, holdPath, afterHold)
                                    return
                                }
                                if (left <= 0) {
                                    afterHold(false, "")
                                    return
                                }
                                Qt.callLater(function () { waitReady(left - 1) })
                            })
                        }
                        waitReady(50)
                    })
                })
            })
            }
            if (files && typeof files.rememberSource === "function" && source) {
                files.rememberSource(cid, source, go)
                return
            }
            go()
        }
        if (Catalog.shareHit(pendingShareBytes, draft.size, draft.filename)) {
            afterView()
            return
        }
        pullShareIntoView(cid, draft.size, function (bytes) {
            if (Catalog.shareHit(bytes, draft.size, draft.filename))
                pendingShareBytes = bytes
            afterView()
        })
    }

    function finishSharePull(bytes) {
        var cb = sharePullFinish
        sharePullCid = ""
        sharePullBytes = ""
        sharePullFinish = null
        if (typeof cb === "function") cb(bytes || "")
    }

    function pullShareIntoView(cid, want, done) {
        if (typeof done !== "function") return
        cid = Catalog.cleanText(cid, 200)
        if (!cid) {
            done("")
            return
        }
        sharePullCid = cid
        sharePullBytes = ""
        sharePullFinish = done
        call("storage_module", "downloadChunks",
             [cid, false, Catalog.BLOCK, false, false], function () {})
    }

    function cancelShare() {
        if (fileSession) call("storage_module", "uploadCancel", [fileSession], function () {})
        endShare()
    }

    function failShare(why) {
        if (!sharing) return
        endShare()
        shareFailed(why)
    }

    function endShare() {
        sharing = false
        fileSession = ""
        fileDisk = ""
        fileSource = ""
        filePending = ""
        fileAt = 0
        fileLen = 0
        fileGen = 0
        fileHold = ""
        fileParts = []
        pendingUpload = null
        draft = null
        fileDone = false
        pendingShareBytes = ""
        sharePullCid = ""
        sharePullBytes = ""
        sharePullFinish = null
    }

    function publishCatalog() {
        if (storageState !== "running" || !works.length) return
        if (catalogBusy) {
            catalogStale = true
            return
        }
        catalogBusy = true
        catalogStale = false
        catalogCount = works.length
        catalogParts = Catalog.split(Catalog.catalogDocument(works), 60000)
        catalogPart = 0
        catalogGen = 0
        call("storage_module", "uploadInit", ["parallel-shelf.json", Catalog.BLOCK, true], function (opened) {
            if (!opened.ok || !opened.value) {
                catalogFailed(opened.error || "Logos Storage did not open an upload.")
                return
            }
            catalogSession = String(opened.value)
            sendCatalogPart()
        }, 60000)
    }

    function sendCatalogPart() {
        if (!catalogBusy || catalogPart >= catalogParts.length) return
        var gen = ++catalogGen
        call("storage_module", "uploadChunk", [catalogSession, catalogParts[catalogPart]], function (sent) {
            if (gen !== catalogGen || !catalogBusy) return
            if (!sent.ok) {
                catalogFailed(sent.error)
                return
            }
            commitCatalogPart(gen)
        }, 60000)
    }

    function catalogProgress(p) {
        if (p.success === false) {
            catalogFailed(p.error || "A piece of the catalog did not upload.")
            return
        }
    }

    function commitCatalogPart(gen) {
        if (gen !== catalogGen || !catalogBusy) return
        catalogGen++
        catalogPart++
        if (catalogPart < catalogParts.length) sendCatalogPart()
        else finalizeCatalog()
    }

    function finalizeCatalog() {
        var session = catalogSession
        catalogSession = ""
        call("storage_module", "uploadFinalize", [session], function (finished) {
            if (!catalogBusy) return
            if (!finished.ok || !finished.value) {
                catalogFailed(finished.error || "Logos Storage did not return an address.")
                return
            }
            catalogPublished(String(finished.value))
        }, 60000)
    }

    function catalogPublished(cid) {
        catalogFailures = 0
        catalogBusy = false
        catalogGen = 0
        fetchedCatalogs[cid] = true
        largestCatalog = Math.max(largestCatalog, catalogCount)
        saved.catalog = cid
        unannounced = cid
        announce()
        if (sharing) {
            var title = draft.title
            endShare()
            shared(title, deliveryState === "running")
        }
        if (catalogStale) publishCatalog()
    }

    function catalogFailed(why) {
        if (!catalogBusy) return
        log("catalog upload: " + why)
        catalogFailures++
        catalogBusy = false
        catalogSession = ""
        catalogGen = 0
        if (sharing) {
            var title = draft.title
            endShare()
            shared(title, false)
        }
        next()
    }
}

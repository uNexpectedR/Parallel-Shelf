import QtQuick 2.15
import TestFileBytes 1.0
import "bytes.js" as Bytes

// Stands in for the `logos` object Basecamp hands an app, with Logos Storage
// and Logos Delivery behind it.
//
// It follows the published interfaces of logos-storage-module v3.0.2 and
// logos-delivery-module v0.3.3: the same methods, the same arguments, the
// same events. When the app calls one in a way the real module would not
// accept, that is recorded on the network as a mistake and the test fails.
Item {
    id: fake

    property var network
    property var app                          // the screen that receives events
    property bool storageInstalled: true
    property bool deliveryInstalled: true
    property bool resultBeforeAnswer: false   // events overtake the answer to the call
    property bool base64Messages: false       // message bodies arrive base64 encoded
    property bool uploadEvents: true          // Basecamp 0.3 sometimes drops these
    property bool downloadEvents: true        // one Basecamp build dropped Storage done events
    property bool existsAnswers: true         // exists can miss a CID that upload already stored
    property string existsError: ""           // real Storage error; Open must not call exists
    property string firstDownloadError: ""    // one-shot downloadToUrl error, then the real write
    property bool contextAlreadyInitialized: false  // Mac Storage 3.0.2: every retrieve method returns this
    property bool mkdirEmpty: false                 // Mac Offscreen: core mkdir("") returns empty
    property bool hostEventsViaReceived: false      // Mac ui_qml: events on moduleEventReceived
    property bool downloadDoneBeforeChunks: false   // Mac: storageDownloadDone overtakes chunks
    property bool downloadEmptyDone: false          // Done with no chunk events
    property bool writeDestFails: false             // dest file stays empty; Open uses jobBytes
    property bool localChunksMiss: false            // downloadChunks local=true misses; local=false hits
    property var held: ({})                         // core memory:<cid> buffer
    property var holdMap: ({})                      // core cid → holdPath, next to the hold
    property var sourceMap: ({})                    // core cid → Choose-file path
    property bool readPieceFails: false             // disk readPiece fails; Open must not hang
    property bool stageShareFails: false            // Mac: core cannot copy ~/Downloads
    property bool hangRenderPage: false             // Mac 0.41.0: renderPage never returns
    property var watchers: ({})

    signal moduleEventReceived(string moduleName, string eventName, var data)

    property var listening: ({})
    property var pending: []
    property bool storageCreated: false
    property bool storageRunning: false
    property bool deliveryRunning: false
    property var topics: []
    property var uploads: ({})
    property var cancelled: ({})
    property int sessions: 0
    property int downloads: 0

    signal viewModuleReadyChanged(string moduleName, bool isReady)

    property var calls: []
    property bool pickFileCalled: false
    property string firstFileChunk: ""

    Timer {
        interval: 2
        repeat: true
        running: fake.pending.length > 0
        onTriggered: {
            var step = fake.pending[0]
            fake.pending = fake.pending.slice(1)
            step()
        }
    }

    // ---- What Basecamp gives the app --------------------------------------

    function onModuleEvent(module, event) {
        listening[module + "." + event] = true
        return true
    }

    function watch(module, event, cb) {
        var key = module + "." + event
        listening[key] = true
        if (typeof cb === "function") {
            var list = fake.watchers[key] || []
            fake.watchers[key] = list.concat([cb])
        }
        return true
    }

    function callModuleAsync(module, method, args, callback, timeoutMs) {
        calls = calls.concat([{ module: module, method: method, args: args }])
        if (module === "parallel_shelf_core" && method === "renderPage" && fake.hangRenderPage)
            return
        var events = []
        var answer
        if (module === "parallel_shelf")
            answer = failed("view modules must be called via logos.module()")
        else if (module === "parallel_shelf_core") answer = shelfCore(method, args)
        else if (module === "storage_module" && storageInstalled) answer = storage(method, args, events)
        else if (module === "delivery_module" && deliveryInstalled) answer = delivery(method, args)
        else answer = failed("module not loaded: " + module)

        var steps = [function () { callback(JSON.stringify(answer)) }]
        steps = resultBeforeAnswer ? events.concat(steps) : steps.concat(events)
        pending = pending.concat(steps)
    }

    // ---- Helpers ----------------------------------------------------------

    function ok(value) {
        return { success: true, value: value === undefined ? null : value, error: "" }
    }

    function failed(why) {
        return { success: false, value: null, error: why }
    }

    function wrong(method, args, types) {
        var fine = args && args.length === types.length
        var i
        for (i = 0; fine && i < types.length; i++) fine = typeof args[i] === types[i]
        if (!fine) network.mistake(method + " takes (" + types.join(", ") + "), got " + JSON.stringify(args))
        return !fine
    }

    function emit(module, event, data) {
        var key = module + "." + event
        if (fake.hostEventsViaReceived) {
            moduleEventReceived(module, event, data)
            return
        }
        var cbs = fake.watchers[key]
        if (cbs && cbs.length) {
            var i
            for (i = 0; i < cbs.length; i++) cbs[i](data)
            return
        }
        if (listening[key]) app.onModuleEvent(module, event, data)
    }

    function storageEvent(event, payload) {
        emit("storage_module", event, [JSON.stringify(payload)])
    }

    // parallel_shelf_core: QFile in a Logos host process. This stand-in uses
    // the same QFile helper the core module ships (tests/TestFileBytes). The
    // view never imports that plugin; it only calls callModuleAsync.
    function shelfCore(method, args) {
        if (method === "snapshot") return ok('{"version":"0.1.0"}')
        if (method === "fetchDest") {
            if (wrong(method, args, ["string", "string"])) return failed("bad arguments")
            var dest = TestFileBytes.fetchDest(args[0], args[1])
            if (!dest) return failed("No writable dest.")
            return ok(dest)
        }
        if (method === "fileSize") {
            if (wrong(method, args, ["string"])) return failed("bad arguments")
            var path = String(args[0] || "")
            if (path.indexOf("memory:") === 0) {
                var held = String(fake.held[path] || "")
                if (!(held.length > 0)) return failed("File not found.")
                return ok(held.length)
            }
            var n = TestFileBytes.fileSize(args[0])
            if (!(n > 0)) return failed("File not found.")
            return ok(n)
        }
        if (method === "readPiece") {
            if (wrong(method, args, ["string", "number", "number"])) return failed("bad arguments")
            var from = String(args[0] || "")
            var piece
            if (from.indexOf("memory:") === 0) {
                piece = String(fake.held[from] || "").substring(args[1], args[1] + args[2])
            } else if (fake.readPieceFails) {
                return failed("Could not read the file.")
            } else {
                piece = TestFileBytes.readPiece(args[0], args[1], args[2])
            }
            if (!piece.length && args[2] > 0) return failed("Could not read the file.")
            if (!fake.firstFileChunk && piece.length)
                fake.firstFileChunk = piece.substring(0, 5)
            return ok(piece)
        }
        if (method === "writePiece") {
            if (wrong(method, args, ["string", "number", "string"])) return failed("bad arguments")
            var dest = String(args[0] || "")
            if (dest.indexOf("memory:") === 0) {
                var at = args[1]
                var chunk = String(args[2] || "")
                var cur = String(fake.held[dest] || "")
                if (at === 0) cur = chunk
                else cur = cur.substring(0, at) + chunk
                fake.held[dest] = cur
                return ok(at + chunk.length)
            }
            if (fake.writeDestFails)
                return failed("Could not write the file.")
            if (!TestFileBytes.writePiece(args[0], args[1], args[2]))
                return failed("Could not write the file.")
            return ok(args[1] + args[2].length)
        }
        if (method === "mkdir") {
            if (wrong(method, args, ["string"])) return failed("bad arguments")
            if (fake.mkdirEmpty) return ok("")
            var dir = TestFileBytes.mkdir(args[0])
            if (!dir || dir.charAt(0) !== "/")
                dir = TestFileBytes.mkdir(TestFileBytes.fetchDest("book", "pdf"))
            return ok(dir)
        }
        if (method === "holdFile") {
            if (wrong(method, args, ["string"])) return failed("bad arguments")
            var hold = TestFileBytes.holdFile(args[0])
            if (!hold || hold.charAt(0) !== "/") return failed("No hold path.")
            return ok(hold)
        }
        if (method === "writeHold") {
            if (wrong(method, args, ["string", "string"])) return failed("bad arguments")
            if (!TestFileBytes.writeHold(args[0], args[1]))
                return failed("Could not remember the hold.")
            var stored = TestFileBytes.readHold(args[0])
            if (!stored) stored = String(args[1] || TestFileBytes.holdFile(args[0]))
            fake.holdMap[args[0]] = stored
            return ok(stored)
        }
        if (method === "readHold") {
            if (wrong(method, args, ["string"])) return failed("bad arguments")
            var found = TestFileBytes.readHold(args[0])
            if (!found) found = fake.holdMap[args[0]] || ""
            if (!found) return failed("No hold.")
            return ok(found)
        }
        if (method === "rememberSource") {
            if (wrong(method, args, ["string", "string"])) return failed("bad arguments")
            if (!TestFileBytes.rememberSource(args[0], args[1]))
                return failed("Could not remember the source.")
            var remembered = TestFileBytes.readSource(args[0])
            if (!remembered) remembered = String(args[1] || "")
            fake.sourceMap[args[0]] = remembered
            return ok(remembered)
        }
        if (method === "readSource") {
            if (wrong(method, args, ["string"])) return failed("bad arguments")
            var source = TestFileBytes.readSource(args[0])
            if (!source) source = fake.sourceMap[args[0]] || ""
            if (!source) return failed("No source.")
            return ok(source)
        }
        if (method === "copyFile") {
            if (wrong(method, args, ["string", "string"])) return failed("bad arguments")
            if (fake.readPieceFails)
                return failed("Could not copy the file.")
            if (!TestFileBytes.copyFile(args[0], args[1]))
                return failed("Could not copy the file.")
            return ok(args[1])
        }
        if (method === "holdRead") {
            if (wrong(method, args, ["string", "number", "number", "string"]))
                return failed("bad arguments")
            var held
            if (fake.readPieceFails)
                return failed("Could not read the file.")
            held = TestFileBytes.holdRead(args[0], args[1], args[2], args[3])
            if (!held.length && args[2] > 0) return failed("Could not read the file.")
            if (!fake.firstFileChunk && held.length)
                fake.firstFileChunk = held.substring(0, 5)
            return ok(held)
        }
        if (method === "keepHold") {
            if (wrong(method, args, ["string", "string"])) return failed("bad arguments")
            var kept = TestFileBytes.keepHold(args[0], args[1])
            if (!kept || kept.charAt(0) !== "/") return failed("Could not keep the hold.")
            fake.holdMap[args[1]] = kept
            return ok(kept)
        }
        if (method === "stageShare") {
            if (wrong(method, args, ["string"])) return failed("bad arguments")
            if (fake.stageShareFails)
                return failed("Could not copy the file.")
            var staged = TestFileBytes.stageShare(args[0])
            if (!staged || staged.charAt(0) !== "/" || staged.indexOf("/Downloads/") >= 0)
                return failed("Could not copy the file.")
            return ok(staged)
        }
        if (method === "renderPage") {
            if (wrong(method, args, ["string", "number", "number", "string"])) return failed("bad arguments")
            var png = TestFileBytes.renderPage(args[0], args[1], args[2])
            if (!png || png.charAt(0) !== "/" || png.indexOf(".png") < 0
                    || png.indexOf("/Downloads/") >= 0)
                return failed("Could not draw this page.")
            var dest = String(args[3] || "")
            if (dest && dest.charAt(0) === "/" && dest.indexOf(".png") > 0
                    && dest.indexOf("/Downloads/") < 0) {
                if (!TestFileBytes.copyFile(png, dest))
                    return failed("Could not write this page into the view.")
                return ok(dest)
            }
            return ok(png)
        }
        network.mistake("parallel_shelf_core has no method " + method)
        return failed("no such method")
    }

    // ---- Logos Storage ----------------------------------------------------

    function storage(method, args, events) {
        if (method === "isRunning") {
            if (wrong(method, args, [])) return false
            return storageRunning
        }
        if (method === "loadConfigOrDefault") {
            if (wrong(method, args, [])) return failed("bad arguments")
            return ok('{"network":"logos.test","config-version":1}')
        }
        if (method === "init") {
            if (wrong(method, args, ["string"])) return false
            try {
                JSON.parse(args[0])
            } catch (e) {
                network.mistake("init needs JSON, got " + args[0])
                return false
            }
            if (storageCreated) {
                network.mistake("init called twice")
                return false
            }
            storageCreated = true
            return true
        }
        if (method === "start") {
            if (wrong(method, args, [])) return false
            if (!storageCreated) {
                network.mistake("start before init")
                return false
            }
            events.push(function () {
                storageRunning = true
                storageEvent("storageStart", { success: true, message: "" })
            })
            return true
        }

        if (!storageRunning) {
            network.mistake(method + " before the node is running")
            return failed("node is not running")
        }
        if (method === "uploadUrl") return uploadUrl(method, args, events)
        if (method === "manifests") {
            if (wrong(method, args, [])) return failed("bad arguments")
            return ok(JSON.stringify(listedManifests()))
        }
        if (method === "uploadInit") {
            if (wrong(method, args, ["string", "number", "boolean"])) return failed("bad arguments")
            var opened = "session-" + (++sessions)
            uploads[opened] = ""
            return ok(opened)
        }
        if (method === "uploadChunk") return uploadChunk(method, args, events)
        if (method === "uploadFinalize") {
            if (wrong(method, args, ["string"])) return failed("bad arguments")
            if (uploads[args[0]] === undefined) return failed("no such session")
            var cid = network.put(uploads[args[0]])
            delete uploads[args[0]]
            return ok(cid)
        }
        if (method === "uploadCancel" || method === "downloadCancel") {
            if (wrong(method, args, ["string"])) return failed("bad arguments")
            cancelled[args[0]] = true
            return ok()
        }
        if (method === "exists") {
            if (wrong(method, args, ["string"])) return failed("bad arguments")
            if (fake.contextAlreadyInitialized) return failed("Context already initialized")
            if (fake.existsError) return failed(fake.existsError)
            if (!fake.existsAnswers) return ok(false)
            return ok(network.files[args[0]] !== undefined)
        }
        if (method === "downloadManifest") {
            if (wrong(method, args, ["string", "boolean", "boolean"])) return failed("bad arguments")
            if (fake.contextAlreadyInitialized) return failed("Context already initialized")
            return downloadManifest(args[0], events)
        }
        if (method === "downloadChunks") {
            if (wrong(method, args, ["string", "boolean", "number", "boolean", "boolean"])) return failed("bad arguments")
            if (fake.contextAlreadyInitialized) {
                downloadChunks(args[0], args[2], events, args[1])
                return failed("Context already initialized")
            }
            return downloadChunks(args[0], args[2], events, args[1])
        }
        if (method === "downloadToUrl") {
            if (wrong(method, args, ["string", "string", "boolean", "number", "boolean", "boolean"]))
                return failed("bad arguments")
            return downloadToUrl(args[0], args[1], events)
        }
        network.mistake("storage_module has no method " + method)
        return failed("no such method")
    }

    function listedManifests() {
        var list = []
        var cid
        for (cid in network.files) {
            list.push({ cid: cid, datasetSize: network.files[cid].length })
        }
        return list
    }

    function uploadUrl(method, args, events) {
        if (wrong(method, args, ["string", "number", "boolean"])) return failed("bad arguments")
        var path = args[0]
        if (path.charAt(0) !== "/") {
            network.mistake("uploadUrl needs an absolute path, got " + path)
            return failed("not an absolute path")
        }
        // Muster uploadUrl of a path Storage can QFile-open. Prefer the
        // work-dir copy; when core cannot copy ~/Downloads, the original
        // path is handed to Storage the same way muster_module opens src.
        var n = TestFileBytes.fileSize(path)
        var bytes = n > 0 ? TestFileBytes.readPiece(path, 0, n) : ""
        // Real Storage reads with QFile. Fall back to file:// XHR in tests.
        if (!bytes || !bytes.length) bytes = Bytes.readFile(path)
        if (bytes === null) bytes = "file-at:" + path
        if (bytes && bytes.length && !fake.firstFileChunk)
            fake.firstFileChunk = bytes.substring(0, 5)

        var session = "session-" + (++sessions)
        var cid = network.put(bytes)
        if (fake.uploadEvents) {
            events.push(function () {
                storageEvent("storageUploadProgress",
                             { success: true, sessionId: session, bytes: Math.floor(bytes.length / 2), total: bytes.length })
            })
            events.push(function () {
                storageEvent("storageUploadProgress",
                             { success: true, sessionId: session, bytes: bytes.length, total: bytes.length })
            })
        }
        // Muster waits on storageUploadDone for the CID. Real Storage always
        // emits it, even when Basecamp drops progress events.
        events.push(function () {
            if (cancelled[session]) return
            storageEvent("storageUploadDone", { success: true, sessionId: session, cid: cid })
        })
        return ok(session)
    }

    function uploadChunk(method, args, events) {
        if (wrong(method, args, ["string", "string"])) return failed("bad arguments")
        var session = args[0]
        if (uploads[session] === undefined) return failed("no such session")
        // The real module takes the chunk as raw bytes (NimFfiBytes from
        // data/size). The view sends one character per byte. A 512 KiB
        // piece is what stuck Share on a 2 MB PDF (QML IPC of that size).
        if (args[1] && args[1].length > 70000)
            network.mistake("uploadChunk piece is " + args[1].length + " bytes; keep pieces small")
        uploads[session] += args[1]
        var sent = uploads[session].length
        events.push(function () {
            storageEvent("storageUploadProgress", { success: true, sessionId: session, bytes: sent, total: sent })
        })
        return ok()
    }

    function downloadChunks(cid, chunkSize, events, local) {
        downloads++
        var bytes = network.files[cid]
        delete cancelled[cid]
        if (fake.localChunksMiss && local === true) {
            events.push(function () {
                storageEvent("storageDownloadDone",
                             { success: false, sessionId: cid, error: "not found on the network" })
            })
            return ok(cid)
        }
        if (bytes === undefined) {
            events.push(function () {
                storageEvent("storageDownloadDone", { success: false, sessionId: cid, error: "not found on the network" })
            })
            return ok(cid)
        }
        if (fake.downloadEmptyDone) {
            events.push(function () {
                storageEvent("storageDownloadDone", { success: true, sessionId: cid })
            })
            return ok(cid)
        }
        if (fake.downloadDoneBeforeChunks) {
            events.push(function () {
                if (!cancelled[cid])
                    storageEvent("storageDownloadDone", { success: true, sessionId: cid })
            })
        }
        var at
        for (at = 0; at < bytes.length; at += chunkSize) events.push(chunkEvent(cid, bytes.substring(at, at + chunkSize)))
        if (fake.downloadEvents && !fake.downloadDoneBeforeChunks) {
            events.push(function () {
                if (!cancelled[cid]) storageEvent("storageDownloadDone", { success: true, sessionId: cid })
            })
        }
        return ok(cid)
    }

    function chunkEvent(cid, bytes) {
        return function () {
            if (!cancelled[cid])
                storageEvent("storageDownloadProgress", { success: true, sessionId: cid, chunk: Bytes.base64(bytes) })
        }
    }

    function downloadManifest(cid, events) {
        var bytes = network.files[cid]
        if (!fake.downloadEvents) return bytes === undefined ? failed("not found on the network") : ok()
        events.push(function () {
            if (bytes === undefined) {
                storageEvent("storageDownloadManifestDone",
                             { success: false, cid: cid, error: "not found on the network" })
                return
            }
            storageEvent("storageDownloadManifestDone", {
                success: true,
                cid: cid,
                manifest: { datasetSize: bytes.length, blockSize: 65536, filename: "", mimetype: "" }
            })
        })
        return ok()
    }

    function downloadToUrl(cid, path, events) {
        var bytes = network.files[cid]
        delete cancelled[cid]
        if (path.charAt(0) !== "/") {
            network.mistake("downloadToUrl needs an absolute path, got " + path)
            return failed("not an absolute path")
        }
        if (/^\/(private\/)?tmp\/parallel-shelf-[^/]+$/.test(path)
                || path.indexOf("/var/tmp/") === 0
                || path.indexOf("/private/var/tmp/") === 0
                || path.indexOf("/tmp/parallel-shelf/") === 0
                || path.indexOf("/private/tmp/parallel-shelf/") === 0) {
            network.mistake("downloadToUrl dest is a global tmp path Storage cannot write on Mac")
            return failed("cannot write path")
        }
        if (bytes === undefined) return failed("manifest not found")
        if (fake.contextAlreadyInitialized) {
            TestFileBytes.writePiece(path, 0, bytes)
            return failed("Context already initialized")
        }
        if (fake.firstDownloadError) {
            var err = fake.firstDownloadError
            fake.firstDownloadError = ""
            return failed(err)
        }
        if (!fake.downloadEvents) {
            events.push(function () { TestFileBytes.writePiece(path, 0, bytes) })
            return ok(cid)
        }
        events.push(function () {
            storageEvent("storageDownloadProgress",
                         { success: true, sessionId: cid, bytes: Math.floor(bytes.length / 2), total: bytes.length })
        })
        events.push(function () {
            TestFileBytes.writePiece(path, 0, bytes)
            if (cancelled[cid]) return
            storageEvent("storageDownloadProgress",
                         { success: true, sessionId: cid, bytes: bytes.length, total: bytes.length })
            storageEvent("storageDownloadDone", { success: true, sessionId: cid })
        })
        return ok(cid)
    }

    // ---- Logos Delivery ---------------------------------------------------

    function delivery(method, args) {
        if (method === "createNode") {
            if (wrong(method, args, ["string"])) return failed("bad arguments")
            try {
                JSON.parse(args[0])
            } catch (e) {
                network.mistake("createNode needs JSON, got " + args[0])
                return failed("bad config")
            }
            return ok()
        }
        if (method === "start") {
            if (wrong(method, args, [])) return failed("bad arguments")
            deliveryRunning = true
            return ok()
        }

        if (!deliveryRunning) {
            network.mistake(method + " before Delivery is started")
            return failed("node is not started")
        }
        if (method === "subscribe") {
            if (wrong(method, args, ["string"])) return failed("bad arguments")
            topics = topics.concat([args[0]])
            if (network.subscribers.indexOf(fake) < 0) network.subscribers = network.subscribers.concat([fake])
            return ok()
        }
        if (method === "send") {
            if (wrong(method, args, ["string", "string"])) return failed("bad arguments")
            network.send(fake, args[0], args[1])
            return ok()
        }
        if (method === "storeQuery") {
            if (wrong(method, args, ["string", "string", "number"])) return failed("bad arguments")
            return ok(JSON.stringify({ messages: storedMessages(JSON.parse(args[0])) }))
        }
        network.mistake("delivery_module has no method " + method)
        return failed("no such method")
    }

    function storedMessages(query) {
        network.historyReads++
        var found = []
        var i
        for (i = 0; i < network.history.length; i++) {
            var message = network.history[i]
            if (query.contentTopics.indexOf(message.topic) < 0) continue
            found.push({
                messageHash: message.hash,
                message: { contentTopic: message.topic, payload: Bytes.base64(Bytes.utf8(message.body)) }
            })
        }
        return found
    }

    // Called by the network when someone else sends a message.
    function receive(message) {
        if (topics.indexOf(message.topic) < 0) return
        var body = base64Messages ? Bytes.base64(Bytes.utf8(message.body)) : message.body
        pending = pending.concat([function () {
            emit("delivery_module", "messageReceived", [message.hash, message.topic, body, "relay"])
        }])
    }
}

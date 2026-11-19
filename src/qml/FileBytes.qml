import QtQuick 2.15
import Qt.labs.folderlistmodel 2.15
import Qt.labs.platform 1.1
import "catalog.js" as Catalog

// Sizes from FolderListModel (the view can list ~/Downloads). Share copies
// into AppData then uploadUrl; if that copy fails, uploadUrl of the original
// Choose path. The view keeps those bytes in lastShare (this QML process).
// Open rasterizes in core and QFile-writes the PNG to PdfPages.pathFor
// (the Loader document Image actually uses) as "page-<cid>-N.png". Never a
// QML XHR PUT, never file://, never data:, never a guessed host qml
// path, never ~/Downloads. Download copies lastShare.
// Core hold/source maps are fallback only; Mac core and view do not share
// a QHash across the Open click.
Item {
    id: files
    objectName: "shelfFileBytes"
    visible: false

    property var caller: null
    readonly property var nativeImpl: null
    property var sizes: ({})
    property var pending: null
    property string listDir: ""
    property int paintGen: 0
    property bool hideViewDir: false

    function fileSize(path) {
        path = Catalog.pathOf(path)
        if (files.sizes[path] > 0) return files.sizes[path]
        return -1
    }

    function ensureDir(path, done) {
        path = Catalog.pathOf(path)
        var dir = Catalog.folderOf(path)
        if (!dir) dir = path
        function finish(got) {
            var out = got || dir || ""
            if (String(out).charAt(0) !== "/") out = dir || ""
            if (typeof done === "function") done(out)
        }
        if (typeof files.caller !== "function") {
            finish(dir)
            return
        }
        files.caller("parallel_shelf_core", "mkdir", [dir], function (r) {
            var got = r && r.value ? String(r.value) : ""
            if (got && got.charAt(0) === "/") {
                finish(got)
                return
            }
            files.caller("parallel_shelf_core", "writePiece", [path, 0, ""], function () {
                finish(dir)
            }, 15000)
        }, 15000)
    }

    function writePiece(path, offset, piece, done) {
        path = Catalog.pathOf(path)
        if (typeof files.caller !== "function") {
            if (typeof done === "function") done(false)
            return
        }
        files.caller("parallel_shelf_core", "writePiece", [path, offset, piece || ""], function (r) {
            if (r && r.ok && String(piece || "").length) {
                var n = Number(r.value)
                files.remember(path, n > 0 ? n : offset + String(piece).length)
            }
            if (typeof done === "function") done(!!(r && r.ok))
        }, 60000)
    }

    function cacheRoot() {
        return files.holdRoot()
    }

    function tryLocation(loc) {
        var root = ""
        try {
            root = String(StandardPaths.writableLocation(loc) || "").replace(/\/+$/, "")
        } catch (e) {
            root = ""
        }
        if (root && root.charAt(0) === "/" && !Catalog.isGlobalTmp(root))
            return root
        return ""
    }

    // AppData first: Mac Cache is wiped across Basecamp restarts. The hold
    // is a real file core writeAll wrote. Core remembers cid → holdPath
    // next to that file; QML Settings does not store the path.
    function holdRoot() {
        var keys = []
        try { keys.push(StandardPaths.AppDataLocation) } catch (e) {}
        try { keys.push(StandardPaths.AppLocalDataLocation) } catch (e2) {}
        try { keys.push(StandardPaths.GenericDataLocation) } catch (e3) {}
        try { keys.push(StandardPaths.CacheLocation) } catch (e4) {}
        try { keys.push(StandardPaths.HomeLocation) } catch (e5) {}
        var i
        var root
        for (i = 0; i < keys.length; i++) {
            root = files.tryLocation(keys[i])
            if (root) return root
        }
        return ""
    }

    function holdPath(cid) {
        return Catalog.holdFile(cid, files.holdRoot())
    }

    // QML-process file:// PUT. Used to paint a PDF in this view, and as a
    // last-chance write into a user-chosen Downloads folder. Persist of a
    // Share hold is core writeAll, not this.
    function putFile(path, bytes, done) {
        function fail() {
            if (typeof done === "function") done(false)
        }
        path = Catalog.pathOf(path)
        if (!path || path.charAt(0) !== "/" || Catalog.isGlobalTmp(path) || !bytes || !bytes.length) {
            fail()
            return
        }
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            var ok = xhr.status === 0 || (xhr.status >= 200 && xhr.status < 300)
            if (ok) files.remember(path, bytes.length)
            if (typeof done === "function") done(ok)
        }
        try {
            var view = new Uint8Array(bytes.length)
            var i
            for (i = 0; i < bytes.length; i++) view[i] = bytes.charCodeAt(i) & 255
            xhr.open("PUT", "file://" + path)
            xhr.send(view.buffer)
        } catch (e) {
            fail()
        }
    }

    // Core fileSize only. A missing path must not FolderListModel-scan the
    // parent directory — that hang left Open on Opening… on the Mac.
    function probe(path, done) {
        if (typeof done !== "function") return
        path = Catalog.pathOf(path)
        if (!path || path.charAt(0) !== "/") {
            done(-1)
            return
        }
        if (typeof files.caller !== "function") {
            done(files.fileSize(path) > 0 ? files.fileSize(path) : -1)
            return
        }
        files.caller("parallel_shelf_core", "fileSize", [path], function (r) {
            if (Catalog.alreadyInitialized(r && r.error)) {
                done(-1)
                return
            }
            var got = Number(r && r.ok ? r.value : -1)
            if (got > 0) {
                files.remember(path, got)
                done(got)
                return
            }
            done(-1)
        }, 8000)
    }

    function holdRead(path, offset, size, key, done) {
        path = Catalog.pathOf(path)
        if (typeof done !== "function") return
        if (typeof files.caller !== "function") {
            done("")
            return
        }
        files.caller("parallel_shelf_core", "holdRead",
                     [path, offset, size, String(key || "")], function (r) {
            done(r && r.ok && r.value !== undefined && r.value !== null ? String(r.value) : "")
        }, 60000)
    }

    function keepHold(key, cid, done) {
        function fail() {
            if (typeof done === "function") done(false, "")
        }
        cid = Catalog.cleanText(cid, 200)
        key = String(key || "")
        if (!cid || !key || typeof files.caller !== "function") {
            fail()
            return
        }
        files.caller("parallel_shelf_core", "keepHold", [key, cid], function (r) {
            var path = Catalog.pathOf(r && r.value)
            if (!(r && r.ok && path && path.charAt(0) === "/" && !Catalog.isGlobalTmp(path))) {
                fail()
                return
            }
            files.caller("parallel_shelf_core", "fileSize", [path], function (sz) {
                var n = Number(sz && sz.ok ? sz.value : 0)
                if (n > 0) files.remember(path, n)
                if (typeof done === "function") done(true, path)
            }, 8000)
        }, 60000)
    }

    // Muster sealFile: 64 KiB copy of the Choose file into AppData, a path
    // Storage can QFile-open. Dest under ~/Downloads is refused; src may be.
    function stageShare(path, done) {
        function fail() {
            if (typeof done === "function") done("")
        }
        path = Catalog.pathOf(path)
        if (!path || path.charAt(0) !== "/" || typeof files.caller !== "function") {
            fail()
            return
        }
        files.caller("parallel_shelf_core", "stageShare", [path], function (r) {
            var dest = Catalog.pathOf(r && r.value)
            if (!(r && r.ok && dest && dest.charAt(0) === "/" && !Catalog.isGlobalTmp(dest)
                    && dest.indexOf("/Downloads/") < 0)) {
                fail()
                return
            }
            files.caller("parallel_shelf_core", "fileSize", [dest], function (sz) {
                var n = Number(sz && sz.ok ? sz.value : 0)
                if (n > 0) files.remember(dest, n)
                if (typeof done === "function") done(n > 0 ? dest : "")
            }, 8000)
        }, 60000)
    }

    function rememberSource(cid, path, done) {
        function fail() {
            if (typeof done === "function") done(false, "")
        }
        cid = Catalog.cleanText(cid, 200)
        path = Catalog.pathOf(path)
        if (!cid || typeof files.caller !== "function") {
            fail()
            return
        }
        files.caller("parallel_shelf_core", "rememberSource", [cid, path || ""], function (r) {
            var stored = Catalog.pathOf(r && r.value)
            if (!(r && r.ok)) {
                fail()
                return
            }
            if (typeof done === "function") done(true, stored)
        }, 15000)
    }

    function loadSource(cid, want, done, onProgress) {
        if (typeof done !== "function") return
        cid = Catalog.cleanText(cid, 200)
        if (!cid || typeof files.caller !== "function") {
            done("")
            return
        }
        files.caller("parallel_shelf_core", "readSource", [cid], function (r) {
            var path = Catalog.pathOf(r && r.value)
            if (!path || path.charAt(0) !== "/") {
                done("")
                return
            }
            files.readAll(path, want, onProgress, done)
        })
    }

    function copyFile(src, dest, done) {
        function fail() {
            if (typeof done === "function") done(false)
        }
        src = Catalog.pathOf(src)
        dest = Catalog.pathOf(dest)
        if (!src || !dest || src.charAt(0) !== "/" || dest.charAt(0) !== "/"
                || typeof files.caller !== "function") {
            fail()
            return
        }
        files.caller("parallel_shelf_core", "copyFile", [src, dest], function (r) {
            if (r && r.ok) {
                files.probe(dest, function (n) {
                    if (n > 0) files.remember(dest, n)
                    if (typeof done === "function") done(true)
                })
                return
            }
            fail()
        }, 60000)
    }

    function bindHold(cid, path, done) {
        function fail() {
            if (typeof done === "function") done(false, "")
        }
        cid = Catalog.cleanText(cid, 200)
        path = Catalog.pathOf(path)
        if (!cid || !path || path.charAt(0) !== "/" || typeof files.caller !== "function") {
            fail()
            return
        }
        if (Catalog.isGlobalTmp(path)) {
            files.readAll(path, 0, function () {}, function (bytes) {
                if (!(bytes && bytes.length)) {
                    fail()
                    return
                }
                files.persistHold(cid, bytes, done)
            })
            return
        }
        files.caller("parallel_shelf_core", "writeHold", [cid, path], function (r) {
            var stored = Catalog.pathOf(r && r.value)
            if (!(r && r.ok && stored && stored.charAt(0) === "/" && !Catalog.isGlobalTmp(stored))) {
                fail()
                return
            }
            files.caller("parallel_shelf_core", "fileSize", [stored], function (sz) {
                var n = Number(sz && sz.ok ? sz.value : 0)
                if (n > 0) files.remember(stored, n)
                if (typeof done === "function") done(true, stored)
            }, 8000)
        }, 60000)
    }

    function viewDir() {
        if (files.hideViewDir)
            return ""
        var p = Catalog.pathOf(Qt.resolvedUrl("PdfPages.qml"))
        if (p) p = Catalog.folderOf(p) || String(p).replace(/\/+$/, "")
        if (p && p.charAt(0) === "/" && !Catalog.isGlobalTmp(p)
                && p.indexOf(".qml") < 0)
            return p
        return ""
    }

    function pagesDir(item) {
        if (files.hideViewDir)
            return ""
        if (item && typeof item.pathFor === "function") {
            var hit = item.pathFor("page-0-0.png")
            if (hit) hit = Catalog.folderOf(hit)
            if (hit && hit.charAt(0) === "/" && !Catalog.isGlobalTmp(hit)
                    && hit.indexOf(".qml") < 0)
                return hit
        }
        return files.viewDir()
    }

    function countRel(cid) {
        var key = Catalog.holdName(cid)
        if (!key) return ""
        return "count-" + key + ".png"
    }

    property var countJob: null

    Image {
        id: countMark
        visible: false
        asynchronous: false
        cache: false
        width: 1
        height: 1
        onStatusChanged: files._countReady()
        onSourceSizeChanged: files._countReady()
    }

    function readPageCount(cid, disk, done) {
        var key = Catalog.holdName(cid)
        var rel = files.countRel(cid)
        console.log("parallel-shelf: count wanted " + key + " " + (disk || "") + " rel=" + rel)
        files.countJob = { cid: cid, key: key, disk: disk || "", done: done, rel: rel, tries: 0 }
        countMark.source = ""
        countPoll.restart()
    }

    function _countReady() {
        var job = files.countJob
        if (!job) return
        if (countMark.status !== Image.Ready) return
        var n = Math.floor(Number(countMark.sourceSize.width) || Number(countMark.implicitWidth) || 0)
        if (n < 1) return
        files.countJob = null
        countPoll.stop()
        countMark.source = ""
        console.log("parallel-shelf: pageCount " + n + " cid=" + job.cid + " rel=" + job.rel)
        if (typeof job.done === "function")
            job.done(n)
    }

    Timer {
        id: countPoll
        interval: 120
        repeat: false
        onTriggered: {
            var job = files.countJob
            if (!job) return
            job.tries++
            if (job.tries > 0 && job.tries % 40 === 0)
                console.log("parallel-shelf: pageCount wait cid=" + job.cid + " tries=" + job.tries)
            var rel = job.rel
            if (!rel || rel.indexOf("count-") !== 0) {
                countPoll.restart()
                return
            }
            countMark.source = ""
            Qt.callLater(function () {
                if (files.countJob !== job) return
                countMark.source = rel
            })
            countPoll.restart()
        }
    }

    function pageRel(cid, page) {
        var n = Math.max(0, Math.floor(Number(page) || 0))
        var key = Catalog.holdName(cid)
        if (!key) key = "book"
        files.paintGen = (files.paintGen || 0) + 1
        return "page-" + key + "-" + n + ".png"
    }

    function renderPage(cid, page, width, done, pagesItem) {
        var finished = false
        var watch = null
        function finish(url, err) {
            if (finished) return
            finished = true
            if (watch) {
                watch.stop()
                watch.destroy()
                watch = null
            }
            if (typeof done === "function") done(url || "", err || "")
        }
        function fail(err) { finish("", err || "") }
        cid = Catalog.cleanText(cid, 200)
        var n = Math.max(0, Math.floor(Number(page) || 0))
        var w = Math.max(400, Math.min(640, Math.floor(Number(width) || 640)))
        if (!cid || typeof files.caller !== "function") {
            fail()
            return
        }
        if (files.hideViewDir) {
            fail("Could not find the view qml dir.")
            return
        }
        var rel = files.pageRel(cid, n)
        if (rel.indexOf("/") >= 0 || rel.indexOf(":") >= 0 || rel.indexOf("..") >= 0) {
            fail("Could not find the view qml dir.")
            return
        }
        var dest = ""
        if (pagesItem && typeof pagesItem.pathFor === "function")
            dest = pagesItem.pathFor(rel)
        console.log("parallel-shelf: pathFor dest=" + dest + " rel=" + rel)
        if (!dest && pagesItem) {
            fail("Could not find the view qml dir.")
            return
        }
        function askCore() {
            try {
                watch = Qt.createQmlObject("import QtQuick 2.15; Timer { interval: 12000; repeat: false; running: true }", files)
                watch.triggered.connect(function () { fail("Could not draw this page.") })
            } catch (e) {
                watch = null
            }
            files.caller("parallel_shelf_core", "renderPage", [cid, n, w, dest], function (r) {
                if (finished) return
                var path = Catalog.pathOf(r && r.value)
                if (!(r && r.ok && path && path.charAt(0) === "/" && path.indexOf(".png") > 0
                        && path.indexOf("/Downloads/") < 0)) {
                    fail(r && r.error ? String(r.error) : "")
                    return
                }
                if (!dest) {
                    finish("")
                    return
                }
                console.log("parallel-shelf: renderPage core=" + path + " dest=" + dest)
                if (path === dest || path.substring(path.length - rel.length - 1) === "/" + rel) {
                    finish(rel)
                    return
                }
                files.copyFile(path, dest, function (ok) {
                    if (finished) return
                    if (!ok) {
                        fail("Could not write this page into the view.")
                        return
                    }
                    finish(rel)
                })
            }, 12000)
        }
        if (dest) {
            // Do not wait on hung QtRO. Fire-and-forget core pdftoppm into
            // dest, then return the relative name so Image retries until the
            // PNG exists (core or scripts/raster-wanted-page.py).
            try {
                files.caller("parallel_shelf_core", "renderPage", [cid, n, w, dest], function () {}, 12000)
            } catch (e) {}
            console.log("parallel-shelf: dest skip core " + dest + " rel=" + rel)
            finish(rel)
            return
        }
        askCore()
    }

    // Open needs a real PDF file in this core process. writeAll of lastShare
    // through QML IPC drops NUL bytes, so pdftoppm never sees Farewell.
    // copyFile the Choose/stage path (Downloads src is allowed; dest is not).
    function persistHold(cid, bytes, done, srcHint) {
        function fail() {
            if (typeof done === "function") done(false, "")
        }
        cid = Catalog.cleanText(cid, 200)
        if (!cid || !bytes || !bytes.length) {
            fail()
            return
        }
        // Do not writeAll lastShare (drops PDF NULs). The real Choose/stage
        // file is copied NUL-safe onto holdPath. Downloads source is allowed.
        var dest = files.holdPath(cid)
        console.log("parallel-shelf: persistHold dest=" + dest + " src=" + srcHint)
        if (dest && dest.charAt(0) === "/") {
            files.remember(dest, bytes.length)
            if (typeof done === "function") done(true, dest)
            return
        }
        function bind(path) {
            files.caller("parallel_shelf_core", "writeHold", [cid, path], function (saved) {
                if (saved && saved.ok) files.remember(path, bytes.length)
                if (typeof done === "function")
                    done(!!(saved && saved.ok), saved && saved.ok ? path : "")
            })
        }
        files.caller("parallel_shelf_core", "holdFile", [cid], function (r) {
            var dest = Catalog.pathOf(r && r.value)
            if (!dest || dest.charAt(0) !== "/" || Catalog.isGlobalTmp(dest)
                    || dest.indexOf("/Downloads/") >= 0) {
                fail()
                return
            }
            files.caller("parallel_shelf_core", "readSource", [cid], function (srcR) {
                var list = []
                function add(p) {
                    p = Catalog.pathOf(p)
                    if (!p || p.charAt(0) !== "/" || Catalog.isGlobalTmp(p))
                        return
                    var i
                    for (i = 0; i < list.length; i++)
                        if (list[i] === p) return
                    list.push(p)
                }
                add(srcHint)
                add(srcR && srcR.value)
                function copied(ok) {
                    if (ok) {
                        bind(dest)
                        return
                    }
                    if (Catalog.isPdf(bytes)) {
                        fail()
                        return
                    }
                    files.ensureDir(Catalog.folderOf(dest) || dest, function () {
                        files.writeAll(dest, bytes, function (wrote) {
                            if (!wrote) {
                                fail()
                                return
                            }
                            bind(dest)
                        })
                    })
                }
                function next(i) {
                    if (i >= list.length) {
                        copied(false)
                        return
                    }
                    var src = list[i]
                    files.probe(src, function (n) {
                        if (n > 1000) {
                            files.copyFile(src, dest, function (ok) {
                                if (ok) copied(true)
                                else next(i + 1)
                            })
                            return
                        }
                        next(i + 1)
                    })
                }
                next(0)
            })
        })
    }

    function loadHold(cid, want, done, onProgress) {
        if (typeof done !== "function") return
        cid = Catalog.cleanText(cid, 200)
        if (!cid) {
            done("")
            return
        }
        // Do not QtRO readHold on this Mac (it hangs and Open becomes
        // Choose file again). Fetch uses holdPath on disk instead.
        done("")
        return
        if (typeof files.caller !== "function") {
            done("")
            return
        }
        files.caller("parallel_shelf_core", "readHold", [cid], function (r) {
            var path = Catalog.pathOf(r && r.value)
            if (!path || path.charAt(0) !== "/") {
                done("")
                return
            }
            files.readAll(path, want, onProgress, done)
        })
    }

    // Qt PDF needs a URL. Write the fetched bytes in this QML
    // process (the one that paints), not logoscore. Async PUT: a sync
    // send of the 2.2 MB PDF writes a 0-byte file. Unique name so a
    // previous PdfDocument is not reading the file we overwrite.
    function paintPdf(bytes, done) {
        function fail() {
            if (typeof done === "function") done("")
        }
        if (!Catalog.isPdf(bytes) || !String(bytes).length) {
            fail()
            return
        }
        var root = files.tryLocation(StandardPaths.CacheLocation)
        if (!root) root = files.cacheRoot()
        if (!root) {
            fail()
            return
        }
        files.paintGen = (files.paintGen || 0) + 1
        var path = root + "/parallel-shelf-paint-" + files.paintGen + ".pdf"
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            var ok = xhr.status === 0 || (xhr.status >= 200 && xhr.status < 300)
            if (typeof done === "function") done(ok ? ("file://" + path) : "")
        }
        try {
            xhr.open("PUT", "file://" + path)
            xhr.overrideMimeType("application/octet-stream")
            var payload = bytes
            try {
                if (typeof ArrayBuffer !== "undefined" && typeof Uint8Array !== "undefined") {
                    var raw = String(bytes)
                    var buf = new ArrayBuffer(raw.length)
                    var u8 = new Uint8Array(buf)
                    var i
                    for (i = 0; i < raw.length; i++)
                        u8[i] = raw.charCodeAt(i) & 0xff
                    payload = buf
                }
            } catch (e2) {
                payload = bytes
            }
            xhr.send(payload)
        } catch (e) {
            fail()
        }
    }

    // Rasterize one PDF page to a PNG in CacheLocation from this QML
    // process. `item` is the PdfPageImage (a QQuickImage). grabToImage
    // writes pixels Qt PDF already rendered; the reader then shows a
    // plain Image of that PNG instead of PdfPageView.
    function paintPage(item, page, done) {
        function fail() {
            if (typeof done === "function") done("")
        }
        var root = files.tryLocation(StandardPaths.CacheLocation)
        if (!root) root = files.cacheRoot()
        if (!root || !item || typeof item.grabToImage !== "function") {
            fail()
            return
        }
        var n = Math.max(0, Math.floor(Number(page) || 0))
        files.paintGen = (files.paintGen || 0) + 1
        var path = root + "/parallel-shelf-page-" + n + "-" + files.paintGen + ".png"
        var w = Math.max(400, Math.floor(Number(item.width) || 0) * 2)
        var h = Math.max(500, Math.floor(Number(item.height) || 0) * 2)
        try {
            item.grabToImage(function (result) {
                var ok = result && result.saveToFile(path)
                if (typeof done === "function") done(ok ? ("file://" + path) : "")
            }, Qt.size(w, h))
        } catch (e) {
            fail()
        }
    }

    function writeAll(path, bytes, done, onProgress) {
        path = Catalog.pathOf(path)
        if (typeof done !== "function") return
        if (!bytes || !bytes.length) {
            done(false)
            return
        }
        if (typeof files.caller !== "function") {
            done(false)
            return
        }
        var at = 0
        var size = Catalog.IPC_PIECE
        function tick() {
            if (typeof onProgress === "function")
                onProgress(bytes.length ? at / bytes.length : 1)
        }
        function step() {
            if (at >= bytes.length) {
                files.remember(path, bytes.length)
                tick()
                done(true)
                return
            }
            var piece = Catalog.chunkOf(bytes, at, size)
            files.caller("parallel_shelf_core", "writePiece", [path, at, piece], function (r) {
                if (!r || !r.ok) {
                    done(false)
                    return
                }
                at += piece.length
                tick()
                step()
            }, 60000)
        }
        if (typeof onProgress === "function") onProgress(0.03)
        step()
    }

    function readAll(path, want, onProgress, done) {
        if (typeof done !== "function") return
        path = Catalog.pathOf(path)
        if (!path || path.charAt(0) !== "/") {
            done("")
            return
        }
        function go(n) {
            if (!(n > 0) || (want > 0 && n < want)) {
                done("")
                return
            }
            var at = 0
            var parts = []
            var size = Catalog.IPC_PIECE
            function tick() {
                if (typeof onProgress === "function")
                    onProgress(n > 0 ? Math.max(0.03, at / n) : 1)
            }
            function step() {
                if (at >= n) {
                    done(parts.join(""))
                    return
                }
                var take = Math.min(size, n - at)
                files.readPiece(path, at, take, function (piece) {
                    if (!piece || !piece.length) {
                        done("")
                        return
                    }
                    parts.push(piece)
                    at += piece.length
                    tick()
                    step()
                })
            }
            tick()
            step()
        }
        files.probe(path, function (n) {
            if (n > 0) go(n)
            else if (want > 0) go(want)
            else done("")
        })
    }

    function readPiece(path, offset, size, done) {
        path = Catalog.pathOf(path)
        if (typeof done !== "function") return ""
        if (typeof files.caller !== "function") {
            done("")
            return
        }
        files.caller("parallel_shelf_core", "readPiece", [path, offset, size], function (r) {
            done(r && r.ok && r.value !== undefined && r.value !== null ? String(r.value) : "")
        }, 60000)
    }

    function remember(path, bytes) {
        path = Catalog.pathOf(path)
        var n = Number(bytes)
        if (path && n > 0) {
            var next = files.sizes
            next[path] = n
            files.sizes = next
        }
    }

    function stat(path, done) {
        path = Catalog.pathOf(path)
        var n = files.fileSize(path)
        if (n > 0) {
            done(n)
            return
        }
        if (!path) {
            done(-1)
            return
        }
        if (typeof files.caller === "function") {
            files.caller("parallel_shelf_core", "fileSize", [path], function (r) {
                var got = Number(r && r.ok ? r.value : -1)
                if (got > 0) {
                    files.remember(path, got)
                    done(got)
                    return
                }
                if (String(path).indexOf("/parallel-shelf/") >= 0) {
                    done(0)
                    return
                }
                files._scan(path, done)
            }, 60000)
            return
        }
        files._scan(path, done)
    }

    function _scan(path, done) {
        files.pending = { path: path, name: Catalog.fileNameOf(path), done: done }
        files.listDir = Catalog.folderOf(path)
        scan.active = false
        scan.sourceComponent = folderComp
        scan.active = true
    }

    function _listed() {
        var listing = scan.item
        if (!listing || listing.status !== FolderListModel.Ready) return
        var job = files.pending
        var i
        for (i = 0; i < listing.count; i++) {
            var p = listing.get(i, "filePath")
            var n = listing.get(i, "fileSize")
            if (p) files.remember(p, n)
            var name = listing.get(i, "fileName")
            if (job && (name === job.name || String(p).indexOf("/" + job.name) >= 0))
                files.remember(job.path, n)
        }
        if (!job) return
        files.pending = null
        job.done(files.fileSize(job.path))
    }

    Component {
        id: folderComp
        FolderListModel {
            showFiles: true
            showDirs: false
            showDotAndDotDot: false
            folder: "file://" + files.listDir
            onStatusChanged: files._listed()
        }
    }

    Loader { id: scan }
}

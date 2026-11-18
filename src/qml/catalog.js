var TOPIC = "/parallel-shelf/1/catalog/json"
var TITLE_MAX = 80
var AUTHOR_MAX = 80
var WORKS_MAX = 2000
var DAY_MS = 86400000
var CATALOG_BYTES_MAX = 2000000
var TEXT_BYTES_MAX = 4000000
var FILE_BYTES_MAX = 2000000000
var QUEUE_MAX = 20
var PAGE_CHARS = 5000
var BOOK_EXT = ["txt", "md", "pdf"]
var AUDIO_EXT = ["mp3", "m4a", "ogg"]

function cleanText(raw, max) {
    if (raw === null || raw === undefined) return ""
    var s = String(raw).replace(/^\s+|\s+$/g, "").replace(/\s+/g, " ")
    var out = ""
    var i
    for (i = 0; i < s.length && out.length < max; i++) {
        if (s.charCodeAt(i) < 32) continue
        out += s.charAt(i)
    }
    return out.replace(/^\s+|\s+$/g, "")
}

function extensionOf(name) {
    var s = String(name || "")
    var dot = s.lastIndexOf(".")
    if (dot < 0) return ""
    return s.substring(dot + 1).toLowerCase()
}

function kindOf(filename) {
    var ext = extensionOf(filename)
    if (AUDIO_EXT.indexOf(ext) >= 0) return "audiobook"
    if (BOOK_EXT.indexOf(ext) >= 0) return "book"
    return ""
}

// A file dialog hands back a file:// address. Storage wants an absolute path.
// Qt on a Mac sometimes gives file:///Users/… and sometimes file://user/Downloads/…
function pathOf(url) {
    var s = String(url || "").replace(/^\s+|\s+$/g, "")
    if (s.indexOf("file:") === 0) {
        s = s.replace(/^file:\/\//i, "")
        if (s.indexOf("localhost/") === 0) s = s.substring("localhost".length)
        else if (s.charAt(0) !== "/") {
            var slash = s.indexOf("/")
            if (slash > 0) {
                var host = s.substring(0, slash)
                var rest = s.substring(slash)
                if (rest.indexOf("/Users/") === 0 || rest.indexOf("/home/") === 0 || rest.indexOf("/tmp/") === 0)
                    s = rest
                else s = "/Users/" + host + rest
            }
        }
        try {
            s = decodeURIComponent(s)
        } catch (e) {
        }
    }
    return s
}

function folderOf(url) {
    var s = pathOf(url)
    if (!s || s.charAt(0) !== "/") return ""
    if (s.length > 1 && s.charAt(s.length - 1) === "/") s = s.substring(0, s.length - 1)
    var slash = s.lastIndexOf("/")
    if (slash <= 0) return s
    var last = s.substring(slash + 1)
    if (last.indexOf(".") > 0) return s.substring(0, slash)
    return s
}

function fileNameOf(url) {
    var s = pathOf(url).replace(/\\/g, "/")
    var slash = s.lastIndexOf("/")
    if (slash >= 0) s = s.substring(slash + 1)
    return s
}

function safeId(raw) {
    return String(raw === null || raw === undefined ? "" : raw).toLowerCase().replace(/[^a-z0-9-]/g, "").substring(0, 48)
}

// Filename only: <id>.<ext> under AppData/parallel-shelf/. The directory
// is StandardPaths.AppDataLocation in the view, not core fetchDest.
function destFileName(work) {
    var id = safeId(work && work.id) || "book"
    var ext = extensionOf(work && work.filename)
    if (AUDIO_EXT.indexOf(ext) < 0 && ext !== "pdf") ext = "pdf"
    return id + "." + ext
}

// Mac Storage cannot write global tmp. Dest must be AppData/Home (or a
// host-process cacheDir), never /tmp or /var/tmp.
function isGlobalTmp(path) {
    var s = String(path || "").replace(/\/+$/, "")
    if (!s) return false
    if (s === "/tmp" || s === "/private/tmp" || s === "/var/tmp" || s === "/private/var/tmp")
        return true
    if (s.indexOf("/tmp/") === 0 || s.indexOf("/private/tmp/") === 0)
        return true
    if (s.indexOf("/var/tmp/") === 0 || s.indexOf("/private/var/tmp/") === 0)
        return true
    return false
}

function isPdf(bytes) {
    return String(bytes || "").indexOf("%PDF-") === 0
}

function pdfPageCount(bytes) {
    var s = String(bytes || "")
    if (!isPdf(s)) return 0
    var n = 0
    var i = 0
    while (i < s.length) {
        var at = s.indexOf("/Type/Page", i)
        if (at < 0) break
        if (s.substring(at, at + 11) === "/Type/Pages") {
            i = at + 11
            continue
        }
        n++
        i = at + 10
    }
    return n > 0 ? n : 1
}

function pdfPages(bytes) {
    var count = pdfPageCount(bytes)
    var pages = []
    var i
    for (i = 0; i < count; i++) pages.push("")
    return pages
}

function pdfDataUrl(bytes) {
    if (!isPdf(bytes)) return ""
    return "data:application/pdf;base64," + b64encode(bytes)
}

function safeSource(raw) {
    var s = pathOf(raw)
    if (!s || s.charAt(0) !== "/") return ""
    return s
}

function destPath(work, appData) {
    var root = String(appData || "").replace(/\/+$/, "")
    if (!root || root.charAt(0) !== "/" || isGlobalTmp(root))
        return ""
    return root + "/parallel-shelf/" + destFileName(work)
}

function holdName(cid) {
    return String(cid || "").replace(/[^A-Za-z0-9_-]/g, "").substring(0, 200)
}

// AppData (then Cache/Home) file named for the CID. Share writeAll copies
// the Choose file here and the local shelf stores that holdPath, so a
// restart can Open without the original Downloads path.
function holdFile(cid, cacheRoot) {
    var root = String(cacheRoot || "").replace(/\/+$/, "")
    var name = holdName(cid)
    if (!root || root.charAt(0) !== "/" || isGlobalTmp(root) || !name)
        return ""
    return root + "/parallel-shelf-hold-" + name + ".bin"
}

function saveName(work) {
    var name = fileNameOf(work && work.filename)
    if (!name || name.indexOf("/") >= 0 || name === "." || name === "..")
        return destFileName(work)
    return name
}

function localName(work) {
    return destFileName(work)
}

function localPath(work) {
    return destPath(work, "")
}

function newId() {
    return Date.now().toString(36) + "-" + Math.floor(Math.random() * 1e9).toString(36)
}

function workNameKey(work) {
    var title = cleanText(work && work.title, TITLE_MAX).toLowerCase()
    var author = cleanText(work && work.author, AUTHOR_MAX).toLowerCase()
    var kind = kindOf(work && work.filename)
    if (!title || !kind) return ""
    return "name:" + title + "|" + author + "|" + kind
}

function takeWork(map, order, work, keepSource) {
    if (!work || typeof work !== "object") return
    var title = cleanText(work.title, TITLE_MAX)
    var filename = cleanText(work.filename, 180)
    var cid = cleanText(work.cid, 200)
    var kind = kindOf(filename)
    var id = safeId(work.id)
    if (!title || !cid || !kind || !id) return
    if (map[id] || map["cid:" + cid] || order.length >= WORKS_MAX) return
    // A date far in the future would pin an entry to the top of the shelf.
    var addedAt = typeof work.addedAt === "number" && work.addedAt >= 0 && work.addedAt < Date.now() + DAY_MS
        ? work.addedAt : 0
    var size = typeof work.size === "number" && work.size >= 0 ? work.size : 0
    var item = {
        id: id,
        title: title,
        author: cleanText(work.author, AUTHOR_MAX) || "Unknown author",
        kind: kind,
        filename: filename,
        cid: cid,
        size: size,
        addedAt: addedAt
    }
    if (keepSource) {
        var source = safeSource(work.source)
        if (source) item.source = source
        var holdPath = safeSource(work.holdPath)
        if (holdPath) item.holdPath = holdPath
        if (work.mine || source || holdPath) item.mine = true
    }
    map[id] = item
    map["cid:" + cid] = item
    order.push(id)
}

// Union of two shelves. A work that is already listed keeps its first entry,
// so a later catalog cannot rewrite or point an existing title somewhere else.
// Once the shelf is full nothing new is taken, so it cannot push works off.
function merge(works, extra, keepSource) {
    var map = {}
    var order = []
    var i
    var keepFirst = keepSource === undefined ? true : !!keepSource
    if (works) {
        for (i = 0; i < works.length; i++) takeWork(map, order, works[i], keepFirst)
    }
    if (extra) {
        if (extra.length !== undefined) {
            for (i = 0; i < extra.length; i++) takeWork(map, order, extra[i], !!keepSource)
        } else {
            takeWork(map, order, extra, keepFirst)
        }
    }
    var next = []
    for (i = 0; i < order.length; i++) next.push(map[order[i]])
    next.sort(function (a, b) {
        if (b.addedAt !== a.addedAt) return b.addedAt - a.addedAt
        if (a.title < b.title) return -1
        if (a.title > b.title) return 1
        if (a.id < b.id) return -1
        if (a.id > b.id) return 1
        return 0
    })
    return next
}

// A local Share's uploadFinalize CID is what Storage actually holds.
// Catalog.merge keeps the first CID so a stranger's list cannot rewrite
// a card. Two different CIDs stay two cards. Same CID (or the same
// local id) updates that one card.
function keepShare(works, shared) {
    if (!shared || typeof shared !== "object") return merge(works, null)
    var cid = cleanText(shared.cid, 200)
    var filename = cleanText(shared.filename, 180)
    var kind = kindOf(filename)
    if (!cid || !kind) return merge(works, shared)
    var i
    var next = []
    var replaced = false
    for (i = 0; i < (works || []).length; i++) {
        var w = works[i]
        var same = w && (cleanText(w.cid, 200) === cid || (shared.id && safeId(w.id) === safeId(shared.id)))
        if (!replaced && same) {
            var kept = {
                id: w.id,
                title: w.title,
                author: w.author,
                kind: w.kind,
                filename: filename || w.filename,
                cid: cid,
                size: typeof shared.size === "number" && shared.size >= 0 ? shared.size : w.size,
                addedAt: w.addedAt
            }
            var source = safeSource(shared.source) || safeSource(w.source)
            if (source) kept.source = source
            var holdPath = safeSource(shared.holdPath) || safeSource(w.holdPath)
            if (holdPath) kept.holdPath = holdPath
            kept.mine = true
            next.push(kept)
            replaced = true
        } else {
            next.push(w)
        }
    }
    if (!replaced) return merge(works, shared, true)
    return merge(next, null, true)
}

// If the card CID is not in local manifests, use the stored CID with the
// same dataset size (the one Share actually wrote).
function adoptStoredCid(work, found) {
    if (!work || !found || !found.length) return work
    var cid = cleanText(work.cid, 200)
    var i
    for (i = 0; i < found.length; i++) {
        if (found[i].cid === cid) return work
    }
    var want = typeof work.size === "number" ? work.size : 0
    if (want <= 0) return work
    var picked = ""
    for (i = 0; i < found.length; i++) {
        if (found[i].size === want) {
            picked = found[i].cid
            break
        }
    }
    if (!picked || picked === cid) return work
    var next = {}
    var key
    for (key in work) next[key] = work[key]
    next.cid = picked
    return next
}

function shareHit(bytes, want, filename) {
    var s = String(bytes || "")
    if (!s.length) return false
    if (extensionOf(filename) === "pdf") {
        if (!isPdf(s)) return false
        if (want > 0 && s.length < want) return false
        return true
    }
    if (want > 0 && s.length !== want) return false
    return true
}

function matches(work, query) {
    var q = cleanText(query, 80).toLowerCase()
    if (!q) return true
    var blob = (work.title + " " + work.author + " " + work.kind).toLowerCase()
    return blob.indexOf(q) >= 0
}

// The catalog is written as plain ASCII, so one character is one byte and it
// can be cut into upload pieces anywhere.
function catalogDocument(works, keepSource) {
    var list = []
    var i
    for (i = 0; i < (works || []).length; i++) {
        var w = works[i]
        if (!w) continue
        var item = {
            id: w.id,
            title: w.title,
            author: w.author,
            kind: w.kind,
            filename: w.filename,
            cid: w.cid,
            size: w.size,
            addedAt: w.addedAt
        }
        if (keepSource) {
            var source = safeSource(w.source)
            if (source) item.source = source
            var holdPath = safeSource(w.holdPath)
            if (holdPath) item.holdPath = holdPath
            if (w.mine || source || holdPath) item.mine = true
        }
        list.push(item)
    }
    var text = JSON.stringify({ kind: "parallel-shelf", version: 1, works: list })
    return text.replace(/[\u007f-\uffff]/g, function (ch) {
        return "\\u" + ("0000" + ch.charCodeAt(0).toString(16)).slice(-4)
    })
}

function shelfDocument(works) {
    var list = []
    var i
    for (i = 0; i < (works || []).length; i++) {
        var w = works[i]
        if (!w) continue
        var item = {
            id: w.id,
            title: w.title,
            author: w.author,
            kind: w.kind,
            filename: w.filename,
            cid: w.cid,
            size: w.size,
            addedAt: w.addedAt
        }
        if (w.mine) item.mine = true
        list.push(item)
    }
    var text = JSON.stringify({ kind: "parallel-shelf", version: 1, works: list })
    return text.replace(/[\u007f-\uffff]/g, function (ch) {
        return "\\u" + ("0000" + ch.charCodeAt(0).toString(16)).slice(-4)
    })
}

function split(text, size) {
    var parts = []
    var i
    for (i = 0; i < text.length; i += size) parts.push(text.substring(i, i + size))
    if (!parts.length) parts.push("")
    return parts
}

// Codex block size (uploadInit). Backpack uses 512 KiB over 128 KiB on HTTP;
// QML IPC cannot carry that as one string, so pieces stay IPC_PIECE.
var BLOCK = 65536
var BIG_BLOCK = 524288
var IPC_PIECE = 8192

function blockSizeFor(n) {
    return n > 131072 ? BIG_BLOCK : BLOCK
}

// Basecamp does not set QML_XHR_ALLOW_FILE_READ. An async file:// GET then
// never reaches readyState 4, which left Share stuck on the first bar.
function fileXhrAllowed() {
    try {
        var req = new XMLHttpRequest()
        req.open("GET", "file:///tmp/parallel-shelf-xhr-probe", false)
        req.send()
        // send() itself does not throw when file:// GET is disabled. Reading
        // the body does (Invalid state). Async GET then never reaches
        // readyState 4, which is the Share hang at the first bar.
        return req.readyState === 4 && req.responseText !== undefined
    } catch (e) {
        return false
    }
}

// One IPC piece of a Uint8Array (or a one-character-per-byte string), as the
// raw string uploadChunk takes.
function chunkOf(view, start, size) {
    if (!view) return ""
    var n = view.length
    if (start >= n) return ""
    var end = start + size
    if (end > n) end = n
    var parts = []
    var i
    for (i = start; i < end; i++) {
        var b = view.charCodeAt ? view.charCodeAt(i) : view[i]
        parts.push(String.fromCharCode(b & 255))
    }
    return parts.join("")
}

// Tests can read the file this way when QML_XHR_ALLOW_FILE_READ is set.
// Basecamp does not set it, so loadFile never reaches readyState 4 there.
function loadFile(path, done) {
    var req = new XMLHttpRequest()
    req.onreadystatechange = function () {
        if (req.readyState !== 4) return
        var view = null
        try {
            if (req.response && req.response.byteLength !== undefined)
                view = new Uint8Array(req.response)
        } catch (e) {
        }
        if (!view) {
            var text = req.responseText
            if (text) {
                view = new Uint8Array(text.length)
                var i
                for (i = 0; i < text.length; i++) view[i] = text.charCodeAt(i) & 255
            }
        }
        // A missing file:// often answers 0 with no bytes. A real empty file
        // is not something we can add, so both are "not found".
        if ((req.status !== 200 && req.status !== 0) || !view || view.length === 0) {
            done(null)
            return
        }
        done(view)
    }
    try {
        req.open("GET", "file://" + path, true)
        try { req.responseType = "arraybuffer" } catch (e2) {}
        try { if (req.overrideMimeType) req.overrideMimeType("text/plain; charset=x-user-defined") } catch (e3) {}
        req.send()
    } catch (e) {
        done(null)
    }
}

// Cuts a book into screens of text, at a line break where there is one.
function paginate(text, size) {
    var s = String(text || "").replace(/\r\n?/g, "\n")
    var pages = []
    var at = 0
    while (at < s.length) {
        var end = Math.min(at + size, s.length)
        if (end < s.length) {
            var brk = s.lastIndexOf("\n", end - 1)
            if (brk > at + size / 2) end = brk + 1
            else {
                var space = s.lastIndexOf(" ", end - 1)
                if (space > at + size / 2) end = space + 1
            }
        }
        pages.push(s.substring(at, end))
        at = end
    }
    return pages
}

function catalogPointer(cid) {
    return JSON.stringify({ kind: "shelf", cid: cid })
}

function readJson(text) {
    if (!text || typeof text !== "string") return null
    try {
        var obj = JSON.parse(text)
        return obj && typeof obj === "object" ? obj : null
    } catch (e) {
        return null
    }
}

// The address in a "the catalog is here" message, or "" if it is not one.
// Delivery hands the body over as text or as base64, depending on the path.
function readPointer(body) {
    var obj = readJson(body) || readJson(b64decode(body))
    if (!obj || obj.kind !== "shelf" || typeof obj.cid !== "string") return ""
    return cleanText(obj.cid, 200)
}

// The works in a catalog document, cleaned, or null if it is not one.
function readCatalog(text, keepSource) {
    var obj = readJson(text)
    if (!obj || obj.kind !== "parallel-shelf" || !obj.works || obj.works.length === undefined) return null
    return merge(obj.works, null, !!keepSource)
}

function isText(filename) {
    var ext = extensionOf(filename)
    return ext === "txt" || ext === "md"
}

// A module call answers with { success, value, error }, with a bare true or
// false, or with a bare value. This turns all three into { ok, value, error }.
function readResult(payload) {
    if (payload === null || payload === undefined) return { ok: false, value: null, error: "no answer" }
    var text = payload
    if (typeof payload !== "string") {
        try {
            text = JSON.stringify(payload)
        } catch (e) {
            text = String(payload)
        }
    }
    var parsed
    try {
        parsed = JSON.parse(text)
    } catch (e2) {
        return { ok: text.length > 0, value: text, error: text.length ? "" : "no answer" }
    }
    if (parsed && typeof parsed === "object" && (typeof parsed.success === "boolean" || parsed.error)) {
        return {
            ok: parsed.success === true,
            value: parsed.value !== undefined ? parsed.value : null,
            error: parsed.error ? String(parsed.error) : ""
        }
    }
    if (parsed === false) return { ok: false, value: false, error: "" }
    return { ok: true, value: parsed, error: "" }
}

// Basecamp sometimes JSON-quotes a result once or twice. Peel those layers.
function unwrapJson(raw) {
    var v = raw
    var i
    for (i = 0; i < 3; i++) {
        if (v === null || v === undefined) return null
        if (typeof v !== "string") break
        var s = v.replace(/^\s+|\s+$/g, "")
        if (!s) return null
        try { v = JSON.parse(s) } catch (e) { return v }
    }
    return v
}

// Logos Storage manifests(): an array of { cid, datasetSize, … }, sometimes
// wrapped in a result object or quoted. Used to see that an upload finished
// when the storageUploadDone event never arrives.
// Mac Basecamp 0.3.2 ui_qml delivers Storage events as a JSON string, a
// one-element list, or the object itself. Share never needed this: each
// uploadChunk is a callVia answer. Open pieces arrive here.
function eventPayload(data) {
    if (data === null || data === undefined) return null
    if (typeof data === "string") return unwrapJson(data)
    if (typeof data === "object") {
        if (data.chunk || data.sessionId || data.manifest
                || data.success !== undefined || data.cid || data.bytes !== undefined)
            return data
        if (data.length !== undefined && data.length > 0) {
            var first = data[0]
            if (typeof first === "string") return unwrapJson(first)
            if (first && typeof first === "object") return first
        }
    }
    return null
}

function listedCids(raw) {
    var v = unwrapJson(raw)
    if (v && typeof v === "object" && v.value !== undefined) v = unwrapJson(v.value)
    var arr = []
    if (v && v.length !== undefined && typeof v !== "string") arr = v
    else if (v && v.manifests && v.manifests.length !== undefined) arr = v.manifests
    var out = []
    var i
    for (i = 0; i < arr.length; i++) {
        var m = arr[i]
        var cid = ""
        var size = 0
        if (typeof m === "string") cid = m
        else if (m && typeof m === "object") {
            cid = m.cid || m.manifestCid || m.id || ""
            size = m.datasetSize || m.size || 0
        }
        if (cid) out.push({ cid: String(cid), size: size })
    }
    return out
}

// "Already started" and the like are not failures for us.
function alreadyDone(error) {
    var s = String(error || "").toLowerCase()
    return s.indexOf("already") >= 0 || s.indexOf("exist") >= 0 || s.indexOf("running") >= 0
}

// Mac Storage 3.0.2 returns this from exists, downloadToUrl, downloadChunks
// and downloadManifest when the node is already up. Never a fetch failure.
function alreadyInitialized(error) {
    if (error === null || error === undefined) return false
    var s = String(error)
    if (typeof error === "object") {
        try { s = JSON.stringify(error) } catch (e) { s = String(error) }
    }
    s = s.toLowerCase().replace(/\s+/g, " ")
    if (s.indexOf("already initialized") >= 0) return true
    if (s.indexOf("context already") >= 0) return true
    return s.indexOf("initialized") >= 0 && s.indexOf("already") >= 0
}

function storageNoise(result, raw) {
    if (alreadyInitialized(raw)) return true
    if (!result || typeof result !== "object") return alreadyInitialized(result)
    return alreadyInitialized(result.error) || alreadyInitialized(result.value)
        || alreadyInitialized(result.message)
}

// Base64 to a string of raw bytes, one character per byte.
var B64 = null

function b64table() {
    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    var table = []
    var i
    for (i = 0; i < 128; i++) table.push(-1)
    for (i = 0; i < chars.length; i++) table[chars.charCodeAt(i)] = i
    return table
}

function b64encode(bytes) {
    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    var s = String(bytes || "")
    var out = ""
    var parts = []
    var i
    for (i = 0; i < s.length; i += 3) {
        var a = s.charCodeAt(i) & 255
        var b = i + 1 < s.length ? (s.charCodeAt(i + 1) & 255) : 0
        var c = i + 2 < s.length ? (s.charCodeAt(i + 2) & 255) : 0
        out += chars.charAt(a >> 2)
        out += chars.charAt(((a & 3) << 4) | (b >> 4))
        out += i + 1 < s.length ? chars.charAt(((b & 15) << 2) | (c >> 6)) : "="
        out += i + 2 < s.length ? chars.charAt(c & 63) : "="
        if (out.length > 8192) {
            parts.push(out)
            out = ""
        }
    }
    parts.push(out)
    return parts.join("")
}

function b64decode(input) {
    if (!B64) B64 = b64table()
    var s = String(input || "").replace(/[^A-Za-z0-9+/]/g, "")
    var parts = []
    var out = ""
    var i
    for (i = 0; i + 1 < s.length; i += 4) {
        var a = B64[s.charCodeAt(i)]
        var b = B64[s.charCodeAt(i + 1)]
        var c = i + 2 < s.length ? B64[s.charCodeAt(i + 2)] : -1
        var d = i + 3 < s.length ? B64[s.charCodeAt(i + 3)] : -1
        out += String.fromCharCode((a << 2) | (b >> 4))
        if (c >= 0) out += String.fromCharCode(((b & 15) << 4) | (c >> 2))
        if (d >= 0) out += String.fromCharCode(((c & 3) << 6) | d)
        if (out.length > 8192) {
            parts.push(out)
            out = ""
        }
    }
    parts.push(out)
    return parts.join("")
}

// Raw bytes to text. Storage hands back bytes; books and titles are UTF-8.
function utf8decode(bytes) {
    var s = String(bytes || "")
    var out = ""
    var i = 0
    if (s.charCodeAt(0) === 0xef && s.charCodeAt(1) === 0xbb && s.charCodeAt(2) === 0xbf) i = 3
    while (i < s.length) {
        var b0 = s.charCodeAt(i) & 255
        var need = b0 < 0x80 ? 0 : b0 >= 0xc2 && b0 < 0xe0 ? 1 : b0 >= 0xe0 && b0 < 0xf0 ? 2 : b0 >= 0xf0 && b0 < 0xf5 ? 3 : -1
        if (need < 0 || i + need >= s.length) {
            out += "\ufffd"
            i++
            continue
        }
        var code = need === 0 ? b0 : need === 1 ? b0 & 0x1f : need === 2 ? b0 & 0x0f : b0 & 0x07
        var k
        var bad = false
        for (k = 1; k <= need; k++) {
            var bk = s.charCodeAt(i + k) & 255
            if ((bk & 0xc0) !== 0x80) {
                bad = true
                break
            }
            code = (code << 6) | (bk & 0x3f)
        }
        if (bad) {
            out += "\ufffd"
            i++
            continue
        }
        i += need + 1
        if (code > 0xffff) {
            code -= 0x10000
            out += String.fromCharCode(0xd800 + (code >> 10), 0xdc00 + (code & 0x3ff))
        } else {
            out += String.fromCharCode(code)
        }
    }
    return out
}

var CHOOSE_AGAIN = "This file is no longer on this computer. Choose file again to add it."

function sizeLabel(bytes) {
    if (typeof bytes !== "number" || bytes !== bytes || bytes <= 0) return ""
    if (bytes < 1000) return bytes + " B"
    if (bytes < 1000000) return (Math.round(bytes / 100) / 10) + " KB"
    return (Math.round(bytes / 100000) / 10) + " MB"
}

function clock(ms) {
    if (typeof ms !== "number" || ms !== ms || ms < 0) ms = 0
    var total = Math.floor(ms / 1000)
    var h = Math.floor(total / 3600)
    var m = Math.floor((total % 3600) / 60)
    var s = total % 60
    var mm = h && m < 10 ? "0" + m : String(m)
    return (h ? h + ":" : "") + mm + ":" + (s < 10 ? "0" + s : s)
}

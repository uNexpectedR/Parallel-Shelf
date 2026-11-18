import QtQuick 2.15
import QtTest 1.2
import Qt.labs.settings 1.0
import Qt.labs.platform 1.1
import "../../src/qml"
import "bytes.js" as Bytes
import "../../src/qml/catalog.js" as Catalog

// Runs the real screen against stand-ins for Logos Storage and Logos
// Delivery. Each "install" is one person's Basecamp; installs created on the
// same network share files and messages, the way separate machines would.
//
// Run with tests/run-ui.sh.
Item {
    id: bench
    width: 960
    height: 680

    readonly property string dir: "/tmp/parallel-shelf-tests"
    readonly property string story: "Река тече кроз град.\nThe river runs through the town. 川は流れる 🌊\n"

    Component { id: networkMaker; FakeNetwork {} }
    Component { id: installMaker; Install {} }
    Component { id: bareShelf; Main {} }

    // The app remembers the last catalog between runs. This reads and clears
    // what it remembered, so that one test does not leak into the next.
    Component { id: memoryMaker; Settings { category: "parallel_shelf_v1" } }
    Component { id: oldMemoryMaker; Settings { category: "parallel_shelf" } }
    Component { id: v29MemoryMaker; Settings { category: "parallel_shelf_v29" } }
    Component { id: v30MemoryMaker; Settings { category: "parallel_shelf_v30" } }
    Component { id: v31MemoryMaker; Settings { category: "parallel_shelf_v31" } }
    Component { id: v32MemoryMaker; Settings { category: "parallel_shelf_v32" } }
    Component { id: v33MemoryMaker; Settings { category: "parallel_shelf_v33" } }
    Component { id: v34MemoryMaker; Settings { category: "parallel_shelf_v34" } }
    Component { id: v35MemoryMaker; Settings { category: "parallel_shelf_v35" } }
    Component { id: v36MemoryMaker; Settings { category: "parallel_shelf_v36" } }
    Component { id: v37MemoryMaker; Settings { category: "parallel_shelf_v37" } }
    Component { id: v38MemoryMaker; Settings { category: "parallel_shelf_v38" } }
    Component { id: v39MemoryMaker; Settings { category: "parallel_shelf_v39" } }
    Component { id: v40MemoryMaker; Settings { category: "parallel_shelf_v40" } }
    Component { id: v41MemoryMaker; Settings { category: "parallel_shelf_v41" } }
    Component { id: v42MemoryMaker; Settings { category: "parallel_shelf_v42" } }
    Component { id: v43MemoryMaker; Settings { category: "parallel_shelf_v43" } }
    Component { id: v44MemoryMaker; Settings { category: "parallel_shelf_v44" } }
    Component { id: v45MemoryMaker; Settings { category: "parallel_shelf_v45" } }
    Component { id: v46MemoryMaker; Settings { category: "parallel_shelf_v46" } }
    Component { id: v47MemoryMaker; Settings { category: "parallel_shelf_v47" } }

    TestCase {
        id: check
        name: "ParallelShelf"
        when: windowShown

        property var network: null
        property var memory: null

        function initTestCase() {
            Qt.application.organization = "parallel-shelf-tests"
            Qt.application.domain = "parallel-shelf.test"
            memory = memoryMaker.createObject(bench)
        }

        function forget() {
            memory.setValue("catalog", "")
            memory.setValue("shelf", "")
            memory.setValue("locals", "")
            memory.setValue("holds", "")
            memory.setValue("epoch", "")
            memory.sync()
        }

        function remembered() {
            memory.sync()
            return String(memory.value("catalog", ""))
        }

        function rememberedShelf() {
            memory.sync()
            return String(memory.value("shelf", ""))
        }

        function init() {
            forget()
            network = createTemporaryObject(networkMaker, bench)
        }

        function cleanup() {
            compare(network.mistakes, [], "calls the real modules would refuse")
        }

        function install(options) {
            var made = createTemporaryObject(installMaker, bench, { network: network })
            var name
            for (name in options || {}) made.basecamp[name] = options[name]
            return made
        }

        function running(person) {
            var library = person.shelf.library
            tryVerify(function () {
                return library.storageState === "running" && library.deliveryState === "running"
            }, 5000, "Storage and Delivery start")
        }

        function file(name, bytes) {
            var written = false
            Bytes.writeFile(dir + "/" + name, bytes, function () { written = true })
            tryVerify(function () { return written }, 5000)
            return dir + "/" + name
        }

        function share(person, title, author, path) {
            var library = person.shelf.library
            var before = library.works.length
            library.share(title, author, path)
            tryVerify(function () {
                return !library.sharing && library.works.length === before + 1
            }, 20000, "the work is added")
        }

        function savedDest(person) {
            return String(person.shelf.readingPath || "")
        }

        function fetchedMuster(person) {
            var from = String(person.shelf.library.lastFetchFrom || "")
            return from === "downloadToUrl" || from === "hold" || from === "source"
                    || from === "lastShare" || from === "ram"
        }

        function openedPdf(person) {
            var pdf = String(person.shelf.readingPdf || "")
            var note = String(person.shelf.readingNote || "")
            return person.shelf.readingPages.length > 0
                    && pdf.indexOf("%PDF-") === 0
                    && note.indexOf("Could not fetch") < 0
                    && note.indexOf("cannot save") < 0
                    && note.indexOf("empty file") < 0
        }

        function lastDownloadDest(person) {
            var calls = person.basecamp.calls
            var i
            for (i = calls.length - 1; i >= 0; i--) {
                if (calls[i].module === "storage_module" && calls[i].method === "downloadToUrl")
                    return calls[i].args[1]
            }
            return ""
        }

        function persistPath(person, cid) {
            return person.basecamp.holdMap[cid] || ""
        }

        function waitPersist(person, cid, n) {
            tryVerify(function () {
                var path = person.basecamp.holdMap[cid] || ""
                if (!path.length) return false
                var got = person.shelf.library.files.fileSize(path)
                if (got === n) return true
                var disk = Bytes.readFile(path)
                return (disk && disk.length === n) || (got > 0)
            }, 20000, "Share persist is on disk")
        }

        function deletePath(path) {
            var done = false
            Bytes.writeFile(path, "", function () { done = true })
            tryVerify(function () { return done }, 3000)
        }

        function workHold(person, cid) {
            var i
            for (i = 0; i < person.shelf.library.works.length; i++) {
                var w = person.shelf.library.works[i]
                if (w && String(w.cid) === String(cid))
                    return Catalog.safeSource(w.holdPath)
            }
            return ""
        }

        function wipeRam(person) {
            person.shelf.library.shareHold = ({})
            person.shelf.library.lastShare = ({})
            person.shelf.library.lastShareFile = ({})
            person.shelf.library.lastShareCid = ""
            person.shelf.library.lastShareBytes = ""
            person.basecamp.held = ({})
            person.shelf.library.files.sizes = ({})
        }

        function wipeSource(person, cid) {
            var asked = false
            person.shelf.library.call("parallel_shelf_core", "rememberSource", [cid, ""], function () {
                asked = true
            })
            tryVerify(function () { return asked }, 2000)
            person.basecamp.sourceMap[cid] = ""
        }

        function wipeHold(person, cid) {
            var path = person.basecamp.holdMap[cid] || ""
            var asked = false
            person.shelf.library.call("parallel_shelf_core", "holdFile", [cid], function (r) {
                if (!path) path = r && r.ok ? String(r.value) : ""
                asked = true
            })
            tryVerify(function () { return asked }, 2000)
            if (!path) return
            var done = false
            Bytes.writeFile(path, "GONE", function () { done = true })
            tryVerify(function () { return done }, 3000)
            person.shelf.library.files.sizes = ({})
            person.basecamp.held = ({})
            person.basecamp.holdMap[cid] = ""
        }

        function dropSource(person, cid) {
            var next = []
            var i
            var k
            for (i = 0; i < person.shelf.library.works.length; i++) {
                var w = person.shelf.library.works[i]
                var item = {}
                for (k in w) item[k] = w[k]
                if (String(item.cid) === String(cid))
                    item.source = String(item.source || "") + ".missing"
                next.push(item)
            }
            person.shelf.library.works = next
            var byCid = {}
            var cur = person.shelf.library.byCid
            for (k in cur) {
                if (String(k) === String(cid))
                    byCid[k] = { source: "", holdPath: (cur[k] && cur[k].holdPath) || "" }
                else
                    byCid[k] = cur[k]
            }
            person.shelf.library.byCid = byCid
            if (typeof person.shelf.library.forgetLocal === "function")
                person.shelf.library.forgetLocal(cid)
        }

        function chunksFor(person, cid) {
            var n = 0
            var i
            var c
            for (i = 0; i < person.basecamp.calls.length; i++) {
                c = person.basecamp.calls[i]
                if (c.module === "storage_module" && c.method === "downloadChunks"
                        && c.args && String(c.args[0]) === String(cid))
                    n++
            }
            return n
        }

        function titles(person) {
            var list = []
            var i
            for (i = 0; i < person.shelf.library.works.length; i++) list.push(person.shelf.library.works[i].title)
            return list.sort()
        }

        function has(person, count) {
            tryVerify(function () { return person.shelf.library.works.length === count }, 12000,
                      "shelf has " + count + " works, found " + person.shelf.library.works.length)
        }

        function plantDeliveryCatalog() {
            var listed = [
                {
                    id: "cat-cathedral",
                    title: "The Cathedral and the Bazaar",
                    author: "Eric S. Raymond",
                    kind: "book",
                    filename: "cathedral.pdf",
                    cid: "zDvDeliveryCathedral",
                    size: 976300,
                    addedAt: 1
                },
                {
                    id: "cat-farewell",
                    title: "Farewell to Westphalia",
                    author: "Jarrad Hope and Peter Ludlow",
                    kind: "book",
                    filename: "farewell.pdf",
                    cid: "zDvDeliveryFarewell",
                    size: 2276462,
                    addedAt: 2
                }
            ]
            var cid = network.put(Catalog.catalogDocument(listed))
            network.send(null, Catalog.TOPIC, Catalog.catalogPointer(cid))
            return cid
        }

        function staysEmpty(person, ms) {
            wait(ms || 1500)
            compare(person.shelf.library.works.length, 0, "Delivery catalog does not spawn cards")
            compare(person.shelf.shown.length, 0)
        }

        function test_a_fresh_install_is_empty_and_publishes_nothing() {
            var ana = install()
            running(ana)
            tryVerify(function () { return network.historyReads > 0 && ana.basecamp.pending.length === 0 }, 5000,
                      "it has asked what it missed")
            // Longer than the wait before a merged list would be published.
            wait(7000)

            compare(ana.shelf.library.works.length, 0)
            compare(ana.shelf.shown.length, 0)
            compare(ana.shelf.emptyTitle(), "Nothing on the shelf yet")
            verify(ana.shelf.emptyBody().indexOf("Choose a file") === 0)
            compare(ana.shelf.networkLine(), "Logos Storage: running · Logos Delivery: running")

            compare(Object.keys(network.files).length, 0, "nothing was uploaded")
            compare(network.history.length, 0, "nothing was announced")
            compare(ana.basecamp.downloads, 0, "no catalog was fetched")
        }

        function test_a_book_reaches_someone_else() {
            var ana = install()
            var ben = install()
            running(ana)
            running(ben)

            share(ana, "Река и град", "Ана Петровић", "file://" + file("river.txt", Bytes.utf8(story)))
            has(ana, 1)
            staysEmpty(ben, 1500)
            compare(ben.shelf.library.deliveryState, "running")
            compare(ana.shelf.shown[0].title, "Река и град")
        }

        function test_an_audiobook_arrives_byte_for_byte() {
            var sound = ""
            var i
            for (i = 0; i < 3000; i++) sound += String.fromCharCode(i % 256)

            var ana = install()
            var ben = install()
            running(ana)
            running(ben)
            share(ana, "Night Reading", "Cal", file("night.mp3", sound))
            has(ana, 1)
            staysEmpty(ben, 1500)

            var work = ana.shelf.shown[0]
            compare(work.kind, "audiobook")
            ana.shelf.open(work)
            // These bytes are not real audio, so the player reports that it
            // cannot play them. That only happens once the file has arrived.
            tryVerify(function () { return ana.shelf.listeningNote.indexOf("Fetching") < 0 }, 5000, "the file arrives")
            verify(ana.shelf.listeningPath.length > 0)
            verify(!/^\/(private\/)?tmp\/parallel-shelf-[^/]+$/.test(ana.shelf.listeningPath))
            compare(Bytes.readFile(ana.shelf.listeningPath), sound)
            ana.shelf.closePlayer()
            compare(ana.shelf.listening, null)
        }

        function test_a_pdf_is_shown_from_memory() {
            var ana = install()
            running(ana)
            share(ana, "Scanned Pages", "", file("scan.pdf", "%PDF-1.4 not really"))
            var work = ana.shelf.shown[0]
            compare(work.author, "Unknown author")
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 5000)
            compare(ana.shelf.readingPdf, "%PDF-1.4 not really")
            compare(ana.shelf.readingPages.length, 1)
            var scanDest = savedDest(ana)
            if (scanDest) {
                verify(!/^\/(private\/)?tmp\/parallel-shelf-[^/]+$/.test(scanDest))
                compare(Bytes.readFile(scanDest), "%PDF-1.4 not really")
            }
        }

        function test_a_pdf_is_saved_when_download_events_are_dropped() {
            var ana = install({ downloadEvents: false })
            running(ana)
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow",
                  file("farewell.pdf", "%PDF- dropped events"))
            var work = ana.shelf.shown[0]
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 8000,
                      "chunks still open the PDF when storageDownloadDone is dropped")
            compare(ana.shelf.readingPdf, "%PDF- dropped events")
            if (savedDest(ana))
                compare(Bytes.readFile(savedDest(ana)), "%PDF- dropped events")
        }

        function test_a_pdf_is_saved_when_exists_misses_a_local_cid() {
            var ana = install({ downloadEvents: false, existsAnswers: false })
            running(ana)
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow",
                  file("farewell-exists.pdf", "%PDF- exists missed"))
            var work = ana.shelf.shown[0]
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 8000,
                      "downloadChunks local=true opens the PDF when exists is false")
            compare(ana.shelf.readingPdf, "%PDF- exists missed")
            if (savedDest(ana))
                compare(Bytes.readFile(savedDest(ana)), "%PDF- exists missed")
        }

        function test_open_retrieves_with_downloadToUrl() {
            var ana = install()
            running(ana)
            share(ana, "Scanned Pages", "", file("scan-fetch.pdf", "%PDF-1.4 fetch"))
            var work = ana.shelf.shown[0]
            waitPersist(ana, work.cid, work.size)
            wipeHold(ana, work.cid)
            wipeRam(ana)
            dropSource(ana, work.cid)
            wipeSource(ana, work.cid)
            var before = ana.basecamp.calls.length
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 5000)
            compare(ana.shelf.readingPdf, "%PDF-1.4 fetch")
            if (savedDest(ana))
                compare(Bytes.readFile(savedDest(ana)), "%PDF-1.4 fetch")
            var i
            var urls = 0
            var chunks = 0
            var init = 0
            var uploadChunk = 0
            var fin = 0
            for (i = 0; i < ana.basecamp.calls.length; i++) {
                var c = ana.basecamp.calls[i]
                if (c.method === "uploadInit") init++
                if (c.method === "uploadChunk") uploadChunk++
                if (c.method === "uploadFinalize") fin++
                if (i < before) continue
                if (c.module === "storage_module" && c.method === "downloadToUrl") urls++
                if (c.module === "storage_module" && c.method === "downloadChunks") chunks++
            }
            verify(init >= 1, "catalog still uses uploadInit")
            compare(chunksFor(ana, work.cid), 0, "Open of a just-shared book does not call downloadChunks")
            compare(chunks, 0, "Open after Share does not call downloadChunks")
            verify(urls >= 1, "Open retrieves with downloadToUrl like muster")
            var dest = savedDest(ana)
            if (dest) {
                verify(dest.charAt(0) === "/", "dest is absolute")
                verify(!Catalog.isGlobalTmp(dest), "dest is not a global tmp path")
                verify(dest.indexOf("/parallel-shelf/") >= 0, "dest is under parallel-shelf/")
                verify(dest.indexOf(Catalog.destFileName(work)) === dest.length - Catalog.destFileName(work).length)
            }
            var dests = 0
            var existsCalls = 0
            for (i = 0; i < ana.basecamp.calls.length; i++) {
                if (i < before) continue
                if (ana.basecamp.calls[i].module === "parallel_shelf_core"
                        && ana.basecamp.calls[i].method === "fetchDest") dests++
                if (ana.basecamp.calls[i].module === "storage_module"
                        && ana.basecamp.calls[i].method === "exists") existsCalls++
            }
            compare(existsCalls, 0, "Open does not call exists")
            verify(ana.shelf.readingNote.indexOf("no writable dest") < 0)
            verify(ana.shelf.readingNote.indexOf("no file at") < 0)
            verify(ana.shelf.readingNote.indexOf("cannot save a fetched file") < 0)
        }

        function test_share_then_open_farewell_from_share_cache() {
            var pdf = dir + "/farewell-to-westphalia-foss-edition.pdf"
            var bytes = Bytes.readFile(pdf)
            verify(bytes && bytes.length === 2276462, "Farewell proof PDF is on disk")
            compare(bytes.substring(0, 5), "%PDF-")
            var pages = Catalog.pdfPageCount(bytes)
            compare(pages, 381)
            var ana = install()
            running(ana)
            compare(ana.shelf.library.works.length, 0, "1.0.0 starts with an empty shelf")
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", pdf)
            var work = ana.shelf.shown[0]
            compare(work.size, 2276462)
            var cid = work.cid
            waitPersist(ana, cid, 2276462)
            wipeRam(ana)
            wait(2100)
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 60000,
                      "Open after 2s shows Farewell from the core hold")
            compare(ana.shelf.readingPdf.length, 2276462)
            compare(ana.shelf.readingPdf.substring(0, 5), "%PDF-")
            compare(ana.shelf.readingPages.length, 381)
            compare(chunksFor(ana, cid), 0, "Open of a just-shared Farewell does not call downloadChunks")
            verify(fetchedMuster(ana), "Open used downloadToUrl or the Share hold")
            verify(!Catalog.safeSource(work.holdPath), "Share does not put holdPath on the QML card")
            var i
            for (i = 0; i < ana.basecamp.calls.length; i++) {
                if (ana.basecamp.calls[i].method === "downloadCancel")
                    verify(false, "Open never calls downloadCancel")
            }
        }

        function test_open_uses_view_lastShare_and_does_not_clear_it() {
            var pdf = dir + "/farewell-to-westphalia-foss-edition.pdf"
            var ana = install()
            running(ana)
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", pdf)
            var work = ana.shelf.shown[0]
            var cid = work.cid
            waitPersist(ana, cid, 2276462)
            compare(ana.shelf.library.lastShareOf(cid).length, 2276462,
                    "Share kept Farewell bytes in the view lastShare")
            compare(ana.shelf.library.lastShareCid, cid)
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 60000,
                      "Open paints Farewell from view lastShare")
            compare(ana.shelf.library.lastFetchFrom, "lastShare")
            compare(ana.shelf.readingPdf.length, 2276462)
            compare(ana.shelf.readingPages.length, 381)
            compare(ana.shelf.library.lastShareOf(cid).length, 2276462,
                    "Open did not clear lastShare")
            compare(ana.shelf.library.lastShareCid, cid)
            compare(ana.shelf.library.lastShareBytes.length, 2276462)
            verify(String(ana.shelf.library.lastShareFile[cid] || "").length > 0,
                   "Open did not clear lastShareFile")
            tryVerify(function () {
                var url = String(ana.shelf.readingPdfUrl)
                return relPagePng(url, 0)
                        && url.indexOf("/Downloads/") < 0
            }, 20000, "Open paints core page PNG, not ~/Downloads")
            tryVerify(function () {
                var item = ana.shelf.readerPanel.pdfEngine.item
                var pane = findChild(ana.shelf.readerPanel, "pdfPane")
                return ana.shelf.readerPanel.pdfEngine.status === Loader.Ready
                        && item
                        && item.pageCount === 381
                        && item.documentStatus === 2
                        && ana.shelf.readerPanel.pdfEngine.width > 200
                        && ana.shelf.readerPanel.pdfEngine.height > 200
                        && item.width > 200
                        && item.height > 200
                        && item.pageWidth > 200
                        && item.pageHeight > 200
                        && pane && pane.width > 200 && pane.height > 200
                        && item.status === Image.Ready
            }, 15000, "PDF Image is sized and painted")
            var cover = findChild(ana.shelf.readerPanel, "pdfCover")
            verify(!cover || !cover.visible, "title card is hidden when pageCount is 381")
            verify(String(ana.shelf.readingNote).indexOf("Choose file again") < 0)
            compare(chunksFor(ana, cid), 0)
        }

        function test_0_32_ignores_old_settings_category() {
            var old = Catalog.shelfDocument([{
                id: "old-cathedral",
                title: "The Cathedral and the Bazaar",
                author: "Eric S. Raymond",
                kind: "book",
                filename: "cathedral.pdf",
                cid: "zDvOldCathedralCid",
                size: 18,
                addedAt: 1,
                mine: true
            }, {
                id: "old-farewell",
                title: "Farewell to Westphalia",
                author: "Jarrad Hope and Peter Ludlow",
                kind: "book",
                filename: "farewell.pdf",
                cid: "zDvOldFarewellCid",
                size: 2276462,
                addedAt: 2,
                mine: true
            }])
            var oldMem = createTemporaryObject(oldMemoryMaker, bench)
            oldMem.setValue("shelf", old)
            oldMem.setValue("catalog", "zDvOldCatalogCid")
            oldMem.setValue("epoch", "0.28.0")
            oldMem.sync()
            var v29 = createTemporaryObject(v29MemoryMaker, bench)
            v29.setValue("shelf", old)
            v29.setValue("catalog", "zDvOldCatalogCid")
            v29.setValue("epoch", "0.29.0")
            v29.sync()
            var v30 = createTemporaryObject(v30MemoryMaker, bench)
            v30.setValue("shelf", old)
            v30.setValue("catalog", "zDvOldCatalogCid")
            v30.setValue("epoch", "0.30.0")
            v30.sync()
            var v31 = createTemporaryObject(v31MemoryMaker, bench)
            v31.setValue("shelf", old)
            v31.setValue("catalog", "zDvOldCatalogCid")
            v31.setValue("epoch", "0.31.0")
            v31.sync()
            var v32 = createTemporaryObject(v32MemoryMaker, bench)
            v32.setValue("shelf", old)
            v32.setValue("catalog", "zDvOldCatalogCid")
            v32.setValue("epoch", "0.32.0")
            v32.sync()
            var v33 = createTemporaryObject(v33MemoryMaker, bench)
            v33.setValue("shelf", old)
            v33.setValue("catalog", "zDvOldCatalogCid")
            v33.setValue("epoch", "0.33.0")
            v33.sync()
            var v34 = createTemporaryObject(v34MemoryMaker, bench)
            v34.setValue("shelf", old)
            v34.setValue("catalog", "zDvOldCatalogCid")
            v34.setValue("epoch", "0.34.0")
            v34.sync()
            var v35 = createTemporaryObject(v35MemoryMaker, bench)
            v35.setValue("shelf", old)
            v35.setValue("catalog", "zDvOldCatalogCid")
            v35.setValue("epoch", "0.35.0")
            v35.sync()
            var v36 = createTemporaryObject(v36MemoryMaker, bench)
            v36.setValue("shelf", old)
            v36.setValue("catalog", "zDvOldCatalogCid")
            v36.setValue("epoch", "0.36.0")
            v36.sync()
            var v37 = createTemporaryObject(v37MemoryMaker, bench)
            v37.setValue("shelf", old)
            v37.setValue("catalog", "zDvOldCatalogCid")
            v37.setValue("epoch", "0.37.0")
            v37.sync()
            var v38 = createTemporaryObject(v38MemoryMaker, bench)
            v38.setValue("shelf", old)
            v38.setValue("catalog", "zDvOldCatalogCid")
            v38.setValue("epoch", "0.38.0")
            v38.sync()
            var v39 = createTemporaryObject(v39MemoryMaker, bench)
            v39.setValue("shelf", old)
            v39.setValue("catalog", "zDvOldCatalogCid")
            v39.setValue("epoch", "0.39.0")
            v39.sync()
            var v40 = createTemporaryObject(v40MemoryMaker, bench)
            v40.setValue("shelf", old)
            v40.setValue("catalog", "zDvOldCatalogCid")
            v40.setValue("epoch", "0.40.1")
            v40.sync()
            var v41 = createTemporaryObject(v41MemoryMaker, bench)
            v41.setValue("shelf", old)
            v41.setValue("catalog", "zDvOldCatalogCid")
            v41.setValue("epoch", "0.41.0")
            v41.sync()
            var v42 = createTemporaryObject(v42MemoryMaker, bench)
            v42.setValue("shelf", old)
            v42.setValue("catalog", "zDvOldCatalogCid")
            v42.setValue("epoch", "0.42.0")
            v42.sync()
            var v43 = createTemporaryObject(v43MemoryMaker, bench)
            v43.setValue("shelf", old)
            v43.setValue("catalog", "zDvOldCatalogCid")
            v43.setValue("epoch", "0.43.0")
            v43.sync()
            var v44 = createTemporaryObject(v44MemoryMaker, bench)
            v44.setValue("shelf", old)
            v44.setValue("catalog", "zDvOldCatalogCid")
            v44.setValue("epoch", "0.44.0")
            v44.sync()
            var v45 = createTemporaryObject(v45MemoryMaker, bench)
            v45.setValue("shelf", old)
            v45.setValue("catalog", "zDvOldCatalogCid")
            v45.setValue("epoch", "0.45.0")
            v45.sync()
            var v46 = createTemporaryObject(v46MemoryMaker, bench)
            v46.setValue("shelf", old)
            v46.setValue("catalog", "zDvOldCatalogCid")
            v46.setValue("epoch", "0.46.0")
            v46.sync()
            var v47 = createTemporaryObject(v47MemoryMaker, bench)
            v47.setValue("shelf", old)
            v47.setValue("catalog", "zDvOldCatalogCid")
            v47.setValue("epoch", "0.47.0")
            v47.sync()
            var ana = install()
            running(ana)
            plantDeliveryCatalog()
            staysEmpty(ana, 1500)
            compare(ana.shelf.library.savedEpoch, "1.0.0")
            compare(ana.shelf.library.savedShelf, "")
            compare(ana.shelf.library.deliveryState, "running")
        }

        function test_open_from_hold_when_qml_lastShare_and_path_are_gone() {
            var pdf = dir + "/farewell-to-westphalia-foss-edition.pdf"
            var ana = install()
            running(ana)
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", pdf)
            var work = ana.shelf.shown[0]
            var cid = work.cid
            waitPersist(ana, cid, 2276462)
            wipeRam(ana)
            dropSource(ana, cid)
            ana.shelf.open(ana.shelf.library.works[0])
            tryVerify(function () { return openedPdf(ana) }, 60000,
                      "Open reads the core hold after QML lastShare and path are stripped")
            compare(ana.shelf.readingPdf.length, 2276462)
            compare(ana.shelf.readingPdf.substring(0, 5), "%PDF-")
            compare(ana.shelf.readingPages.length, 381)
            compare(chunksFor(ana, cid), 0)
            verify(fetchedMuster(ana), "Open used downloadToUrl or the Share hold")
        }

        function test_open_from_core_source_when_hold_and_qml_are_gone() {
            var pdf = dir + "/farewell-to-westphalia-foss-edition.pdf"
            var ana = install()
            running(ana)
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", pdf)
            var work = ana.shelf.shown[0]
            var cid = work.cid
            waitPersist(ana, cid, 2276462)
            var remembered = ""
            var asked = false
            ana.shelf.library.call("parallel_shelf_core", "readSource", [cid], function (r) {
                remembered = Catalog.pathOf(r && r.value)
                asked = true
            })
            tryVerify(function () { return asked && remembered === pdf }, 5000,
                      "Share stored the Choose-file path in parallel_shelf_core")
            wipeHold(ana, cid)
            wipeRam(ana)
            dropSource(ana, cid)
            ana.shelf.open(ana.shelf.library.works[0])
            tryVerify(function () { return openedPdf(ana) }, 60000,
                      "Open reads the core Choose-file path after QML and hold are gone")
            compare(ana.shelf.readingPdf.length, 2276462)
            compare(ana.shelf.readingPdf.substring(0, 5), "%PDF-")
            compare(ana.shelf.readingPages.length, 381)
            compare(ana.shelf.library.lastFetchFrom, "source")
            verify(String(ana.shelf.readingNote).indexOf("Choose file again") < 0)
        }

        function test_open_does_not_stay_on_opening() {
            var ana = install()
            running(ana)
            ana.shelf.library.works = [{
                id: "stuck-open",
                title: "The Cathedral and the Bazaar",
                author: "Eric S. Raymond",
                kind: "book",
                filename: "cathedral.pdf",
                cid: "zDvStuckOpeningCid",
                size: 976300,
                addedAt: 1,
                mine: true
            }]
            ana.shelf.library.ownCid("zDvStuckOpeningCid")
            tryVerify(function () { return ana.shelf.shown.length === 1 }, 2000)
            ana.shelf.open(ana.shelf.shown[0])
            tryVerify(function () {
                var note = String(ana.shelf.readingNote || "")
                return note.length > 0 && note.indexOf("Opening") !== 0
                        && note.indexOf("Fetching") !== 0
            }, 2000, "Open does not stay on Opening")
            compare(ana.shelf.readingPages.length, 0)
            compare(ana.shelf.readingNote, Catalog.CHOOSE_AGAIN)
            compare(chunksFor(ana, "zDvStuckOpeningCid"), 0)
        }

        function test_loading_bar_is_smooth() {
            var pdf = dir + "/farewell-to-westphalia-foss-edition.pdf"
            var ana = install()
            running(ana)
            var last = 0
            var dipped = false
            ana.shelf.library.share("Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", pdf)
            tryVerify(function () {
                var p = ana.shelf.library.shareProgress
                if (p + 0.0001 < last) dipped = true
                last = Math.max(last, p)
                return !ana.shelf.library.sharing && ana.shelf.library.works.length === 1
            }, 20000, "Share finishes without the bar going backwards")
            verify(!dipped, "Share loading bar never flickers backwards")
            verify(last >= 1, "Share bar reaches the end")
            wait(2100)
            var work = ana.shelf.library.works[0]
            waitPersist(ana, work.cid, 2276462)
            wipeRam(ana)
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 60000, "Open from the core hold")
            verify(fetchedMuster(ana), "Open used downloadToUrl or the Share hold")
            verify(ana.shelf.library.fetchProgress >= 0)
            compare(chunksFor(ana, work.cid), 0)
            verify(ana.shelf.fetchBar.height >= 6)
            var download = ana.shelf.downloadButton()
            var size = findChild(ana.shelf, "cardSize")
            var face = findChild(ana.shelf, "cardFace")
            verify(download && size && face)
            verify(download.parent !== face)
            verify(download.anchors.bottomMargin === 4)
            verify(String(download.text).indexOf("Download") === 0)
        }

        function test_open_from_thin_card_after_share() {
            var pdf = dir + "/farewell-to-westphalia-foss-edition.pdf"
            var ana = install()
            running(ana)
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", pdf)
            var work = ana.shelf.library.works[0]
            var thin = {
                id: work.id,
                title: work.title,
                author: work.author,
                kind: work.kind,
                filename: work.filename,
                cid: work.cid,
                size: work.size,
                addedAt: work.addedAt
            }
            ana.shelf.open(thin)
            tryVerify(function () { return openedPdf(ana) }, 60000,
                      "Open of a stripped card still uses Share bytes")
            compare(ana.shelf.readingPdf.length, 2276462)
            compare(ana.shelf.readingPdf.substring(0, 5), "%PDF-")
            compare(ana.shelf.readingPages.length, 381)
            compare(chunksFor(ana, work.cid), 0)
            verify(String(ana.shelf.readingNote).indexOf("Choose file again") < 0)
        }

        function test_share_then_open_second_book_from_share_cache() {
            var pdf = dir + "/farewell-to-westphalia-foss-edition.pdf"
            var ana = install()
            running(ana)
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", pdf)
            share(ana, "The Cathedral and the Bazaar", "Eric S. Raymond",
                  file("cathedral.pdf", "%PDF-1.4 cathedral"))
            compare(ana.shelf.library.works.length, 2, "two Shares are two cards")
            verify(ana.shelf.library.works[0].cid !== ana.shelf.library.works[1].cid)
            var i
            var work
            for (i = 0; i < ana.shelf.library.works.length; i++) {
                work = ana.shelf.library.works[i]
                ana.shelf.closeReader()
                ana.shelf.open(work)
                tryVerify(function () { return openedPdf(ana) }, 10000,
                          "Open shows " + work.title + " from the Share cache")
                compare(chunksFor(ana, work.cid), 0,
                        "Open of " + work.title + " does not call downloadChunks")
                compare(ana.shelf.readingPdf.substring(0, 5), "%PDF-")
                if (work.title === "Farewell to Westphalia") {
                    compare(ana.shelf.readingPdf.length, 2276462)
                    compare(ana.shelf.readingPages.length, 381)
                } else {
                    compare(ana.shelf.readingPdf, "%PDF-1.4 cathedral")
                }
            }
        }

        function test_open_after_restart_from_original_path() {
            var bytes = Bytes.readFile(dir + "/farewell-to-westphalia-foss-edition.pdf")
            verify(bytes && bytes.length === 2276462)
            var original = file("farewell-open-src.pdf", bytes)
            var ana = install()
            running(ana)
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", original)
            var work = ana.shelf.shown[0]
            waitPersist(ana, work.cid, 2276462)
            wipeRam(ana)
            compare(String(ana.shelf.library.shareHold[work.cid] || ""), "")
            ana.shelf.open(work)
            verify(ana.shelf.fetchBar.visible, "Opening shows a loading bar")
            tryVerify(function () { return openedPdf(ana) }, 60000,
                      "Open after restart shows Farewell from the core hold")
            compare(ana.shelf.readingPdf.length, 2276462)
            compare(ana.shelf.readingPdf.substring(0, 5), "%PDF-")
            compare(ana.shelf.readingPages.length, 381)
            compare(chunksFor(ana, work.cid), 0,
                    "Open from the core hold does not call downloadChunks")
            verify(String(ana.shelf.readingNote).indexOf("Opening") !== 0)
            verify(ana.shelf.fetchBar.width <= ana.shelf.readerPanel.width)
        }

        function test_open_from_core_hold_when_original_gone() {
            var bytes = Bytes.readFile(dir + "/farewell-to-westphalia-foss-edition.pdf")
            verify(bytes && bytes.length === 2276462)
            var original = file("farewell-hold-src.pdf", bytes)
            var ana = install()
            running(ana)
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", original)
            var work = ana.shelf.shown[0]
            waitPersist(ana, work.cid, 2276462)
            verify(rememberedShelf().indexOf("holdPath") < 0,
                   "Settings does not store holdPath")
            verify(rememberedShelf().indexOf(original) < 0,
                   "Settings does not store the Choose file path")
            deletePath(original)
            wipeRam(ana)
            work = ana.shelf.library.works[0]
            verify(!Catalog.safeSource(work.holdPath), "holdPath is not on the QML card")
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 60000,
                      "Open after the original path is gone shows Farewell from the core hold")
            compare(ana.shelf.readingPdf.length, 2276462)
            compare(ana.shelf.readingPdf.substring(0, 5), "%PDF-")
            compare(ana.shelf.readingPages.length, 381)
            compare(ana.shelf.readingPdf, bytes)
            compare(chunksFor(ana, work.cid), 0,
                    "Open from the core hold does not call downloadChunks")
            verify(String(ana.shelf.readingNote).indexOf("Logos Storage") < 0)
            verify(String(ana.shelf.readingNote).indexOf("Choose file again") < 0)
        }

        function test_open_fails_fast_when_source_is_missing() {
            var ana = install()
            running(ana)
            var gone = dir + "/no-such-open-source.pdf"
            ana.shelf.library.works = [{
                id: "missing-src",
                title: "Missing Path",
                author: "Ana",
                kind: "book",
                filename: "gone.pdf",
                cid: "zDvMissingPathCid",
                size: 2276462,
                addedAt: 1,
                mine: true,
                source: gone
            }]
            tryVerify(function () { return ana.shelf.shown.length === 1 }, 2000)
            ana.shelf.open(ana.shelf.shown[0])
            tryVerify(function () {
                var note = String(ana.shelf.readingNote || "")
                return note.length > 0 && note.indexOf("Opening") !== 0
                        && note.indexOf("Fetching") !== 0
            }, 2000, "missing path fails instead of staying on Opening")
            compare(ana.shelf.readingPages.length, 0)
            verify(String(ana.shelf.readingNote).indexOf("Opening") !== 0)
            compare(ana.shelf.readingNote, Catalog.CHOOSE_AGAIN)
            verify(String(ana.shelf.readingNote).indexOf("Logos Storage could not find it") < 0)
            compare(chunksFor(ana, "zDvMissingPathCid"), 0)
        }

        function test_open_fails_fast_when_readPiece_fails() {
            var pdf = file("read-fail.pdf", "%PDF- read fail")
            var ana = install()
            running(ana)
            share(ana, "Read Fail", "Ana", pdf)
            var work = ana.shelf.shown[0]
            wipeRam(ana)
            ana.basecamp.readPieceFails = true
            ana.shelf.open(work)
            tryVerify(function () {
                var note = String(ana.shelf.readingNote || "")
                return note.length > 0 && note.indexOf("Opening") !== 0
                        && note.indexOf("Fetching") !== 0
            }, 2000, "failed readPiece fails instead of staying on Opening")
            compare(ana.shelf.readingPages.length, 0)
            verify(String(ana.shelf.readingNote).indexOf("Opening") !== 0)
            compare(ana.shelf.readingNote, Catalog.CHOOSE_AGAIN)
            verify(String(ana.shelf.readingNote).indexOf("Logos Storage could not find it") < 0)
            compare(chunksFor(ana, work.cid), 0)
        }

        function test_shared_book_asks_to_choose_file_again_not_storage() {
            var ana = install()
            running(ana)
            ana.shelf.library.works = [{
                id: "mine-gone",
                title: "Shared Then Gone",
                author: "Ana",
                kind: "book",
                filename: "gone.pdf",
                cid: "zDvMineGoneCid",
                size: 2276462,
                addedAt: 1,
                mine: true
            }]
            tryVerify(function () { return ana.shelf.shown.length === 1 }, 2000)
            ana.shelf.open(ana.shelf.shown[0])
            tryVerify(function () {
                return String(ana.shelf.readingNote) === Catalog.CHOOSE_AGAIN
            }, 2000, "a Shared book with no path and no hold asks to Choose file again")
            compare(ana.shelf.readingPages.length, 0)
            verify(String(ana.shelf.readingNote).indexOf("Logos Storage could not find it") < 0)
            compare(chunksFor(ana, "zDvMineGoneCid"), 0,
                    "downloadChunks is not used for a CID this install Shared")
        }

        function test_open_from_catalog_only_card_after_share() {
            var bytes = Bytes.readFile(dir + "/farewell-to-westphalia-foss-edition.pdf")
            verify(bytes && bytes.length === 2276462)
            var original = file("farewell-locals.pdf", bytes)
            var ana = install()
            running(ana)
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", original)
            var work = ana.shelf.shown[0]
            waitPersist(ana, work.cid, 2276462)
            verify(work.mine)
            verify(!Catalog.safeSource(work.holdPath), "holdPath is not on the QML card")
            wipeRam(ana)
            var blank = {
                id: work.id,
                title: work.title,
                author: work.author,
                kind: work.kind,
                filename: work.filename,
                cid: work.cid,
                size: work.size,
                addedAt: work.addedAt,
                mine: true
            }
            ana.shelf.library.works = [blank]
            ana.shelf.open(ana.shelf.library.works[0])
            tryVerify(function () { return openedPdf(ana) }, 60000,
                      "Catalog-only Settings still Opens from the core hold")
            compare(ana.shelf.readingPdf.length, 2276462)
            compare(ana.shelf.readingPdf.substring(0, 5), "%PDF-")
            compare(ana.shelf.readingPages.length, 381)
            compare(chunksFor(ana, work.cid), 0)
            verify(String(ana.shelf.readingNote).indexOf("Logos Storage could not find it") < 0)
        }

        function test_local_shelf_card_never_calls_storage() {
            var ana = install()
            running(ana)
            ana.shelf.library.ownCid("zDvShelfOwnedCid")
            ana.shelf.library.works = [{
                id: "shelf-owned",
                title: "On The Shelf",
                author: "Ana",
                kind: "book",
                filename: "owned.pdf",
                cid: "zDvShelfOwnedCid",
                size: 2276462,
                addedAt: 1
            }]
            tryVerify(function () { return ana.shelf.shown.length === 1 }, 2000)
            ana.shelf.open(ana.shelf.shown[0])
            tryVerify(function () {
                return String(ana.shelf.readingNote) === Catalog.CHOOSE_AGAIN
            }, 2000, "a local-shelf card with no path and no hold asks to Choose file again")
            compare(ana.shelf.readingPages.length, 0)
            verify(String(ana.shelf.readingNote).indexOf("Logos Storage") < 0)
            verify(String(ana.shelf.notice).indexOf("Logos Storage") < 0)
            compare(chunksFor(ana, "zDvShelfOwnedCid"), 0)
        }

        function test_download_is_on_the_bottom_of_the_card() {
            var ana = install()
            running(ana)
            share(ana, "Card Bottom", "Ana", file("card-bottom.pdf", "%PDF- bottom"))
            tryVerify(function () { return ana.shelf.shown.length === 1 }, 2000)
            wait(80)
            var btn = ana.shelf.downloadButton()
            var face = findChild(ana.shelf, "cardFace")
            var size = findChild(ana.shelf, "cardSize")
            var bar = ana.shelf.cardBar()
            verify(btn, "Download is on the plank")
            verify(face)
            verify(size)
            verify(btn.visible)
            verify(ana.shelf.addButton.visible)
            verify(btn.parent !== face)
            verify(btn.y > 80, "Download sits on the plank under the book")
            verify(String(btn.text).indexOf("Download") === 0)
            if (bar) {
                compare(bar.parent, face)
                verify(bar.y > 80, "Download bar sits on the cover")
            }
        }

        function test_download_writes_farewell_to_downloads() {
            var pdf = dir + "/farewell-to-westphalia-foss-edition.pdf"
            var bytes = Bytes.readFile(pdf)
            verify(bytes && bytes.length === 2276462)
            var ana = install()
            running(ana)
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", pdf)
            var work = ana.shelf.shown[0]
            waitPersist(ana, work.cid, 2276462)
            wipeRam(ana)
            var destDir = ana.shelf.library.downloadsDir()
            verify(destDir.length > 0)
            var dest = destDir + "/" + Catalog.saveName(work)
            var savedPath = ""
            ana.shelf.library.saveReady.connect(function (w, path) { savedPath = path })
            ana.shelf.download(work)
            tryVerify(function () { return ana.shelf.savePicker.picking }, 3000,
                      "Download opens the in-app folder list")
            verify(ana.shelf.savePicker.saveFolder)
            verify(ana.shelf.addButton.visible)
            ana.shelf.savePicker.folderChosen(destDir)
            tryVerify(function () {
                var bar = ana.shelf.cardBar()
                var btn = ana.shelf.downloadButton()
                var size = findChild(ana.shelf, "cardSize")
                return !!(ana.shelf.library.saveBusy && bar && btn && size
                          && bar.visible)
            }, 3000, "Download bar shows on the cover while Download runs")
            var bar = ana.shelf.cardBar()
            var btn = ana.shelf.downloadButton()
            var size = findChild(ana.shelf, "cardSize")
            var face = findChild(ana.shelf, "cardFace")
            verify(bar)
            verify(btn)
            verify(size)
            verify(face)
            compare(bar.parent, face)
            verify(btn.parent !== face)
            verify(bar.y > 80, "Download bar sits on the cover")
            verify(bar.width < ana.shelf.width / 2, "Download bar is not across the shelf")
            verify(ana.shelf.addButton.visible)
            tryVerify(function () { return savedPath.length > 0 }, 20000, "Download wrote the file")
            compare(savedPath, dest)
            var got = Bytes.readFile(dest)
            compare(got.length, 2276462)
            compare(got.substring(0, 5), "%PDF-")
            compare(got, bytes)
            compare(chunksFor(ana, work.cid), 0, "Download after restart does not call downloadChunks")
        }

        function test_open_and_download_second_card_after_restart() {
            var pdf = dir + "/farewell-to-westphalia-foss-edition.pdf"
            var cathedral = file("cathedral-persist.pdf", "%PDF-1.4 cathedral")
            var ana = install()
            running(ana)
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", pdf)
            share(ana, "The Cathedral and the Bazaar", "Eric S. Raymond", cathedral)
            compare(ana.shelf.library.works.length, 2)
            var i
            var work
            for (i = 0; i < ana.shelf.library.works.length; i++) {
                work = ana.shelf.library.works[i]
                waitPersist(ana, work.cid, work.size)
            }
            wipeRam(ana)
            var destDir = ana.shelf.library.downloadsDir()
            for (i = 0; i < ana.shelf.library.works.length; i++) {
                work = ana.shelf.library.works[i]
                ana.shelf.closeReader()
                ana.shelf.open(work)
                tryVerify(function () { return openedPdf(ana) }, 20000,
                          "Open after restart shows " + work.title)
                compare(chunksFor(ana, work.cid), 0)
                compare(ana.shelf.readingPdf.substring(0, 5), "%PDF-")
                if (work.title === "Farewell to Westphalia") {
                    compare(ana.shelf.readingPdf.length, 2276462)
                    compare(ana.shelf.readingPages.length, 381)
                } else {
                    compare(ana.shelf.readingPdf, "%PDF-1.4 cathedral")
                }
                var dest = destDir + "/" + Catalog.saveName(work)
                ana.shelf.library.saveCopy(work, destDir)
                tryVerify(function () {
                    var got = Bytes.readFile(dest)
                    return got && got.length === ana.shelf.readingPdf.length
                }, 20000, "Download after restart wrote " + work.title)
                compare(Bytes.readFile(dest), ana.shelf.readingPdf)
            }
        }

        function test_open_saves_when_qml_dest_roots_are_empty() {
            var previous = StandardPaths.root
            StandardPaths.root = ""
            var ana = install()
            running(ana)
            share(ana, "Scanned Pages", "", file("scan-empty-roots.pdf", "%PDF- empty roots"))
            var work = ana.shelf.shown[0]
            compare(ana.shelf.library.destPath(work), "")
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 5000)
            compare(ana.shelf.readingPdf, "%PDF- empty roots")
            verify(ana.shelf.readingNote.indexOf("cannot save a fetched file") < 0)
            var dest = savedDest(ana)
            if (dest) {
                verify(!Catalog.isGlobalTmp(dest))
                verify(dest.charAt(0) === "/")
                compare(Bytes.readFile(dest), "%PDF- empty roots")
            }
            StandardPaths.root = previous
        }

        function test_open_shows_farewell_when_mkdir_and_standardpaths_are_empty() {
            var previous = StandardPaths.root
            StandardPaths.root = ""
            var pdf = dir + "/farewell-to-westphalia-foss-edition.pdf"
            var bytes = Bytes.readFile(pdf)
            verify(bytes && bytes.length === 2276462, "Farewell proof PDF is on disk")
            var ana = install({ mkdirEmpty: true })
            running(ana)
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", pdf)
            var work = ana.shelf.shown[0]
            compare(ana.shelf.library.destPath(work), "")
            waitPersist(ana, work.cid, 2276462)
            wipeRam(ana)
            wait(2100)
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 60000,
                      "Open shows Farewell from the core hold when mkdir and StandardPaths are empty")
            compare(ana.shelf.readingPdf.length, 2276462)
            compare(ana.shelf.readingPdf.substring(0, 5), "%PDF-")
            compare(ana.shelf.readingPages.length, 381)
            verify(fetchedMuster(ana), "Open used downloadToUrl or the Share hold")
            compare(chunksFor(ana, work.cid), 0)
            var dest = savedDest(ana)
            verify(!dest || dest.charAt(0) === "/", "dest file is optional")
            if (dest) verify(!Catalog.isGlobalTmp(dest))
            var i
            var cancels = 0
            for (i = 0; i < ana.basecamp.calls.length; i++) {
                if (ana.basecamp.calls[i].module === "storage_module"
                        && ana.basecamp.calls[i].method === "downloadCancel")
                    cancels++
            }
            compare(cancels, 0, "Open never calls downloadCancel")
            StandardPaths.root = previous
        }

        function test_open_never_calls_downloadCancel() {
            var ana = install()
            running(ana)
            share(ana, "Scanned Pages", "", file("scan-nocancel.pdf", "%PDF- no cancel"))
            var work = ana.shelf.shown[0]
            var before = ana.basecamp.calls.length
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 5000)
            var i
            var cancels = 0
            for (i = before; i < ana.basecamp.calls.length; i++) {
                if (ana.basecamp.calls[i].module === "storage_module"
                        && ana.basecamp.calls[i].method === "downloadCancel")
                    cancels++
            }
            compare(cancels, 0, "Open never calls downloadCancel")
            verify(ana.shelf.readingNote.indexOf("downloadCancel") < 0)
        }

        function test_open_shows_farewell_when_events_arrive_on_moduleEventReceived() {
            var previous = StandardPaths.root
            StandardPaths.root = ""
            var pdf = dir + "/farewell-to-westphalia-foss-edition.pdf"
            var bytes = Bytes.readFile(pdf)
            verify(bytes && bytes.length === 2276462, "Farewell proof PDF is on disk")
            var ana = install({ mkdirEmpty: true, hostEventsViaReceived: true })
            running(ana)
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", pdf)
            waitPersist(ana, ana.shelf.shown[0].cid, 2276462)
            wipeRam(ana)
            wait(2100)
            ana.shelf.open(ana.shelf.shown[0])
            tryVerify(function () { return openedPdf(ana) }, 60000,
                      "Open shows Farewell from the core hold when Mac events arrive on moduleEventReceived")
            compare(ana.shelf.readingPdf.length, 2276462)
            compare(ana.shelf.readingPdf.substring(0, 5), "%PDF-")
            compare(ana.shelf.readingPages.length, 381)
            verify(fetchedMuster(ana), "Open used downloadToUrl or the Share hold")
            compare(chunksFor(ana, ana.shelf.shown[0].cid), 0)
            var i
            var cancels = 0
            for (i = 0; i < ana.basecamp.calls.length; i++) {
                if (ana.basecamp.calls[i].method === "downloadCancel") cancels++
            }
            compare(cancels, 0, "Open never calls downloadCancel")
            StandardPaths.root = previous
        }

        function farewellWork(id) {
            return {
                id: id || "mwgvu2lo-9qytof",
                title: "Farewell to Westphalia",
                author: "Jarrad Hope and Peter Ludlow",
                filename: "farewell-to-westphalia-foss-edition.pdf",
                cid: "zDvZRwzkzrrYB6sS1rRpRLt4gBhc1pWoyTSjkfszfmj1seaYYLCZ",
                size: 2276462,
                kind: "book",
                addedAt: 1
            }
        }

        function test_open_fails_when_fetch_finishes_with_no_bytes() {
            var ana = install({ mkdirEmpty: true, downloadEmptyDone: true })
            running(ana)
            var cid = "zDvEmptyFetchNoBytesCid"
            wipeHold(ana, cid)
            network.files[cid] = Bytes.readFile(dir + "/farewell-to-westphalia-foss-edition.pdf")
            var work = farewellWork("empty-fetch-id")
            work.cid = cid
            ana.shelf.library.works = [work]
            ana.shelf.refresh()
            var t0 = new Date().getTime()
            ana.shelf.open(ana.shelf.shown[0])
            tryVerify(function () {
                return String(ana.shelf.readingNote) === Catalog.CHOOSE_AGAIN
            }, 2000, "no local bytes asks to Choose file again, not Storage")
            verify(new Date().getTime() - t0 < 2000)
            compare(ana.shelf.readingPdf, "")
            compare(ana.shelf.readingPages.length, 0)
            compare(chunksFor(ana, cid), 0)
        }

        function test_open_shows_farewell_when_dest_is_an_empty_file() {
            var pdf = dir + "/farewell-to-westphalia-foss-edition.pdf"
            var bytes = Bytes.readFile(pdf)
            verify(bytes && bytes.length === 2276462)
            var ana = install({ writeDestFails: true, downloadDoneBeforeChunks: true })
            running(ana)
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", pdf)
            var work = ana.shelf.shown[0]
            var dest = ana.shelf.library.destPath(work)
            if (dest && dest.charAt(0) === "/") {
                var folderReady = false
                ana.shelf.library.files.ensureDir(dest, function () { folderReady = true })
                tryVerify(function () { return folderReady }, 3000)
                var emptyReady = false
                Bytes.writeFile(dest, "", function () { emptyReady = true })
                tryVerify(function () { return emptyReady }, 3000)
            }
            waitPersist(ana, work.cid, 2276462)
            wipeRam(ana)
            wait(2100)
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 60000,
                      "Open shows Farewell from the core hold when dest is an empty file")
            compare(ana.shelf.readingPdf.length, 2276462)
            compare(ana.shelf.readingPdf.substring(0, 5), "%PDF-")
            compare(ana.shelf.readingPages.length, 381)
            verify(fetchedMuster(ana), "Open used downloadToUrl or the Share hold")
            compare(chunksFor(ana, work.cid), 0)
            verify(ana.shelf.readingNote.indexOf("empty file") < 0)
        }

        function test_three_farewells_collapse_to_one_card() {
            var ana = install()
            running(ana)
            ana.shelf.library.works = Catalog.merge([], [
                farewellWork("id1"),
                farewellWork("id2"),
                farewellWork("id3")
            ])
            ana.shelf.refresh()
            compare(ana.shelf.library.works.length, 1)
            compare(ana.shelf.shown.length, 1)
            compare(ana.shelf.library.works[0].title, "Farewell to Westphalia")
            compare(ana.shelf.library.works[0].id, "id1")
            compare(ana.shelf.library.works[0].cid,
                    "zDvZRwzkzrrYB6sS1rRpRLt4gBhc1pWoyTSjkfszfmj1seaYYLCZ")
        }

        function test_share_same_file_does_not_stack_copies() {
            var ana = install()
            running(ana)
            var path = file("farewell-copy.pdf", "%PDF- farewell copy")
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", path)
            compare(ana.shelf.library.works.length, 1)
            libraryShareAgain(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", path)
            compare(ana.shelf.library.works.length, 1)
            compare(ana.shelf.library.works[0].title, "Farewell to Westphalia")
        }

        function libraryShareAgain(person, title, author, path) {
            var library = person.shelf.library
            library.share(title, author, path)
            tryVerify(function () { return !library.sharing }, 5000, "second share finishes")
        }

        function test_open_retries_without_local_after_a_local_miss() {
            var cid = "zDvRetryLocalMissCid"
            var pdf = dir + "/farewell-to-westphalia-foss-edition.pdf"
            var bytes = Bytes.readFile(pdf)
            verify(bytes && bytes.length === 2276462)
            var ana = install({ mkdirEmpty: true, localChunksMiss: true })
            running(ana)
            wipeHold(ana, cid)
            network.files[cid] = bytes
            var work = farewellWork("retry-local-miss")
            work.cid = cid
            ana.shelf.library.works = [work]
            ana.shelf.refresh()
            var t0 = new Date().getTime()
            ana.shelf.open(ana.shelf.shown[0])
            tryVerify(function () {
                return String(ana.shelf.readingNote) === Catalog.CHOOSE_AGAIN
            }, 2000, "a catalog-only card with Storage bytes still asks to Choose file again")
            verify(new Date().getTime() - t0 < 2000, "Choose file again in under 2s")
            compare(ana.shelf.readingPages.length, 0)
            compare(chunksFor(ana, cid), 0, "Open never calls downloadChunks")
        }

        function test_open_does_not_replace_share_cid_via_manifests() {
            var ana = install()
            running(ana)
            share(ana, "The Cathedral and the Bazaar", "Eric S. Raymond",
                  file("cathedral-keep.pdf", "%PDF- cathedral keep"))
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow",
                  file("farewell-keep.pdf", "%PDF- farewell keep"))
            compare(ana.shelf.library.works.length, 2)
            var firstCid = ana.shelf.library.works[0].cid
            var secondCid = ana.shelf.library.works[1].cid
            verify(firstCid !== secondCid)
            var before = ana.basecamp.calls.length
            ana.shelf.open(ana.shelf.shown[0])
            tryVerify(function () { return openedPdf(ana) }, 5000)
            compare(ana.shelf.library.works.length, 2)
            compare(ana.shelf.library.works[0].cid, firstCid)
            compare(ana.shelf.library.works[1].cid, secondCid)
            var i
            var manifests = 0
            var chunks = 0
            for (i = before; i < ana.basecamp.calls.length; i++) {
                if (ana.basecamp.calls[i].module === "storage_module"
                        && ana.basecamp.calls[i].method === "manifests")
                    manifests++
                if (ana.basecamp.calls[i].module === "storage_module"
                        && ana.basecamp.calls[i].method === "downloadChunks")
                    chunks++
            }
            compare(manifests, 0, "Open of a just-shared book does not call manifests()")
            compare(chunks, 0, "Open of a just-shared book does not call downloadChunks")
        }

        function test_open_does_not_call_fetchDest() {
            var ana = install()
            running(ana)
            share(ana, "Scanned Pages", "", file("scan-qml-dest.pdf", "%PDF- qml dest"))
            var work = ana.shelf.shown[0]
            var before = ana.basecamp.calls.length
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 5000)
            var i
            var dests = 0
            for (i = before; i < ana.basecamp.calls.length; i++) {
                if (ana.basecamp.calls[i].module === "parallel_shelf_core"
                        && ana.basecamp.calls[i].method === "fetchDest") dests++
            }
            compare(dests, 0, "Open does not call fetchDest")
            compare(ana.shelf.readingPdf, "%PDF- qml dest")
            var dest = savedDest(ana)
            if (dest) {
                verify(!Catalog.isGlobalTmp(dest))
                verify(dest.indexOf("/parallel-shelf/") >= 0)
                verify(dest.charAt(0) === "/")
                verify(dest.indexOf(Catalog.destFileName(work)) === dest.length - Catalog.destFileName(work).length)
            }
            verify(ana.shelf.readingNote.indexOf("no writable dest") < 0)
            verify(ana.shelf.readingNote.indexOf("fetchDest") < 0)
            verify(ana.shelf.readingNote.indexOf("no file at") < 0)
        }

        function test_open_treats_context_already_initialized_as_non_fatal() {
            var ana = install({ contextAlreadyInitialized: true })
            running(ana)
            share(ana, "Scanned Pages", "", file("scan-init.pdf", "%PDF- already init"))
            var work = ana.shelf.shown[0]
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 5000)
            compare(ana.shelf.readingPdf, "%PDF- already init")
            if (savedDest(ana))
                compare(Bytes.readFile(savedDest(ana)), "%PDF- already init")
            verify(ana.shelf.readingNote.indexOf("Context already initialized") < 0)
        }

        function test_open_does_not_call_exists_even_when_exists_would_fail() {
            var ana = install({ existsError: "Context already initialized" })
            running(ana)
            share(ana, "Scanned Pages", "", file("scan-exists-err.pdf", "%PDF- exists err"))
            var work = ana.shelf.shown[0]
            var before = ana.basecamp.calls.length
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 5000)
            compare(ana.shelf.readingPdf, "%PDF- exists err")
            if (savedDest(ana))
                compare(Bytes.readFile(savedDest(ana)), "%PDF- exists err")
            var i
            var existsCalls = 0
            for (i = before; i < ana.basecamp.calls.length; i++) {
                if (ana.basecamp.calls[i].module === "storage_module"
                        && ana.basecamp.calls[i].method === "exists") existsCalls++
            }
            compare(existsCalls, 0, "Open does not call exists")
            verify(ana.shelf.readingNote.indexOf("Context already initialized") < 0)
            verify(ana.shelf.readingNote.indexOf("did not answer in time") < 0)
        }

        function proveStorageMethodSilent(person, method, args) {
            var lib = person.shelf.library
            var done = false
            var okFlag = false
            var saw = "unset"
            lib.lastCallError = ""
            lib.call("storage_module", method, args, function (r) {
                okFlag = !!(r && r.ok)
                saw = String(lib.lastCallError)
                done = true
            })
            tryVerify(function () { return done }, 3000, method + " answered")
            compare(okFlag, true, method + " treated as success")
            compare(saw, "", method + " must not set lastCallError")
            compare(lib.lastCallError, "")
        }

        function test_open_never_puts_context_already_initialized_in_lastCallError() {
            var ana = install({ contextAlreadyInitialized: true })
            running(ana)
            share(ana, "Scanned Pages", "", file("scan-noise.pdf", "%PDF- dest size"))
            tryVerify(function () { return !ana.shelf.library.job }, 8000, "catalog job finished")
            var work = ana.shelf.shown[0]
            var cid = work.cid
            proveStorageMethodSilent(ana, "exists", [cid])
            proveStorageMethodSilent(ana, "downloadChunks", [cid, false, Catalog.BLOCK, false, false])
            proveStorageMethodSilent(ana, "downloadManifest", [cid, false, false])
            var dest = ""
            var destDone = false
            dest = ana.shelf.library.destPath(work)
            destDone = dest.length > 0
            tryVerify(function () { return destDone && dest.length > 0 }, 3000, "qml dest")
            proveStorageMethodSilent(ana, "downloadToUrl",
                                     [cid, dest, true, Catalog.BLOCK, false, false])
            verify(Bytes.readFile(dest).indexOf("%PDF-") === 0, "retry dest already has size")

            waitPersist(ana, cid, work.size)
            wipeHold(ana, cid)
            wipeRam(ana)
            dropSource(ana, cid)
            wipeSource(ana, cid)
            var leaked = ""
            var before = ana.basecamp.calls.length
            ana.shelf.open(work)
            tryVerify(function () {
                var e = String(ana.shelf.library.lastCallError)
                if (e.toLowerCase().indexOf("already initialized") >= 0
                        || e.toLowerCase().indexOf("context already") >= 0)
                    leaked = e
                return openedPdf(ana)
            }, 5000)
            compare(leaked, "", "lastCallError never held Context already initialized")
            compare(ana.shelf.library.lastCallError, "")
            verify(ana.shelf.readingNote.indexOf("Context already initialized") < 0)
            compare(ana.shelf.readingPdf, "%PDF- dest size")
            if (savedDest(ana))
                compare(Bytes.readFile(savedDest(ana)), "%PDF- dest size")
            var i
            var urls = 0
            var chunks = 0
            var existsCalls = 0
            for (i = before; i < ana.basecamp.calls.length; i++) {
                if (ana.basecamp.calls[i].module === "storage_module"
                        && ana.basecamp.calls[i].method === "downloadToUrl") urls++
                if (ana.basecamp.calls[i].module === "storage_module"
                        && ana.basecamp.calls[i].method === "downloadChunks") chunks++
                if (ana.basecamp.calls[i].module === "storage_module"
                        && ana.basecamp.calls[i].method === "exists") existsCalls++
            }
            compare(chunks, 0, "Open of a just-shared book does not call downloadChunks")
            verify(urls >= 1, "Open retrieves with downloadToUrl like muster")
            compare(existsCalls, 0, "Open still does not call exists")
            if (savedDest(ana))
                verify(!Catalog.isGlobalTmp(savedDest(ana)))
        }

        function test_open_opens_dest_that_already_has_size_when_chunks_fail() {
            var ana = install({ contextAlreadyInitialized: true })
            running(ana)
            share(ana, "Scanned Pages", "", file("scan-ready.pdf", "%PDF- already there"))
            tryVerify(function () { return !ana.shelf.library.job }, 8000, "catalog job finished")
            var work = ana.shelf.shown[0]
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 5000)
            compare(ana.shelf.readingPdf, "%PDF- already there")
            if (savedDest(ana))
                compare(Bytes.readFile(savedDest(ana)), "%PDF- already there")
            verify(String(ana.shelf.library.lastCallError).indexOf("Context already initialized") < 0)
            verify(ana.shelf.readingNote.indexOf("downloadChunks") < 0)
        }

        function test_someone_who_opens_the_app_later_sees_the_shelf() {
            var ana = install()
            running(ana)
            share(ana, "Early Book", "Ana", file("early.txt", "early"))
            tryVerify(function () { return network.history.length === 1 }, 5000, "the catalog is announced")

            forget()
            var late = install()
            running(late)
            staysEmpty(late, 1500)
            verify(network.historyReads > 0, "it asked the store nodes")
            compare(late.shelf.library.deliveryState, "running")
        }

        function test_the_shelf_survives_a_restart_from_local_memory() {
            var ana = install()
            running(ana)
            share(ana, "Local Memory", "Ana", file("local.txt", "local"))
            tryVerify(function () { return rememberedShelf().indexOf("Local Memory") >= 0 }, 5000,
                      "Share writes Catalog.catalogDocument to Settings.shelf")
            memory.setValue("catalog", "")
            memory.sync()
            var late = install({ deliveryInstalled: false })
            has(late, 1)
            compare(titles(late), ["Local Memory"])
        }

        function test_the_shelf_is_remembered_without_delivery() {
            var ana = install()
            running(ana)
            share(ana, "Kept Book", "Ana", file("kept.txt", "kept"))
            tryVerify(function () { return remembered() !== "" }, 5000, "the catalog address is saved")

            var offline = install({ deliveryInstalled: false })
            has(offline, 1)
            tryVerify(function () { return offline.shelf.library.deliveryState === "down" }, 8000)
            compare(titles(offline), ["Kept Book"])
        }

        function test_two_people_adding_at_once_both_stay_on_the_shelf() {
            var ana = install()
            var ben = install()
            running(ana)
            running(ben)

            var first = file("first.txt", "first")
            var second = file("second.txt", "second")
            ana.shelf.library.share("First", "Ana", first)
            ben.shelf.library.share("Second", "Ben", second)
            has(ana, 1)
            has(ben, 1)
            compare(titles(ana), ["First"])
            compare(titles(ben), ["Second"])
        }

        function test_answers_may_arrive_in_either_order() {
            var ana = install({ resultBeforeAnswer: true })
            var ben = install({ base64Messages: true })
            running(ana)
            running(ben)
            share(ana, "Out of Order", "Ana", file("order.txt", "order"))
            has(ana, 1)
            staysEmpty(ben, 1500)
        }

        function test_a_hostile_catalog_cannot_do_much() {
            var ana = install()
            var ben = install()
            running(ana)
            running(ben)
            share(ana, "Honest Book", "Ana", file("honest.txt", "honest"))
            has(ana, 1)
            staysEmpty(ben, 800)

            var forged = {
                kind: "parallel-shelf", version: 1, works: [
                    { id: "honest-id", title: "Replaced", filename: "x.txt", cid: "zDvElsewhere", addedAt: 9 },
                    { id: "../../../home/ben/.bashrc", title: "Climb out", filename: "a.mp3", cid: "zDv1", addedAt: 8 },
                    { id: "prog", title: "A program", filename: "run.sh", cid: "zDv2", addedAt: 7 },
                    { id: "markup", title: "<b>Bold</b> <img src='http://example.com/x.png'>", filename: "m.txt", cid: "zDv3", addedAt: 6 },
                    { title: "No id", filename: "n.txt", cid: "zDv4" },
                    "not a work"
                ]
            }
            var cid = network.put(JSON.stringify(forged))
            network.send(null, Catalog.TOPIC, Catalog.catalogPointer(cid))
            network.send(null, Catalog.TOPIC, "not a pointer at all")
            network.send(null, "/some/other/topic", Catalog.catalogPointer("zDvIgnored"))
            staysEmpty(ben, 1500)
            compare(titles(ana), ["Honest Book"])
        }

        function test_an_oversized_catalog_is_dropped() {
            var ana = install()
            running(ana)
            var padding = ""
            while (padding.length < Catalog.CATALOG_BYTES_MAX + 70000) padding += "0123456789abcdef0123456789abcdef"
            var cid = network.put('{"kind":"parallel-shelf","works":[{"id":"big","title":"Big","filename":"b.txt","cid":"z"}],"pad":"' + padding + '"}')
            var small = network.put('{"kind":"parallel-shelf","works":[{"id":"small","title":"Small","filename":"s.txt","cid":"z"}]}')
            network.send(null, Catalog.TOPIC, Catalog.catalogPointer(cid))
            network.send(null, Catalog.TOPIC, Catalog.catalogPointer(small))
            staysEmpty(ana, 1500)
        }

        function test_a_flood_of_pointers_is_mostly_ignored() {
            var ana = install()
            running(ana)
            var i
            for (i = 0; i < 200; i++) network.send(null, Catalog.TOPIC, Catalog.catalogPointer("zDvFlood" + i))
            tryVerify(function () { return ana.basecamp.pending.length === 0 && !ana.shelf.library.job }, 10000)
            compare(ana.basecamp.downloads, 0, "Delivery catalogs are not fetched into the shelf")
            compare(ana.shelf.library.works.length, 0)
        }

        function test_a_book_that_is_gone_says_so() {
            var ana = install()
            running(ana)
            var cid = network.put('{"kind":"parallel-shelf","works":[{"id":"gone","title":"Gone","filename":"g.txt","cid":"zDvMissing"}]}')
            network.send(null, Catalog.TOPIC, Catalog.catalogPointer(cid))
            staysEmpty(ana, 1500)
        }

        function test_the_form_explains_what_is_wrong() {
            var ana = install()
            running(ana)
            var said = []
            ana.shelf.library.shareFailed.connect(function (why) { said.push(why) })
            var book = file("ok.txt", "ok")

            ana.shelf.library.share("  ", "Ana", book)
            ana.shelf.library.share("Title", "Ana", "")
            ana.shelf.library.share("Title", "Ana", "books/ok.txt")
            ana.shelf.library.share("Title", "Ana", file("setup.exe", "MZ"))
            compare(said, [
                "Give it a title.",
                "Choose a file.",
                "Use the full path to the file, starting with /.",
                "That file type is not supported. Use txt, md, pdf, mp3, m4a or ogg."
            ])
            compare(ana.shelf.library.works.length, 0)

            ana.shelf.library.share("Title", "Ana", dir + "/does-not-exist.txt")
            tryVerify(function () { return said.length === 5 }, 5000, "a missing file is reported")
            verify(!ana.shelf.library.sharing)
        }

        function test_search_narrows_the_shelf() {
            var ana = install()
            running(ana)
            share(ana, "River Walks", "Nia", file("walks.txt", "walks"))
            share(ana, "Night Reading", "Cal", file("reading.mp3", "sound"))
            ana.shelf.query = "nia"
            ana.shelf.refresh()
            compare(ana.shelf.shown.length, 1)
            compare(ana.shelf.shown[0].title, "River Walks")
            ana.shelf.query = "audiobook"
            ana.shelf.refresh()
            compare(ana.shelf.shown[0].title, "Night Reading")
            ana.shelf.query = "nothing like this"
            ana.shelf.refresh()
            compare(ana.shelf.emptyTitle(), "Nothing matches that search")
        }

        function test_without_storage_nothing_is_added() {
            var ana = install({ storageInstalled: false })
            tryVerify(function () { return ana.shelf.library.storageState === "down" }, 5000)
            var said = ""
            ana.shelf.library.shareFailed.connect(function (why) { said = why })
            ana.shelf.library.share("Title", "Ana", file("nostorage.txt", "x"))
            compare(said, "Logos Storage is not running, so nothing can be added.")
            verify(ana.shelf.emptyBody().indexOf("Logos Storage is not running") === 0)
        }

        function test_a_two_megabyte_pdf_is_shared() {
            var pdf = dir + "/farewell-to-westphalia-foss-edition.pdf"
            var ana = install()
            running(ana)
            var library = ana.shelf.library
            tryVerify(function () {
                return library.files && typeof library.files.fileSize === "function"
            }, 3000, "FileBytes loaded in the view")
            var got = -2
            library.files.stat(pdf, function (n) { got = n })
            tryVerify(function () { return got === 2276462 }, 5000, "core fileSize of the PDF")

            var t0 = Date.now()
            library.share("Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", pdf)
            tryVerify(function () { return !library.sharing && library.works.length === 1 }, 20000,
                      "the 2.2 MB PDF is on the shelf")
            var ms = Date.now() - t0
            console.log("PDF_SHARE bytes=2276462 ms=" + ms)
            compare(library.works[0].title, "Farewell to Westphalia")
            compare(library.works[0].author, "Jarrad Hope and Peter Ludlow")
            compare(library.works[0].size, 2276462)
            compare(network.files[library.works[0].cid].length, 2276462)
            compare(ana.basecamp.firstFileChunk, "%PDF-")
        }

        function test_share_from_downloads_succeeds_when_stageShare_fails() {
            var pdf = dir + "/Users/unexpectedr/Downloads/farewell-to-westphalia-foss-edition.pdf"
            var ana = install({ stageShareFails: true })
            running(ana)
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", pdf)
            compare(ana.shelf.library.works.length, 1)
            compare(ana.shelf.library.works[0].title, "Farewell to Westphalia")
            compare(ana.shelf.library.works[0].size, 2276462)
            compare(network.files[ana.shelf.library.works[0].cid].length, 2276462)
            compare(ana.basecamp.firstFileChunk, "%PDF-")
            var i
            var uploadUrl = 0
            var uploadPath = ""
            for (i = 0; i < ana.basecamp.calls.length; i++) {
                if (ana.basecamp.calls[i].module === "storage_module"
                        && ana.basecamp.calls[i].method === "uploadUrl") {
                    var up = String(ana.basecamp.calls[i].args[0] || "")
                    if (up.indexOf("farewell-to-westphalia") >= 0
                            || up.indexOf("/Downloads/") >= 0) {
                        uploadUrl++
                        uploadPath = up
                        compare(ana.basecamp.calls[i].args[1], 65536)
                        compare(ana.basecamp.calls[i].args[2], true)
                    }
                }
            }
            verify(uploadUrl >= 1, "Share still uploadUrl's the Downloads path Storage can open")
            verify(uploadPath.indexOf("/Downloads/") >= 0)
            compare(network.mistakes, [])
            var work = ana.shelf.library.works[0]
            ana.shelf.open(work)
            tryVerify(function () { return openedPdf(ana) }, 60000,
                      "Open same session shows Farewell after a failed stageShare")
            compare(ana.shelf.readingPdf.length, 2276462)
            compare(ana.shelf.readingPdf.substring(0, 5), "%PDF-")
            compare(ana.shelf.readingPages.length, 381)
            verify(fetchedMuster(ana), "Open used hold, original path, or downloadToUrl")
            verify(String(ana.shelf.readingNote).indexOf("Could not copy") < 0)
        }

        function test_share_calls_storage_uploadUrl() {
            var ana = install()
            running(ana)
            share(ana, "River", "Ana", file("river2.txt", "ok"))
            var i
            var init = 0
            var chunk = 0
            var fin = 0
            var uploadUrl = 0
            var manifests = 0
            var stage = 0
            var bind = 0
            var remember = 0
            for (i = 0; i < ana.basecamp.calls.length; i++) {
                compare(ana.basecamp.calls[i].module !== "parallel_shelf", true)
                if (ana.basecamp.calls[i].module === "parallel_shelf_core"
                        && ana.basecamp.calls[i].method === "stageShare")
                    stage++
                if (ana.basecamp.calls[i].module === "parallel_shelf_core"
                        && ana.basecamp.calls[i].method === "writeHold")
                    bind++
                if (ana.basecamp.calls[i].module === "parallel_shelf_core"
                        && ana.basecamp.calls[i].method === "rememberSource")
                    remember++
                if (ana.basecamp.calls[i].module !== "storage_module") continue
                if (ana.basecamp.calls[i].method === "uploadInit") init++
                if (ana.basecamp.calls[i].method === "uploadChunk") chunk++
                if (ana.basecamp.calls[i].method === "uploadFinalize") fin++
                if (ana.basecamp.calls[i].method === "uploadUrl") {
                    uploadUrl++
                    var upPath = String(ana.basecamp.calls[i].args[0] || "")
                    verify(upPath.indexOf("/Downloads/") < 0, "uploadUrl is not the Downloads path")
                    compare(ana.basecamp.calls[i].args[1], 65536)
                    compare(ana.basecamp.calls[i].args[2], true)
                }
                if (ana.basecamp.calls[i].method === "manifests") manifests++
            }
            verify(uploadUrl >= 1, "Share uses storage_module.uploadUrl like muster")
            verify(stage >= 1, "Share copies the Choose file through parallel_shelf_core.stageShare")
            verify(bind >= 1, "Share binds the staged copy with writeHold")
            verify(remember >= 1, "Share stores the Choose-file path in parallel_shelf_core.rememberSource")
            verify(init >= 1, "catalog still uses uploadInit")
            verify(chunk >= 1, "catalog still uses uploadChunk")
            verify(fin >= 1, "catalog still uses uploadFinalize")
            compare(manifests, 0, "Share does not poll manifests()")
        }

        function test_share_finishes_when_upload_events_never_arrive() {
            var ana = install({ uploadEvents: false })
            running(ana)
            share(ana, "Quiet File", "Ana", file("quiet.txt", "ok"))
            compare(ana.shelf.library.works.length, 1)
            compare(ana.shelf.library.works[0].title, "Quiet File")
        }

        function test_choose_file_opens_the_view_list() {
            var ana = install()
            running(ana)
            ana.shelf.adding = true
            wait(80)
            verify(ana.shelf.uploadPanel.chooseButton.visible)
            mouseClick(ana.shelf.uploadPanel.chooseButton)
            wait(80)
            compare(ana.basecamp.pickFileCalled, false)
            if (ana.shelf.uploadPanel.hasDialog)
                verify(ana.shelf.uploadPanel.picking)
        }

        function test_choose_file_starts_in_a_real_folder() {
            var ana = install()
            running(ana)
            var book = dir + "/farewell-to-westphalia-foss-edition.pdf"
            ana.shelf.adding = true
            wait(80)
            ana.shelf.uploadPanel.setSource(book)
            compare(ana.shelf.uploadPanel.pathInput.text, book)
            mouseClick(ana.shelf.uploadPanel.chooseButton)
            tryVerify(function () {
                return ana.shelf.uploadPanel.picking && ana.shelf.uploadPanel.pickerHere === "/tmp/parallel-shelf-tests"
            }, 3000, "the list opens in the folder that holds the file")
            if (ana.shelf.uploadPanel.listsInView) {
                tryVerify(function () {
                    return ana.shelf.uploadPanel.picker.pickNamed("farewell-to-westphalia-foss-edition.pdf") === book
                }, 3000, "the PDF is in the list and can be chosen")
                compare(ana.shelf.uploadPanel.pathInput.text, book)
            }
        }

        function test_the_path_field_keeps_the_full_file_name() {
            var ana = install()
            running(ana)
            ana.shelf.adding = true
            wait(80)
            var path = "/Users/unexpectedr/Downloads/farewell-to-westphalia-foss-edition.pdf"
            ana.shelf.uploadPanel.setSource(path)
            compare(ana.shelf.uploadPanel.pathInput.text, path)
            compare(ana.shelf.uploadPanel.pathInput.wrap, true)
        }

        function test_add_stays_when_storage_is_down() {
            var ana = install({ storageInstalled: false })
            tryVerify(function () { return ana.shelf.library.storageState === "down" }, 5000)
            verify(ana.shelf.addButton.visible)
            verify(ana.shelf.addButton.enabled)
            ana.shelf.adding = true
            verify(ana.shelf.uploadPanel.visible)
            verify(ana.shelf.uploadPanel.chooseButton.visible)
            verify(ana.shelf.uploadPanel.chooseButton.enabled)
            verify(ana.shelf.uploadPanel.shareButton.visible)
            verify(ana.shelf.uploadPanel.shareButton.enabled)
        }

        function test_outside_basecamp_the_shelf_says_it_cannot_connect() {
            var alone = createTemporaryObject(bareShelf, bench)
            tryVerify(function () { return alone.library.storageState === "down" }, 8000)
            compare(alone.emptyTitle(), "The shelf cannot be reached")
            compare(alone.shown.length, 0)
        }

        function goPdfPage(person, page) {
            person.shelf.readerPanel.page = page
            var root = person.shelf.readerPanel.pdfEngine.item
            if (root)
                root.page = page
        }

        function relPagePng(url, page) {
            url = String(url)
            var prefix = "page-" + page + "-"
            return url.indexOf(prefix) === 0
                    && url.indexOf(".png") === url.length - 4
                    && url.indexOf(":") < 0
                    && url.indexOf("/") < 0
                    && url.indexOf("file") < 0
                    && url.indexOf("data") < 0
        }

        function test_open_does_not_hang_when_renderPage_never_returns() {
            var proof = "/cursor/stores/bc-a13b448c-7ad4-47f5-a01c-a53f4b3ed883/internal/farewell-to-westphalia-foss-edition.pdf"
            var ana = install({ hangRenderPage: true })
            running(ana)
            ana.shelf.paintTimeoutMs = 400
            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", proof)
            var farewell = ana.shelf.library.works[0]
            waitPersist(ana, farewell.cid, 2276462)
            ana.shelf.open({
                id: farewell.id,
                title: farewell.title,
                author: farewell.author,
                kind: farewell.kind,
                filename: farewell.filename,
                cid: farewell.cid,
                size: farewell.size,
                addedAt: farewell.addedAt
            })
            tryVerify(function () { return openedPdf(ana) }, 60000,
                      "Open still loads Farewell bytes when render hangs")
            tryVerify(function () {
                var note = String(ana.shelf.readingNote)
                var item = ana.shelf.readerPanel.pdfEngine.item
                return note.indexOf("Could not draw this page") >= 0
                        && note.indexOf("pdftoppm is missing") < 0
                        && item
                        && String(item.failText).indexOf("Could not draw this page") >= 0
            }, 20000, "Open fails clearly instead of hanging on Rendering page N")
            verify(String(ana.shelf.readingPdfUrl).indexOf("data:") < 0)
            verify(String(ana.shelf.readingPdfUrl).indexOf("file://") < 0)
            ana.shelf.closeReader()
        }

        function test_screenshots_0_48_0() {
            var proof = "/cursor/stores/bc-a13b448c-7ad4-47f5-a01c-a53f4b3ed883/internal/farewell-to-westphalia-foss-edition.pdf"
            var bytes = Bytes.readFile(proof)
            verify(bytes && bytes.length === 2276462, "Farewell proof PDF is the store file")
            compare(bytes.substring(0, 5), "%PDF-")
            compare(Catalog.pdfPageCount(bytes), 381)
            var ana = install()
            running(ana)
            compare(ana.shelf.library.works.length, 0, "empty shelf before Delivery catalog")
            plantDeliveryCatalog()
            staysEmpty(ana, 1500)
            compare(ana.shelf.library.deliveryState, "running")
            compare(ana.shelf.emptyTitle(), "Nothing on the shelf yet")
            var destEmpty = "/cursor/stores/bc-a13b448c-7ad4-47f5-a01c-a53f4b3ed883/media/0.48.0-empty-shelf.png"
            var emptySaved = false
            ana.shelf.grabToImage(function (result) {
                emptySaved = result.saveToFile(destEmpty)
            })
            tryVerify(function () { return emptySaved }, 5000, "saved 0.48.0-empty-shelf.png")

            share(ana, "Farewell to Westphalia", "Jarrad Hope and Peter Ludlow", proof)
            compare(ana.shelf.library.works.length, 1)
            var farewell = ana.shelf.library.works[0]
            waitPersist(ana, farewell.cid, 2276462)
            compare(ana.shelf.library.lastShareOf(farewell.cid).length, 2276462,
                    "Share kept the PDF in view lastShare")
            ana.shelf.open({
                id: farewell.id,
                title: farewell.title,
                author: farewell.author,
                kind: farewell.kind,
                filename: farewell.filename,
                cid: farewell.cid,
                size: farewell.size,
                addedAt: farewell.addedAt
            })
            tryVerify(function () { return openedPdf(ana) }, 60000,
                      "Open Farewell from view lastShare")
            compare(ana.shelf.library.lastFetchFrom, "lastShare")
            compare(ana.shelf.library.lastShareOf(farewell.cid).length, 2276462,
                    "Open did not clear lastShare")
            compare(ana.shelf.readingPdf.length, 2276462)
            compare(ana.shelf.readingPdf.substring(0, 5), "%PDF-")
            compare(ana.shelf.readingPages.length, 381)
            compare(chunksFor(ana, farewell.cid), 0)
            verify(fetchedMuster(ana), "Open used view lastShare")
            verify(String(ana.shelf.readingNote).indexOf("Opening") !== 0)
            verify(String(ana.shelf.readingNote).indexOf("Choose file again") < 0)
            tryVerify(function () {
                var url = String(ana.shelf.readingPdfUrl)
                var cover = findChild(ana.shelf.readerPanel, "pdfCover")
                return relPagePng(url, 0)
                        && url.indexOf("/Downloads/") < 0
                        && ana.shelf.readerPanel.pdfEngine.status === Loader.Ready
                        && ana.shelf.readerPanel.pdfEngine.item
                        && ana.shelf.readerPanel.pdfEngine.item.pageCount === 381
                        && ana.shelf.readerPanel.pdfEngine.item.documentStatus === 2
                        && ana.shelf.readerPanel.pdfEngine.width > 200
                        && ana.shelf.readerPanel.pdfEngine.height > 200
                        && ana.shelf.readerPanel.pdfEngine.item.width > 200
                        && ana.shelf.readerPanel.pdfEngine.item.height > 200
                        && ana.shelf.readerPanel.pdfEngine.item.pageWidth > 200
                        && ana.shelf.readerPanel.pdfEngine.item.pageHeight > 200
                        && (!cover || !cover.visible)
            }, 20000, "core PNG Image loaded, no title card")
            wait(400)
            goPdfPage(ana, 11)
            tryVerify(function () {
                var item = ana.shelf.readerPanel.pdfEngine.item
                return ana.shelf.readerPanel.page === 11
                        && item
                        && item.currentPage === 11
            }, 10000, "PDF page Image currentPage is 11")
            goPdfPage(ana, 11)
            tryVerify(function () {
                var item = ana.shelf.readerPanel.pdfEngine.item
                var img = findChild(item, "pdfImage")
                var url = String(ana.shelf.readingPdfUrl)
                return item
                        && item.currentPage === 11
                        && item.status === Image.Ready
                        && relPagePng(url, 11)
                        && img
                        && img.status === Image.Ready
                        && img.paintedWidth > 100
                        && img.paintedHeight > 100
            }, 30000, "page 12 core PNG Image is Ready with body pixels")
            wait(1200)
            var destShare = "/cursor/stores/bc-a13b448c-7ad4-47f5-a01c-a53f4b3ed883/media/open-0.48.0-page12.png"
            var shareSaved = false
            ana.shelf.readerPanel.grabToImage(function (result) {
                shareSaved = result.saveToFile(destShare)
            })
            tryVerify(function () { return shareSaved }, 5000, "saved open-0.48.0-page12.png")
            ana.shelf.closeReader()
            var destDir = ana.shelf.library.downloadsDir()
            verify(destDir.length > 0)
            var destFile = destDir + "/" + Catalog.saveName(farewell)
            var savedPath = ""
            ana.shelf.library.saveReady.connect(function (w, path) { savedPath = path })
            ana.shelf.download(farewell)
            tryVerify(function () { return ana.shelf.savePicker.picking }, 3000,
                      "Download opens the in-app folder list")
            ana.shelf.savePicker.folderChosen(destDir)
            tryVerify(function () { return savedPath.length > 0 }, 20000, "Download wrote the file")
            compare(savedPath, destFile)
            var got = Bytes.readFile(destFile)
            compare(got.length, 2276462)
            compare(got.substring(0, 5), "%PDF-")
            compare(got, bytes)
        }
    }
}

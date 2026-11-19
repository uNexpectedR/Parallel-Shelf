// Tests for src/qml/catalog.js, the part of the app that decides what goes on the
// shelf. Run with: node --test

import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

// catalog.js is a QML script, not a module, so load it into a sandbox and
// read its functions back out.
const source = readFileSync(new URL("../src/qml/catalog.js", import.meta.url), "utf8")
const sandbox = {}
vm.runInNewContext(source, sandbox)
const c = sandbox

// Objects made inside the sandbox have a different prototype, so compare
// through JSON.
const same = (got, want) => assert.equal(JSON.stringify(got), JSON.stringify(want))

const base64 = (text) => Buffer.from(text, "utf8").toString("base64")
const bytes = (text) => Buffer.from(text, "utf8").toString("latin1")

const river = { id: "a1", title: "River", author: "Nia", filename: "river.txt", cid: "zDvRiver", size: 12, addedAt: 1 }
const night = { id: "b2", title: "Night", author: "Cal", filename: "night.mp3", cid: "zDvNight", size: 40, addedAt: 2 }

test("text is trimmed, flattened to one line and capped", () => {
  assert.equal(c.cleanText("  Ada \n  Lovelace  ", 80), "Ada Lovelace")
  assert.equal(c.cleanText("abcdef", 3), "abc")
  assert.equal(c.cleanText(null, 10), "")
  assert.equal(c.cleanText("a\u0000b", 10), "ab")
})

test("the file extension decides book or audiobook", () => {
  assert.equal(c.kindOf("notes.MD"), "book")
  assert.equal(c.kindOf("scan.pdf"), "book")
  assert.equal(c.kindOf("talk.mp3"), "audiobook")
  assert.equal(c.kindOf("setup.exe"), "")
  assert.equal(c.kindOf("no-extension"), "")
  assert.equal(c.isText("a.txt"), true)
  assert.equal(c.isText("a.pdf"), false)
})

test("a file address becomes an absolute path", () => {
  assert.equal(c.pathOf("file:///home/ana/My%20Book.txt"), "/home/ana/My Book.txt")
  assert.equal(c.pathOf("file://localhost/Users/ana/a.mp3"), "/Users/ana/a.mp3")
  assert.equal(c.pathOf("file:///Users/unexpectedr/Downloads/book.pdf"), "/Users/unexpectedr/Downloads/book.pdf")
  assert.equal(c.pathOf("file://unexpectedr/Downloads/book.pdf"), "/Users/unexpectedr/Downloads/book.pdf")
  assert.equal(c.pathOf("/tmp/a.txt"), "/tmp/a.txt")
  assert.equal(c.pathOf("file:///home/ana/%D0%9A%D1%9A%D0%B8%D0%B3%D0%B0.txt"), "/home/ana/Књига.txt")
  assert.equal(c.fileNameOf("file:///tmp/My%20Book.txt"), "My Book.txt")
})

test("the folder of a file is its parent directory", () => {
  assert.equal(c.folderOf("/Users/unexpectedr/Downloads/farewell-to-westphalia-foss-edition.pdf"),
               "/Users/unexpectedr/Downloads")
  assert.equal(c.folderOf("/Users/unexpectedr/Downloads"), "/Users/unexpectedr/Downloads")
  assert.equal(c.folderOf("/home/ana/book.txt"), "/home/ana")
  assert.equal(c.folderOf("relative.pdf"), "")
})

test("a fetched file name is <id>.<ext> under AppData/parallel-shelf", () => {
  assert.equal(c.destFileName(night), "b2.mp3")
  assert.equal(c.localName(night), "b2.mp3")
  assert.equal(c.destPath(night, "/Users/ana/Library/Application Support/app"),
               "/Users/ana/Library/Application Support/app/parallel-shelf/b2.mp3")
  assert.equal(c.destPath({ id: "../../etc/passwd", filename: "x.mp3" }, "/data"),
               "/data/parallel-shelf/etcpasswd.mp3")
  assert.equal(c.destPath({ id: "ok", filename: "scan.pdf" }, "/tmp"), "")
  assert.equal(c.destPath({ id: "ok", filename: "scan.pdf" }, "/var/tmp"), "")
  assert.equal(c.destPath({ id: "ok", filename: "scan.pdf" }, "/private/var/tmp"), "")
  assert.equal(c.destPath({ id: "ok", filename: "scan.pdf" }, ""), "")
  assert.equal(c.installRootFromQml("/Users/ana/Library/Application Support/Logos/LogosBasecamp/plugins/parallel_shelf/qml/Library.qml"),
               "/Users/ana/Library/Application Support/Logos/LogosBasecamp")
  assert.equal(c.installRootFromQml("/home/bob/.local/share/LogosBasecamp/plugins/parallel_shelf/qml/Main.qml"),
               "/home/bob/.local/share/LogosBasecamp")
  assert.equal(c.installRootFromQml("/tmp/plugins/parallel_shelf/qml/Library.qml"), "")
  assert.equal(c.isGlobalTmp("/tmp"), true)
  assert.equal(c.isGlobalTmp("/var/tmp"), true)
  assert.equal(c.isGlobalTmp("/private/tmp"), true)
  assert.equal(c.isGlobalTmp("/private/var/tmp/parallel-shelf/ok.pdf"), true)
  assert.equal(c.isGlobalTmp("/Users/ana/Library/Application Support/app"), false)
  assert.equal(c.isGlobalTmp("/home/ubuntu/.local/share/parallel-shelf"), false)
  assert.equal(c.localName({ id: "ok", filename: "x.mp3/../../y" }), "ok.pdf")
  assert.equal(c.localName({ id: "ok", filename: "run.sh" }), "ok.pdf")
  assert.equal(c.localName({ id: "///", filename: "x.mp3" }), "book.mp3")
  assert.equal(c.localName(null), "book.pdf")
})

test("Storage events unwrap from a string, a list, or the object", () => {
  const chunk = { success: true, sessionId: "zDvZ", chunk: "QQ==" }
  same(c.eventPayload(JSON.stringify(chunk)), chunk)
  same(c.eventPayload([JSON.stringify(chunk)]), chunk)
  same(c.eventPayload(chunk), chunk)
  assert.equal(c.eventPayload(null), null)
})

test("a PDF in memory becomes reader pages without a dest file", () => {
  assert.equal(c.isPdf("%PDF-1.4 x"), true)
  assert.equal(c.isPdf("not a pdf"), false)
  assert.equal(c.pdfPageCount("%PDF-1.4 no pages"), 0)
  assert.equal(c.pdfPageCount("%PDF-1.4 /Type/Pages /Type/Page /Type/Page"), 2)
  assert.equal(c.pdfPageCount("%PDF-1.4 /Type /Page /Type /Pages /Type /Page"), 2)
  assert.equal(c.pdfPages("%PDF-1.4 /Type/Page").length, 1)
  assert.equal(c.b64encode("Man"), "TWFu")
  assert.equal(c.pdfDataUrl("%PDF-x").indexOf("data:application/pdf;base64,"), 0)
})

test("merging two shelves keeps every work once, oldest first", () => {
  const merged = c.merge([river], [night, river])
  same(merged.map((w) => w.id), ["a1", "b2"])
  assert.equal(merged[0].kind, "book")
  assert.equal(merged[1].kind, "audiobook")
})

test("a later catalog cannot rewrite a work that is already listed", () => {
  const forged = { ...river, title: "Something else", cid: "zDvElsewhere" }
  const merged = c.merge([river], [forged])
  assert.equal(merged.length, 1)
  assert.equal(merged[0].title, "River")
  assert.equal(merged[0].cid, "zDvRiver")
})

test("re-uploads of the same CID collapse to the first card", () => {
  const farewell = {
    id: "id1",
    title: "Farewell to Westphalia",
    author: "Jarrad Hope and Peter Ludlow",
    filename: "farewell.pdf",
    cid: "zDvZRwzkzrrYB6sS1rRpRLt4gBhc1pWoyTSjkfszfmj1seaYYLCZ",
    size: 2276462,
    addedAt: 1,
  }
  const copies = [
    farewell,
    { ...farewell, id: "id2", addedAt: 2 },
    { ...farewell, id: "id3", addedAt: 3 },
  ]
  const merged = c.merge(copies, null)
  assert.equal(merged.length, 1)
  assert.equal(merged[0].id, "id1")
  assert.equal(merged[0].title, "Farewell to Westphalia")
  assert.equal(merged[0].cid, farewell.cid)
})

test("two different CIDs stay two cards even with the same title", () => {
  const a = { id: "a", title: "Farewell to Westphalia", author: "Jarrad Hope and Peter Ludlow",
              filename: "a.pdf", cid: "zDvA", addedAt: 1 }
  const b = { id: "b", title: "The Cathedral and the Bazaar", author: "Eric S. Raymond",
              filename: "b.pdf", cid: "zDvB", addedAt: 2 }
  const sameTitle = { id: "c", title: "Farewell to Westphalia", author: "Jarrad Hope and Peter Ludlow",
                      filename: "c.pdf", cid: "zDvC", addedAt: 3 }
  const merged = c.merge([a, b, sameTitle], null)
  assert.equal(merged.length, 3)
  assert.equal(merged.map((w) => w.cid).sort().join(","), "zDvA,zDvB,zDvC")
})

test("keepShare updates the matching CID and leaves a second CID as its own card", () => {
  const first = { id: "id1", title: "Farewell to Westphalia", author: "Jarrad Hope and Peter Ludlow",
                  filename: "old.pdf", cid: "zDvSame", size: 1, addedAt: 1 }
  const shared = { id: "id2", title: "Farewell to Westphalia", author: "Jarrad Hope and Peter Ludlow",
                   filename: "farewell.pdf",
                   cid: "zDvSame",
                   size: 2276462, addedAt: 2,
                   source: "/Users/me/Downloads/farewell.pdf" }
  const kept = c.keepShare([first], shared)
  assert.equal(kept.length, 1)
  assert.equal(kept[0].id, "id1")
  assert.equal(kept[0].cid, "zDvSame")
  assert.equal(kept[0].size, 2276462)
  assert.equal(kept[0].source, "/Users/me/Downloads/farewell.pdf")
  const cathedral = { id: "id3", title: "The Cathedral and the Bazaar", author: "Eric S. Raymond",
                      filename: "cathedral.pdf", cid: "zDvCathedral", size: 1000, addedAt: 3,
                      source: "/tmp/cathedral.pdf" }
  const two = c.keepShare(kept, cathedral)
  assert.equal(two.length, 2)
  assert.equal(two.map((w) => w.cid).sort().join(","), "zDvCathedral,zDvSame")
  assert.equal(two.find((w) => w.cid === "zDvCathedral").source, "/tmp/cathedral.pdf")
})

test("the local shelf is catalog-only; the published catalog does not store paths", () => {
  const work = { ...river, source: "/Users/me/Downloads/book.pdf", mine: true }
  const listed = c.merge([work], null, true)
  assert.equal(listed[0].source, "/Users/me/Downloads/book.pdf")
  assert.equal(listed[0].mine, true)
  const published = c.catalogDocument(listed, true)
  assert.equal(published.indexOf("/Users/me"), -1)
  assert.equal(published.indexOf("source"), -1)
  assert.equal(published.indexOf("mine"), -1)
  const leaked = {
    ...listed[0],
    dest: "/Users/unexpectedr/Library/Application Support/Logos/LogosBasecamp/parallel-shelf/mwl5ahqs-3t8nmi.pdf",
    holdPath: "/Users/unexpectedr/Library/Application Support/Logos/LogosBasecamp/hold",
  }
  const stripped = JSON.parse(c.catalogDocument([leaked], true))
  assert.equal(stripped.works[0].dest, undefined)
  assert.equal(stripped.works[0].source, undefined)
  assert.equal(stripped.works[0].holdPath, undefined)
  assert.equal(stripped.works[0].mine, undefined)
  assert.equal(JSON.stringify(stripped).indexOf("/Users/unexpectedr"), -1)
  const shelf = c.shelfDocument(listed)
  assert.equal(shelf.indexOf("/Users/me/Downloads/book.pdf"), -1)
  assert.equal(shelf.indexOf("source"), -1)
  assert.match(shelf, /"mine":true/)
  assert.equal(c.readCatalog(shelf, true)[0].source, undefined)
  assert.equal(c.readCatalog(shelf, true)[0].mine, true)
  assert.equal(c.readCatalog(published)[0].source, undefined)
  const hostile = c.readCatalog(JSON.stringify({
    kind: "parallel-shelf",
    version: 1,
    works: [{ ...listed[0], source: "/etc/passwd" }],
  }))
  assert.equal(hostile[0].source, undefined)
  const merged = c.merge(listed, hostile)
  assert.equal(merged[0].source, "/Users/me/Downloads/book.pdf")
})

test("merge of a published catalog does not strip a Share source or holdPath", () => {
  const shared = {
    id: "id1",
    title: "Farewell to Westphalia",
    author: "Jarrad Hope and Peter Ludlow",
    filename: "farewell.pdf",
    cid: "zDvKeep",
    size: 2276462,
    addedAt: 1,
    source: "/Users/me/Downloads/farewell.pdf",
    holdPath: "/Users/me/Library/Application Support/parallel-shelf-hold-zDvKeep",
    mine: true,
  }
  const kept = c.keepShare([], shared)
  assert.equal(kept[0].source, "/Users/me/Downloads/farewell.pdf")
  assert.equal(kept[0].holdPath,
               "/Users/me/Library/Application Support/parallel-shelf-hold-zDvKeep")
  const published = c.readCatalog(c.catalogDocument(kept))
  assert.equal(published[0].source, undefined)
  assert.equal(published[0].holdPath, undefined)
  const merged = c.merge(kept, published)
  assert.equal(merged.length, 1)
  assert.equal(merged[0].source, "/Users/me/Downloads/farewell.pdf")
  assert.equal(merged[0].holdPath,
               "/Users/me/Library/Application Support/parallel-shelf-hold-zDvKeep")
  assert.equal(merged[0].mine, true)
})

test("the local shelf does not store the hold path; the published catalog does not either", () => {
  const work = {
    ...river,
    source: "/Users/me/Downloads/book.pdf",
    holdPath: "/Users/me/Library/Application Support/parallel-shelf-hold-zDvZabc",
    mine: true,
  }
  const listed = c.merge([work], null, true)
  assert.equal(listed[0].holdPath,
               "/Users/me/Library/Application Support/parallel-shelf-hold-zDvZabc")
  assert.equal(listed[0].mine, true)
  const published = c.catalogDocument(listed)
  assert.equal(published.indexOf("holdPath"), -1)
  assert.equal(published.indexOf("Application Support"), -1)
  const shelf = c.shelfDocument(listed)
  assert.equal(shelf.indexOf("holdPath"), -1)
  assert.equal(shelf.indexOf("parallel-shelf-hold-zDvZabc"), -1)
  assert.equal(c.readCatalog(shelf, true)[0].holdPath, undefined)
  assert.equal(c.readCatalog(published)[0].holdPath, undefined)
  const hostile = c.readCatalog(JSON.stringify({
    kind: "parallel-shelf",
    version: 1,
    works: [{ ...listed[0], holdPath: "/etc/passwd" }],
  }))
  assert.equal(hostile[0].holdPath, undefined)
})

test("holdFile is a cache file named for the CID", () => {
  assert.equal(c.holdName("zDvZ-abc_1"), "zDvZ-abc_1")
  assert.equal(c.holdName("zDvZ/../etc"), "zDvZetc")
  assert.equal(c.holdFile("zDvZabc", "/tmp"), "")
  assert.equal(c.holdFile("zDvZabc", "/home/me/.cache"),
               "/home/me/.cache/parallel-shelf-hold-zDvZabc.bin")
  assert.equal(c.saveName({ filename: "farewell-to-westphalia-foss-edition.pdf" }),
               "farewell-to-westphalia-foss-edition.pdf")
  assert.equal(c.saveName({ filename: "/Users/me/Downloads/book.pdf" }), "book.pdf")
})

test("CHOOSE_AGAIN tells the reader to pick the file again", () => {
  assert.match(c.CHOOSE_AGAIN, /Choose file again/)
  assert.equal(c.CHOOSE_AGAIN.indexOf("Logos Storage"), -1)
})

test("shareHit needs %PDF- and the size for a PDF", () => {
  assert.equal(c.shareHit("", 8, "a.pdf"), false)
  assert.equal(c.shareHit("%PDF-xx", 8, "a.pdf"), false)
  assert.equal(c.shareHit("%PDF-xx", 7, "a.pdf"), true)
  assert.equal(c.shareHit("%PDF-xxxx", 7, "a.pdf"), true)
  assert.equal(c.shareHit("not-pdf", 7, "a.pdf"), false)
  assert.equal(c.shareHit("hello", 5, "a.txt"), true)
})

test("adoptStoredCid picks the local manifest CID of the same size", () => {
  const work = { id: "id1", title: "Farewell to Westphalia", filename: "f.pdf",
                 cid: "zDvStale", size: 2276462 }
  const found = [{ cid: "zDvZRwzkzrrYB6sS1rRpRLt4gBhc1pWoyTSjkfszfmj1seaYYLCZ", size: 2276462 }]
  assert.equal(c.adoptStoredCid(work, found).cid, found[0].cid)
  assert.equal(c.adoptStoredCid(work, [{ cid: "zDvStale", size: 2276462 }]).cid, "zDvStale")
  assert.equal(c.adoptStoredCid({ cid: "zDvMissing", size: 0, filename: "g.txt" }, found).cid,
               "zDvMissing")
})

test("entries that are not usable works are dropped", () => {
  const junk = [
    null,
    "text",
    { id: "x1", title: "", filename: "a.txt", cid: "z" },
    { id: "x2", title: "No address", filename: "a.txt" },
    { id: "x3", title: "Program", filename: "a.exe", cid: "z" },
    { id: "", title: "No id", filename: "a.txt", cid: "z" },
  ]
  same(c.merge(junk, null), [])
})

test("fields from a catalog are cleaned before they are kept", () => {
  const [work] = c.merge([{ id: "A1/..", title: "  Big\nTitle ", filename: "b.txt", cid: "z1", size: -5, addedAt: "soon" }], null)
  assert.equal(work.id, "a1")
  assert.equal(work.title, "Big Title")
  assert.equal(work.author, "Unknown author")
  assert.equal(work.size, 0)
  assert.equal(work.addedAt, 0)
})

test("a full shelf takes nothing new and loses nothing", () => {
  const full = []
  for (let i = 0; i < c.WORKS_MAX; i++) {
    full.push({ id: "w" + i, title: "Work " + i, filename: "w.txt", cid: "z" + i, addedAt: i })
  }
  const newer = { id: "late", title: "Late", filename: "l.txt", cid: "zLate", addedAt: c.WORKS_MAX + 1 }
  const merged = c.merge(full, [newer])
  assert.equal(merged.length, c.WORKS_MAX)
  assert.equal(merged.some((w) => w.id === "late"), false)
  assert.equal(merged.some((w) => w.id === "w0"), true)
})

test("a date in the future does not put a work first", () => {
  const future = { ...night, id: "f1", addedAt: Date.now() + 10 * c.DAY_MS }
  const today = { ...river, addedAt: Date.now() }
  same(c.merge([future, today], null).map((w) => w.id), ["a1", "f1"])
})

test("search looks at title, author and kind", () => {
  const [work] = c.merge([night], null)
  assert.equal(c.matches(work, "nig"), true)
  assert.equal(c.matches(work, "CAL"), true)
  assert.equal(c.matches(work, "audiobook"), true)
  assert.equal(c.matches(work, "river"), false)
  assert.equal(c.matches(work, ""), true)
})

test("a catalog document is plain ASCII and reads back unchanged", () => {
  const works = c.merge([{ ...river, title: "Књига о реци", author: "Ana 🌊" }, night], null)
  const text = c.catalogDocument(works)
  assert.match(text, /^[\x00-\x7e]*$/)
  same(c.readCatalog(text), works)
})

test("anything that is not a catalog is refused", () => {
  assert.equal(c.readCatalog("not json"), null)
  assert.equal(c.readCatalog("[]"), null)
  assert.equal(c.readCatalog('{"kind":"shelf","cid":"z"}'), null)
  assert.equal(c.readCatalog('{"kind":"parallel-shelf"}'), null)
  same(c.readCatalog('{"kind":"parallel-shelf","works":[]}'), [])
})

test("a pointer is read from text or from base64", () => {
  const pointer = c.catalogPointer("zDvCatalog")
  assert.equal(c.readPointer(pointer), "zDvCatalog")
  assert.equal(c.readPointer(base64(pointer)), "zDvCatalog")
  assert.equal(c.readPointer("hello"), "")
  assert.equal(c.readPointer(""), "")
  assert.equal(c.readPointer('{"kind":"shelf","cid":42}'), "")
  assert.equal(c.readPointer('{"kind":"other","cid":"z"}'), "")
})

test("splitting cuts text into pieces that join back", () => {
  same(c.split("abcdefg", 3), ["abc", "def", "g"])
  same(c.split("", 3), [""])
})

test("pages break at a line or a space and lose nothing", () => {
  const text = "one two three\nfour five six\nseven eight nine ten"
  const pages = c.paginate(text, 16)
  assert.equal(pages.join(""), text)
  assert.ok(pages.length > 1)
  for (const page of pages) assert.ok(page.length <= 16)
  assert.equal(pages[0], "one two three\n")
  same(c.paginate("", 16), [])
  assert.equal(c.paginate("a\r\nb", 16)[0], "a\nb")
})

test("module answers come in three shapes", () => {
  same(c.readResult('{"success":true,"value":"abc"}'), { ok: true, value: "abc", error: "" })
  same(c.readResult('{"success":false,"error":"nope"}'), { ok: false, value: null, error: "nope" })
  same(c.readResult({ success: true, value: 7 }), { ok: true, value: 7, error: "" })
  same(c.readResult(true), { ok: true, value: true, error: "" })
  same(c.readResult(false), { ok: false, value: false, error: "" })
  same(c.readResult("session-1"), { ok: true, value: "session-1", error: "" })
  assert.equal(c.readResult(null).ok, false)
  assert.equal(c.readResult(undefined).ok, false)
})

test("already started is not treated as a failure", () => {
  assert.equal(c.alreadyDone("Node already started"), true)
  assert.equal(c.alreadyDone("timeout"), false)
  assert.equal(c.alreadyDone(""), false)
  assert.equal(c.alreadyInitialized("Context already initialized"), true)
  assert.equal(c.alreadyInitialized("storage_module.exists: Context already initialized"), true)
  assert.equal(c.alreadyInitialized("storage_module.downloadToUrl: Context already initialized"), true)
  assert.equal(c.alreadyInitialized("storage_module.downloadChunks: Context already initialized"), true)
  assert.equal(c.alreadyInitialized("storage_module.downloadManifest: Context already initialized"), true)
  assert.equal(c.alreadyInitialized("cid not found"), false)
  assert.equal(c.storageNoise({ error: "Context already initialized" }, ""), true)
  assert.equal(c.storageNoise({ value: "Context already initialized" }, ""), true)
  assert.equal(c.storageNoise({ error: "" }, "storage_module.downloadChunks: Context already initialized"), true)
  assert.equal(c.storageNoise({ error: "not found" }, "not found"), false)
})

test("base64 decodes to bytes, with or without padding", () => {
  assert.equal(c.b64decode(base64("hello")), "hello")
  assert.equal(c.b64decode(base64("hello").replace(/=/g, "")), "hello")
  assert.equal(c.b64decode(base64("ab")), "ab")
  assert.equal(c.b64decode(""), "")
  const long = "x".repeat(20000)
  assert.equal(c.b64decode(base64(long)), long)
})

test("bytes decode as UTF-8", () => {
  const text = "Река тече. 川は流れる 🌊"
  assert.equal(c.utf8decode(bytes(text)), text)
  assert.equal(c.utf8decode(c.b64decode(base64(text))), text)
  assert.equal(c.utf8decode("\u00ef\u00bb\u00bfhi"), "hi")
  assert.equal(c.utf8decode("a\u00ffb"), "a\ufffdb")
  assert.equal(c.utf8decode("a\u00e2\u0082"), "a\ufffd\ufffd")
})

test("blockSizeFor matches backpack: 64 KiB, or 512 KiB over 128 KiB", () => {
  assert.equal(c.blockSizeFor(0), 65536)
  assert.equal(c.blockSizeFor(131072), 65536)
  assert.equal(c.blockSizeFor(131073), 524288)
  assert.equal(c.IPC_PIECE, 8192)
  assert.equal(c.chunkOf("abcdef", 2, 3), "cde")
  assert.equal(c.chunkOf("abcdef", 5, 8), "f")
  assert.equal(c.chunkOf("", 0, 65536), "")
  assert.equal(c.fileXhrAllowed(), false)
})

test("listedCids reads a Storage manifests() payload", () => {
  same(c.listedCids('[{"cid":"zDvA","datasetSize":12}]'), [{ cid: "zDvA", size: 12 }])
  same(c.listedCids(JSON.stringify({ success: true, value: '[{"cid":"zDvB","size":4}]' })),
       [{ cid: "zDvB", size: 4 }])
  same(c.listedCids(null), [])
})

test("sizes and times are short labels", () => {
  assert.equal(c.sizeLabel(0), "")
  assert.equal(c.sizeLabel(512), "512 B")
  assert.equal(c.sizeLabel(1500), "1.5 KB")
  assert.equal(c.sizeLabel(2400000), "2.4 MB")
  assert.equal(c.clock(0), "0:00")
  assert.equal(c.clock(65000), "1:05")
  assert.equal(c.clock(3725000), "1:02:05")
  assert.equal(c.clock(NaN), "0:00")
})

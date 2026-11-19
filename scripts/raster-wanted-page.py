#!/usr/bin/env python3
"""Raster Open/cover pages into qml/page-<cid>-N.png.

Watches Basecamp logs for dest skip / rel= / Image.source of page-<cid>-N.png.
Does not wait on hung QtRO. Always keeps page-*-0.png (shelf covers).
"""
import glob
import json
import os
import re
import subprocess
import time

HOME = os.path.expanduser("~")
QML = os.environ.get(
    "PARALLEL_SHELF_QML",
    os.path.join(
        HOME,
        "Library/Application Support/Logos/LogosBasecamp/plugins/parallel_shelf/qml",
    ),
)
BIN = os.environ.get(
    "PARALLEL_SHELF_BIN",
    os.path.join(
        HOME,
        "Library/Application Support/Logos/LogosBasecamp/modules/parallel_shelf_core/bin",
    ),
)
SOURCES = os.environ.get(
    "PARALLEL_SHELF_SOURCES",
    os.path.join(
        HOME,
        "Library/Application Support/Logos Basecamp/parallel-shelf/parallel-shelf-sources.json",
    ),
)
LOGDIR = os.environ.get(
    "PARALLEL_SHELF_LOGS",
    os.path.join(HOME, "Library/Application Support/Logos/LogosBasecamp/logs"),
)
LOGFILE = os.path.join(
    HOME, "Library/Application Support/Logos Basecamp/parallel-shelf/raster.log"
)
PPM = os.path.join(BIN, "pdftoppm")
# Only dest-skip / rel= / Image.source — not "Image retry 1 page-..." floods.
WANT = re.compile(
    r"(?:dest skip core \S+|rel=|Image\.source=)(page-([A-Za-z0-9_]+)-(\d+)\.png)"
)
WANTED_FILE = re.compile(r"^wanted-([A-Za-z0-9_]+)-(\d+)\.txt$")
COUNT_WANT = re.compile(r"count wanted ([A-Za-z0-9_]+) (\S+)")
FETCH_DISK = re.compile(r"fetch disk cid=(\S+) path=(\S+)")
OPEN_DEST = re.compile(r"(?:open dest|destFor) cid=(\S+) (?:path|dest)=(\S+)")
DOWNLOAD_DEST = re.compile(r"fetch downloadToUrl local=false (\S+)")
COVER_WANT = re.compile(r"cover wanted ([A-Za-z0-9_]+)")
KEY_PDF = {}
DONE = set()
CURRENT = ""
COUNTED = set()


def log(*args):
    line = " ".join(str(a) for a in args)
    print(line, flush=True)
    try:
        with open(LOGFILE, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


def page_count(pdf):
    try:
        data = open(pdf, "rb").read()
    except OSError:
        return 0
    return len(re.findall(br"/Type\s*/Page(?![s])", data))


def tiny_png(path, width=1):
    import struct
    import zlib

    n = max(1, min(int(width or 1), 10000))

    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    raw = b"\x00" + (b"\xff\xff\xff" * n)
    ihdr = struct.pack(">IIBBBBB", n, 1, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as f:
        f.write(png)


def write_count(key, pdf):
    if not key or not pdf or not os.path.isfile(pdf):
        return 0
    n = page_count(pdf)
    if n < 1:
        log("count fail", key, pdf)
        return 0
    txt = os.path.join(QML, "count-%s.txt" % key)
    marker = os.path.join(QML, "count-%s-%d.png" % (key, n))
    rel = os.path.join(QML, "count-%s.png" % key)
    have_txt = os.path.isfile(txt)
    have_marker = os.path.isfile(marker)
    have_rel = os.path.isfile(rel)
    if key in COUNTED and have_txt and have_marker and have_rel:
        return n
    try:
        with open(txt, "w") as f:
            f.write(str(n))
        if not have_marker:
            tiny_png(marker, 1)
        tiny_png(rel, n)
    except OSError as e:
        log("count write fail", e)
        return 0
    COUNTED.add(key)
    log("count", key, n, "pdf", os.path.basename(pdf))
    return n


def sources_map():
    try:
        with open(SOURCES, "r") as f:
            return json.load(f)
    except Exception:
        return {}


def hold_roots():
    return [
        os.path.join(HOME, "Library/Application Support/Logos Basecamp"),
        os.path.join(HOME, "Library/Application Support/Logos/LogosBasecamp"),
        HOME,
    ]


def cid_matches(cid, key):
    a = re.sub(r"[^A-Za-z0-9_]", "", cid or "")
    b = re.sub(r"[^A-Za-z0-9_]", "", key or "")
    if not a or not b:
        return False
    return a == b or a.startswith(b) or b.startswith(a)


def pdf_for_key(key):
    if key in KEY_PDF and os.path.isfile(KEY_PDF[key]):
        return KEY_PDF[key]
    for root in hold_roots():
        hold = os.path.join(root, "parallel-shelf-hold-%s.bin" % key)
        if os.path.isfile(hold) and os.path.getsize(hold) > 1000:
            KEY_PDF[key] = hold
            return hold
    src = sources_map()
    for cid, path in src.items():
        if path and os.path.isfile(path) and cid_matches(cid, key):
            KEY_PDF[key] = path
            return path
    return ""


def remember_pdf(key, pdf):
    if key and pdf and os.path.isfile(pdf):
        KEY_PDF[key] = pdf


def clear_stale(key):
    global CURRENT
    if key == CURRENT:
        return
    CURRENT = key
    keep = "page-%s-" % key
    for path in glob.glob(os.path.join(QML, "page-*.png")):
        name = os.path.basename(path)
        if name.startswith(keep):
            continue
        # Keep every book's cover so shelf cards stay painted.
        if re.search(r"-0\.png$", name):
            continue
        try:
            os.remove(path)
            log("cleared", path)
        except OSError as e:
            log("clear fail", path, e)
    DONE.clear()


def have(dest):
    return os.path.isfile(dest) and os.path.getsize(dest) > 1000


def raster(key, n):
    dest = os.path.join(QML, "page-%s-%d.png" % (key, n))
    if dest in DONE and have(dest):
        return
    if dest in DONE and not have(dest):
        DONE.discard(dest)
    if have(dest):
        DONE.add(dest)
        return
    pdf = pdf_for_key(key)
    if not pdf:
        log("no pdf for", key)
        return
    one = n + 1
    prefix = os.path.join(QML, "ppm-%s-%d" % (key[:12], n))
    env = os.environ.copy()
    env["DYLD_LIBRARY_PATH"] = BIN
    env["DYLD_FALLBACK_LIBRARY_PATH"] = BIN
    env["LD_LIBRARY_PATH"] = BIN
    try:
        r = subprocess.run(
            [PPM, "-png", "-singlefile", "-f", str(one), "-l", str(one),
             "-r", "72", pdf, prefix],
            env=env,
            capture_output=True,
            timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        log("fail", key, n, e)
        return
    src = prefix + ".png"
    if not os.path.isfile(src):
        matches = glob.glob(prefix + "*.png")
        src = matches[0] if matches else ""
    if src and src != dest:
        try:
            os.replace(src, dest)
        except OSError as e:
            log("replace fail", e)
            return
    if have(dest):
        DONE.add(dest)
        log("wrote", dest, os.path.getsize(dest), "pdf", os.path.basename(pdf),
            "rc", r.returncode)
    else:
        err = (r.stderr or b"")[-200:]
        log("fail", key, n, "rc", r.returncode, err)


def want(key, n):
    if not key:
        return
    if key not in COUNTED:
        write_count(key, pdf_for_key(key))
    clear_stale(key)
    raster(key, 0)
    raster(key, n)
    if n > 0:
        raster(key, n - 1)
    raster(key, n + 1)


def warm_covers():
    src = sources_map()
    for cid, path in src.items():
        if not path or not os.path.isfile(path):
            continue
        key = re.sub(r"[^A-Za-z0-9_]", "", cid)[:200]
        remember_pdf(key, path)
        write_count(key, path)
        raster(key, 0)
        log("warm cover", key, os.path.basename(path))


def scan_wanted():
    try:
        names = os.listdir(QML)
    except OSError:
        return
    for name in names:
        m = WANTED_FILE.match(name)
        if not m:
            continue
        key, n = m.group(1), int(m.group(2))
        dest = os.path.join(QML, "page-%s-%d.png" % (key, n))
        if have(dest):
            continue
        want(key, n)


def scan(text):
    for m in COVER_WANT.finditer(text):
        want(m.group(1), 0)
    for m in COUNT_WANT.finditer(text):
        key, pdf = m.group(1), m.group(2)
        remember_pdf(key, pdf)
        write_count(key, pdf)
        write_count(key, pdf_for_key(key))
        raster(key, 0)
    for m in FETCH_DISK.finditer(text):
        cid, pdf = m.group(1), m.group(2)
        key = re.sub(r"[^A-Za-z0-9_]", "", cid)[:200]
        remember_pdf(key, pdf)
        write_count(key, pdf)
        write_count(key, pdf_for_key(key))
        want(key, 0)
    for m in OPEN_DEST.finditer(text):
        cid, pdf = m.group(1), m.group(2)
        key = re.sub(r"[^A-Za-z0-9_]", "", cid)[:200]
        remember_pdf(key, pdf)
        write_count(key, pdf)
        want(key, 0)
    for m in DOWNLOAD_DEST.finditer(text):
        pdf = m.group(1)
        if pdf and os.path.isfile(pdf):
            remember_pdf(os.path.splitext(os.path.basename(pdf))[0], pdf)
    seen = set()
    for m in WANT.finditer(text):
        key, n = m.group(2), int(m.group(3))
        pair = (key, n)
        if pair in seen:
            continue
        seen.add(pair)
        want(key, n)


def latest_log():
    names = glob.glob(os.path.join(LOGDIR, "basecamp_*.log"))
    if not names:
        return ""
    names.sort(key=os.path.getmtime, reverse=True)
    return names[0]


def main():
    if not os.path.isdir(QML):
        raise SystemExit("qml dir missing: " + QML)
    if not os.path.isfile(PPM):
        raise SystemExit("pdftoppm missing: " + PPM)
    log("raster start qml", QML, "ppm", PPM)
    try:
        warm_covers()
    except Exception as e:
        log("warm fail", e)
    path = ""
    fh = None
    while True:
        try:
            cur = latest_log()
            if cur and cur != path:
                if fh:
                    fh.close()
                path = cur
                fh = open(path, "r", errors="replace")
                # New log: read a tail so dest-skip already written is not missed.
                try:
                    size = os.path.getsize(path)
                except OSError:
                    size = 0
                fh.seek(max(0, size - 1048576), os.SEEK_SET)
                if size > 1048576:
                    fh.readline()
                log("follow", path, "off", fh.tell())
            if fh:
                chunk = fh.read()
                if chunk:
                    scan(chunk)
            scan_wanted()
        except Exception as e:
            log("scan fail", e)
        time.sleep(0.05)


if __name__ == "__main__":
    main()

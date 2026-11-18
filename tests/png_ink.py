#!/usr/bin/env python3
"""Fail if a PNG is empty white (Mac 0.38.0 PdfPageView). Stdlib only."""
import struct
import sys
import zlib


def png_pixels(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("%s is not a PNG" % path)
    i = 8
    width = height = None
    raw = b""
    while i + 8 <= len(data):
        n = struct.unpack(">I", data[i : i + 4])[0]
        kind = data[i + 4 : i + 8]
        chunk = data[i + 8 : i + 8 + n]
        i += 12 + n
        if kind == b"IHDR":
            width, height, depth, color, *_ = struct.unpack(">IIBBBBB", chunk)
            if depth != 8 or color not in (2, 6):
                raise SystemExit("need 8-bit RGB(A) PNG, got depth=%s color=%s" % (depth, color))
        elif kind == b"IDAT":
            raw += chunk
        elif kind == b"IEND":
            break
    rows = zlib.decompress(raw)
    bpp = 4 if color == 6 else 3
    stride = width * bpp
    pixels = []
    o = 0
    prev = bytearray(stride)
    for _ in range(height):
        filt = rows[o]
        o += 1
        line = bytearray(rows[o : o + stride])
        o += stride
        if filt == 1:
            for x in range(stride):
                line[x] = (line[x] + (line[x - bpp] if x >= bpp else 0)) & 255
        elif filt == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif filt == 3:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + ((a + prev[x]) // 2)) & 255
        elif filt == 4:
            def paeth(a, b, c):
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                if pa <= pb and pa <= pc:
                    return a
                if pb <= pc:
                    return b
                return c
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                b = prev[x]
                c = prev[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + paeth(a, b, c)) & 255
        elif filt != 0:
            raise SystemExit("unsupported PNG filter %s" % filt)
        prev = line
        for x in range(0, stride, bpp):
            pixels.append((line[x], line[x + 1], line[x + 2]))
    return width, height, pixels


def main():
    path = sys.argv[1]
    width, height, pixels = png_pixels(path)
    total = len(pixels)
    ink = sum(1 for r, g, b in pixels if (r + g + b) / 3 < 180)
    ratio = ink / total if total else 0
    print("%s %sx%s ink=%s ratio=%.4f" % (path, width, height, ink, ratio))
    if width < 200 or height < 200:
        raise SystemExit("screenshot too small to be a reader page")
    if ink < 4000 or ratio < 0.01:
        raise SystemExit("page is empty white (Image did not show body text)")


if __name__ == "__main__":
    main()

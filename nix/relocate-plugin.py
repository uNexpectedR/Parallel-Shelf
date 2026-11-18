#!/usr/bin/env python3
"""Point the type:ui IComponent plugin at the host Qt, not /nix/store.

Basecamp already has Qt loaded. A plugin whose LC_LOAD_DYLIB / DT_RUNPATH
still names /nix/store/.../Qt*.framework cannot QPluginLoader on a user's
Mac. Relocate is necessary but not sufficient: a ui_qml qmldir `plugin`
never reaches dlopen (QmlSandbox).
"""
from __future__ import annotations

import os
import struct
import subprocess
import sys


MH_MAGIC_64 = 0xFEEDFACF
LC_LOAD_DYLIB = 0x0C
LC_ID_DYLIB = 0x0D
LC_LOAD_WEAK_DYLIB = 0x18
LC_RPATH = 0x1C | 0x80000000
LC_REEXPORT_DYLIB = 0x1B | 0x80000000


def _nul_pad(buf: bytearray, start: int, end: int, text: str) -> None:
    raw = text.encode("utf-8") + b"\0"
    if len(raw) > end - start:
        raise SystemExit(
            "relocated install name is longer than the original: %r needs %d, have %d"
            % (text, len(raw), end - start)
        )
    buf[start:start + len(raw)] = raw
    for i in range(start + len(raw), end):
        buf[i] = 0


def rewrite_macho_name(name: str) -> str | None:
    if "Qt" in name and ".framework/" in name:
        # /nix/store/.../QtQml.framework/Versions/A/QtQml
        parts = name.split("/")
        for p in parts:
            if p.endswith(".framework"):
                fw = p[: -len(".framework")]
                return "@rpath/%s.framework/Versions/A/%s" % (fw, fw)
    if "libc++" in name:
        return "/usr/lib/libc++.1.dylib"
    if "libintl" in name:
        return "@rpath/libintl.8.dylib"
    return None


def relocate_macho(path: str) -> list[str]:
    data = bytearray(open(path, "rb").read())
    magic = struct.unpack_from("<I", data, 0)[0]
    if magic != MH_MAGIC_64:
        raise SystemExit("%s: not a little-endian Mach-O 64 dylib (magic=%s)" % (path, hex(magic)))
    ncmds = struct.unpack_from("<I", data, 16)[0]
    off = 32
    changed: list[str] = []
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd in (LC_LOAD_DYLIB, LC_ID_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB, LC_RPATH):
            namoff = struct.unpack_from("<I", data, off + 8)[0]
            start = off + namoff
            end = off + cmdsize
            name = bytes(data[start:end]).split(b"\0", 1)[0].decode("utf-8", "replace")
            new = rewrite_macho_name(name)
            if new and new != name:
                _nul_pad(data, start, end, new)
                changed.append("%s -> %s" % (name, new))
                name = new
            # Nix Qt pulls gettext. Basecamp does not ship libintl next to
            # a view plugin; missing it must not fail dlopen.
            if "libintl" in name and cmd == LC_LOAD_DYLIB:
                struct.pack_into("<I", data, off, LC_LOAD_WEAK_DYLIB)
                changed.append("WEAK %s" % name)
        off += cmdsize
    if changed:
        open(path, "wb").write(data)
    return changed


def relocate_elf(path: str) -> list[str]:
    patchelf = os.environ.get("PATCHELF", "patchelf")
    old = subprocess.check_output([patchelf, "--print-rpath", path], text=True).strip()
    subprocess.check_call([patchelf, "--remove-rpath", path])
    if old:
        return ["RUNPATH %s -> (host Qt)" % old]
    return []


def relocate(path: str) -> list[str]:
    with open(path, "rb") as f:
        magic = f.read(4)
    if magic == b"\xcf\xfa\xed\xfe":
        return relocate_macho(path)
    if magic == b"\x7fELF":
        return relocate_elf(path)
    raise SystemExit("%s: not an ELF or Mach-O plugin" % path)


def load_names(path: str) -> list[str]:
    with open(path, "rb") as f:
        magic = f.read(4)
        rest = f.read()
    data = magic + rest
    if magic == b"\xcf\xfa\xed\xfe":
        ncmds = struct.unpack_from("<I", data, 16)[0]
        off = 32
        names = []
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack_from("<II", data, off)
            if cmd in (LC_LOAD_DYLIB, LC_ID_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB, LC_RPATH):
                namoff = struct.unpack_from("<I", data, off + 8)[0]
                name = data[off + namoff:off + cmdsize].split(b"\0", 1)[0].decode("utf-8", "replace")
                names.append(name)
            off += cmdsize
        return names
    if magic == b"\x7fELF":
        patchelf = os.environ.get("PATCHELF", "patchelf")
        try:
            rpath = subprocess.check_output([patchelf, "--print-rpath", path], text=True).strip()
        except subprocess.CalledProcessError:
            rpath = ""
        return [rpath] if rpath else []
    raise SystemExit("%s: not an ELF or Mach-O plugin" % path)


def assert_host_qt(path: str) -> None:
    bad = [n for n in load_names(path) if "/nix/store" in n]
    if bad:
        raise SystemExit("%s still names /nix/store: %s" % (path, bad))


def main(argv: list[str]) -> int:
    args = argv[1:]
    check_only = False
    if args and args[0] == "--check":
        check_only = True
        args = args[1:]
    if not args:
        print("usage: relocate-plugin.py [--check] <plugin> [<plugin>...]", file=sys.stderr)
        return 2
    for path in args:
        print("relocate-plugin:", path, file=sys.stderr)
        if not check_only:
            for line in relocate(path):
                print(" ", line, file=sys.stderr)
        assert_host_qt(path)
        for name in load_names(path):
            print("  uses", name, file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

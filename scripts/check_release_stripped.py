#!/usr/bin/env python3
"""Fail if a release APK/AAB ships a native library with debug info left in.

Why this exists: with --obfuscate, gen_snapshot prints

    Warning: The generated ELF library contains unobfuscated DWARF
    debugging information.

on every Android release build. Flutter deliberately leaves stripping to
the Android Gradle Plugin on Android (flutter_tools base/build.dart), so
the warning describes an intermediate libapp.so, not what ships: the
packaged copy is stripped and the DWARF goes to build/symbols/<version>.

The real risk is that stripping silently stops (a missing NDK, a changed
packaging option) and a bundle ships the original Dart names, undoing the
obfuscation. This check turns that from "a warning nobody reads" into a
failed build.

Usage: check_release_stripped.py <app.aab|app.apk> [...]
Exit codes: 0 all stripped, 1 debug info found, 2 bad input.
Standard library only.
"""

import struct
import sys
import zipfile

# Sections whose presence means the library was not stripped.
_DEBUG_PREFIX = ".debug"
_SYMTAB = ".symtab"


def _section_names(data: bytes) -> list[str]:
    if data[:4] != b"\x7fELF":
        raise ValueError("not an ELF file")
    is64 = data[4] == 2
    if is64:
        shoff = struct.unpack_from("<Q", data, 0x28)[0]
        shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x3A)
        name_fmt, off_fmt, off_at = "<I", "<Q", 24
    else:
        shoff = struct.unpack_from("<I", data, 0x20)[0]
        shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x2E)
        name_fmt, off_fmt, off_at = "<I", "<I", 16
    if shoff == 0 or shnum == 0:
        return []
    strtab = struct.unpack_from(off_fmt, data, shoff + shstrndx * shentsize + off_at)[0]
    names = []
    for i in range(shnum):
        name_off = struct.unpack_from(name_fmt, data, shoff + i * shentsize)[0]
        start = strtab + name_off
        names.append(data[start:data.index(b"\0", start)].decode("ascii", "replace"))
    return names


def check(path: str) -> list[str]:
    """Returns one problem line per unstripped library in [path]."""
    problems = []
    with zipfile.ZipFile(path) as archive:
        libs = [n for n in archive.namelist() if n.endswith(".so") and "/lib/" in "/" + n]
        if not libs:
            raise ValueError(f"{path}: no native libraries found")
        for name in sorted(libs):
            leftover = [
                s for s in _section_names(archive.read(name))
                if s.startswith(_DEBUG_PREFIX) or s == _SYMTAB
            ]
            if leftover:
                problems.append(f"{name}: {', '.join(leftover)}")
        print(f"{path}: {len(libs)} native libraries checked")
    return problems


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print("usage: check_release_stripped.py <app.aab|app.apk> [...]", file=sys.stderr)
        return 2
    problems = []
    for path in argv[1:]:
        try:
            problems += check(path)
        except (OSError, ValueError, zipfile.BadZipFile, struct.error) as error:
            print(f"error: {error}", file=sys.stderr)
            return 2
    if problems:
        print("error: native libraries still carry debug info (obfuscation undone):",
              file=sys.stderr)
        for line in problems:
            print(f"  {line}", file=sys.stderr)
        return 1
    print("OK: every native library is stripped; Dart symbols are only in build/symbols/.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

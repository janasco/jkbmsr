#!/usr/bin/env python3
"""Verify that an Android .aab/.apk supports 16 KB memory page sizes.

Google Play requires every app that targets Android 15+ to run on devices
with 16 KB memory pages (enforced since 2025-11-01). The requirement is
satisfied by the app's **64-bit** native libraries: 16 KB page-size devices
(arm64-v8a, x86_64) map ELF `PT_LOAD` segments using the segment's `p_align`,
which must therefore be at least 0x4000. A 0x1000 (4 KB) `p_align` is the
classic rejection.

32-bit ABIs (armeabi-v7a, x86) are reported but do not fail the check: 16 KB
devices are 64-bit only, and Google's own current ML Kit release still ships
4 KB-aligned armeabi-v7a libraries, which would be impossible if Play required
them.

Usage:
    check-16kb-alignment.py <app.aab|app.apk> [more...]

Exit 0 when every 64-bit library is aligned; 1 otherwise; 2 on usage error.
Nothing is uploaded or modified — this only reads the artifact.
"""
import struct
import sys
import zipfile

PT_LOAD = 1
ALIGN_16KB = 0x4000
SIXTY_FOUR = {"arm64-v8a", "x86_64"}


def elf_load_aligns(data: bytes):
    """Return the p_align of every PT_LOAD segment, or None if not an ELF."""
    if data[:4] != b"\x7fELF":
        return None
    ei_class = data[4]
    endian = "<" if data[5] == 1 else ">"
    if ei_class == 2:  # 64-bit
        e_phoff = struct.unpack_from(endian + "Q", data, 0x20)[0]
        e_phentsize = struct.unpack_from(endian + "H", data, 0x36)[0]
        e_phnum = struct.unpack_from(endian + "H", data, 0x38)[0]
        palign_off, palign_fmt = 0x30, "Q"
    else:  # 32-bit
        e_phoff = struct.unpack_from(endian + "I", data, 0x1c)[0]
        e_phentsize = struct.unpack_from(endian + "H", data, 0x2a)[0]
        e_phnum = struct.unpack_from(endian + "H", data, 0x2c)[0]
        palign_off, palign_fmt = 0x1c, "I"
    aligns = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        if struct.unpack_from(endian + "I", data, off)[0] == PT_LOAD:
            aligns.append(struct.unpack_from(endian + palign_fmt, data, off + palign_off)[0])
    return aligns


def check(path: str) -> bool:
    try:
        z = zipfile.ZipFile(path)
    except (OSError, zipfile.BadZipFile) as err:
        print(f"FAIL  {path}: cannot open as a zip: {err}")
        return False

    sos = sorted(n for n in z.namelist() if n.endswith(".so"))
    if not sos:
        # No native code: the app is trivially 16 KB compatible.
        print(f"OK    {path}: no native libraries (nothing to align)")
        return True

    print(f"=== {path} ({len(sos)} native libraries) ===")
    abis = {"arm64-v8a", "armeabi-v7a", "x86", "x86_64"}
    bad64, bad32 = [], []
    for name in sos:
        aligns = elf_load_aligns(z.read(name))
        mx = max(aligns) if aligns else 0
        parts = name.split("/")
        abi = next((p for p in parts if p in abis), "?")
        lib = parts[-1]
        if mx >= ALIGN_16KB:
            verdict = "OK "
        elif abi in SIXTY_FOUR:
            verdict = "BAD"
            bad64.append(f"{abi}/{lib} p_align=0x{mx:x}")
        else:
            verdict = "4KB"
            bad32.append(f"{abi}/{lib} p_align=0x{mx:x}")
        print(f"  {verdict}  p_align=0x{mx:<6x}  {abi}/{lib}")

    if bad32:
        print(f"  (note: {len(bad32)} 32-bit lib(s) are 4 KB — informational, not required)")
    if bad64:
        print(f"FAIL  {len(bad64)} 64-bit lib(s) not 16 KB aligned:")
        for b in bad64:
            print(f"        {b}")
        return False
    print("PASS  all 64-bit native libraries are 16 KB aligned")
    return True


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    return 0 if all(check(p) for p in sys.argv[1:]) else 1


if __name__ == "__main__":
    sys.exit(main())

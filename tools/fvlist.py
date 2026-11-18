#!/usr/bin/env python3
"""List the UEFI modules inside a CIX/Radxa flash image (cix_flash_all.bin).

Walks every EDK2 firmware volume (_FVH) in the image, decompresses LZMA-compressed
sections and prints one line per FFS file:  <file GUID> type=<FFS type> ui=<module name> pe=<sha256[:12]> pelen=<size>

Usage:
    python3 fvlist.py cix_flash_all.bin [extract_dir]

If extract_dir is given, each module's PE32 image is written there as <name>.efi
(useful for comparing e.g. LinuxLoader.efi between two firmware builds).
Only the Python standard library is needed.
"""
import hashlib
import lzma
import os
import struct
import sys
import uuid

LZMA_GUID = uuid.UUID('EE4E5898-3914-4259-9D6E-DC7BD79403CF')
out_dir = sys.argv[2] if len(sys.argv) > 2 else None
seen = {}


def guid_str(b):
    return str(uuid.UUID(bytes_le=bytes(b)))


def sections(data, ctx):
    off = 0
    while off + 4 <= len(data):
        size = int.from_bytes(data[off:off + 3], 'little')
        typ = data[off + 3]
        hdr = 4
        if size == 0xFFFFFF:
            size = struct.unpack_from('<I', data, off + 4)[0]
            hdr = 8
        if size < hdr or off + size > len(data):
            break
        body = data[off + hdr:off + size]
        if typ == 0x02:  # GUID-defined section (e.g. LZMA compressed)
            sec_guid = uuid.UUID(bytes_le=bytes(body[:16]))
            data_off = struct.unpack_from('<H', body, 16)[0] - hdr
            if sec_guid == LZMA_GUID:
                try:
                    sections(lzma.LZMADecompressor(lzma.FORMAT_ALONE).decompress(bytes(body[data_off:])), ctx)
                except lzma.LZMAError as e:
                    ctx.setdefault('err', []).append(str(e))
            else:
                sections(body[data_off:], ctx)
        elif typ == 0x17:  # firmware volume image
            fvs(body, ctx.get('depth', 0) + 1)
        elif typ == 0x15:  # user interface (module name)
            ctx['ui'] = body.decode('utf-16le', 'ignore').rstrip('\x00')
        elif typ == 0x10:  # PE32
            ctx['pe'] = body
        off += (size + 3) & ~3


def ffs(fv, start, end, depth):
    off = start
    while off + 24 <= end:
        if fv[off:off + 24] == b'\xff' * 24:
            break
        name = guid_str(fv[off:off + 16])
        typ = fv[off + 18]
        attr = fv[off + 19]
        size = int.from_bytes(fv[off + 20:off + 23], 'little')
        hdr = 24
        if attr & 0x01:  # large file
            size = struct.unpack_from('<Q', fv, off + 24)[0]
            hdr = 32
        if size < hdr:
            break
        ctx = {'depth': depth}
        if typ not in (0xF0, 0x01, 0x02):  # skip pad / raw / freeform
            sections(fv[off + hdr:off + size], ctx)
        pe = ctx.get('pe')
        pe_hash = hashlib.sha256(pe).hexdigest()[:12] if pe is not None else '-'
        if (name, pe_hash) not in seen:
            seen[(name, pe_hash)] = 1
            print(f"{'  ' * depth}{name} type={typ:#04x} ui={ctx.get('ui', '')!s:30} pe={pe_hash} "
                  f"pelen={len(pe) if pe is not None else 0}")
            if out_dir and pe is not None and ctx.get('ui'):
                with open(os.path.join(out_dir, f"{ctx['ui']}.efi"), 'wb') as f:
                    f.write(pe)
        off = (off + size + 7) & ~7


def fvs(data, depth=0):
    i = 0
    while True:
        i = data.find(b'_FVH', i)
        if i < 0:
            break
        base = i - 40
        if base < 0:
            i += 4
            continue
        length = struct.unpack_from('<Q', data, base + 32)[0]
        hdr_len = struct.unpack_from('<H', data, base + 48)[0]
        if not (0x48 <= hdr_len < 0x1000 and hdr_len <= length <= len(data) - base):
            i += 4
            continue
        print(f"{'  ' * depth}FV @{base:#x} len={length:#x} guid={guid_str(data[base + 16:base + 32])}")
        fv = data[base:base + length]
        ext = struct.unpack_from('<H', fv, 52)[0]
        start = hdr_len
        if ext:
            start = (ext + struct.unpack_from('<I', fv, ext + 16)[0] + 7) & ~7
        ffs(fv, start, length, depth)
        i = base + length


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(sys.argv[1], 'rb') as f:
        fvs(f.read())

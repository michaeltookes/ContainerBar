"""Pure-Python PNG decode and crop for the panel pixel check (CB-143 fix round 1).

The lane compares what is on screen after the click with a baseline taken before it. A valid AX menu frame can
lie anywhere on the display, so the baseline is one wide capture of the whole display and each check crops it to
the menu's rectangle. Only 8-bit RGB/RGBA, non-interlaced PNGs are read (what screencapture and Peekaboo write);
anything else decodes to None and the caller records no-baseline instead of guessing. Python 3.9, stdlib only.
"""
from __future__ import annotations

import struct
import zlib
from pathlib import Path
from typing import List, Optional, Sequence

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


class Image:
    def __init__(self, width: int, height: int, bpp: int, rows: List[bytes]) -> None:
        self.width, self.height, self.bpp, self.rows = width, height, bpp, rows

    def crop(self, x: int, y: int, w: int, h: int) -> Optional["Image"]:
        if x < 0 or y < 0 or w <= 0 or h <= 0 or x + w > self.width or y + h > self.height:
            return None
        rows = [r[x * self.bpp:(x + w) * self.bpp] for r in self.rows[y:y + h]]
        return Image(w, h, self.bpp, rows)

    def same_pixels(self, other: "Image") -> bool:
        return (self.width, self.height, self.bpp) == (other.width, other.height, other.bpp) \
            and self.rows == other.rows


def _unfilter(kind: int, cur: bytearray, prev: bytes, bpp: int) -> bytearray:
    if kind == 0:
        return cur
    if kind == 1:
        for i in range(bpp, len(cur)):
            cur[i] = (cur[i] + cur[i - bpp]) & 255
    elif kind == 2:
        for i in range(len(cur)):
            cur[i] = (cur[i] + prev[i]) & 255
    elif kind == 3:
        for i in range(len(cur)):
            left = cur[i - bpp] if i >= bpp else 0
            cur[i] = (cur[i] + ((left + prev[i]) >> 1)) & 255
    elif kind == 4:
        for i in range(len(cur)):
            a = cur[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            p = a + b - c
            pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
            cur[i] = (cur[i] + pred) & 255
    else:
        raise ValueError("bad filter")
    return cur


def decode(path: Path) -> Optional[Image]:
    """The decoded image, or None when the file is missing, not a supported PNG or damaged."""
    try:
        data = Path(path).read_bytes()
        if not data.startswith(PNG_MAGIC):
            return None
        pos, header, idat = 8, None, []
        while pos + 8 <= len(data):
            size, kind = struct.unpack(">I4s", data[pos:pos + 8])
            body = data[pos + 8:pos + 8 + size]
            pos += 12 + size
            if kind == b"IHDR":
                header = struct.unpack(">IIBBBBB", body)
            elif kind == b"IDAT":
                idat.append(body)
            elif kind == b"IEND":
                break
        if not header:
            return None
        width, height, depth, color, _, _, interlace = header
        if depth != 8 or color not in (2, 6) or interlace != 0 or width <= 0 or height <= 0:
            return None
        bpp = 3 if color == 2 else 4
        raw = zlib.decompress(b"".join(idat))
        stride = width * bpp
        if len(raw) != height * (stride + 1):
            return None
        rows: List[bytes] = []
        prev = bytes(stride)
        for y in range(height):
            line = raw[y * (stride + 1):(y + 1) * (stride + 1)]
            cur = _unfilter(line[0], bytearray(line[1:]), prev, bpp)
            prev = bytes(cur)
            rows.append(prev)
        return Image(width, height, bpp, rows)
    except (OSError, ValueError, struct.error, zlib.error):
        return None


def encode(width: int, height: int, rows: Sequence[bytes]) -> bytes:
    """RGB PNG with filter 0 (used by the test fakes)."""
    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    return PNG_MAGIC + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")

"""Generate PROXY's CalibrationMarker.png: a high-contrast, non-repeating pattern for ARKit.

Usage: python3 -I tools/make_marker.py <output.png> [seed]
The default seed makes CalibrationMarker (front-left); seed 2030 makes CalibrationMarkerRight.
Print those at exactly 50 mm wide (they are square).
Seed 2031 makes DockMarker: print it at exactly 100 mm; it fills the Field Unit's sync-dock pocket.
"""
import random
import struct
import sys
import zlib

SIZE = 1024
BORDER = 48
SEED = 1848  # fixed so reprints match the bundled reference image

def main(out_path, seed=SEED):
    rng = random.Random(seed)
    px = bytearray([255]) * (SIZE * SIZE)

    def rect(x0, y0, x1, y1, v):
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, SIZE), min(y1, SIZE)
        for y in range(y0, y1):
            px[y * SIZE + x0:y * SIZE + x1] = bytes([v]) * (x1 - x0)

    def circle(cx, cy, r, v):
        for y in range(max(cy - r, 0), min(cy + r, SIZE)):
            dy = y - cy
            half = int((r * r - dy * dy) ** 0.5)
            x0, x1 = max(cx - half, 0), min(cx + half, SIZE)
            if x1 > x0:
                px[y * SIZE + x0:y * SIZE + x1] = bytes([v]) * (x1 - x0)

    inner0, inner1 = BORDER * 2, SIZE - BORDER * 2
    tones = [0, 0, 255, 255, 80, 170]
    for _ in range(110):
        w, h = rng.randint(14, 110), rng.randint(14, 110)
        x, y = rng.randint(inner0, inner1 - w), rng.randint(inner0, inner1 - h)
        rect(x, y, x + w, y + h, rng.choice(tones))
    for _ in range(60):
        r = rng.randint(8, 45)
        circle(rng.randint(inner0 + r, inner1 - r), rng.randint(inner0 + r, inner1 - r), r, rng.choice(tones))

    # Thick black frame plus an asymmetric corner notch so orientation is unambiguous.
    rect(0, 0, SIZE, BORDER, 0)
    rect(0, SIZE - BORDER, SIZE, SIZE, 0)
    rect(0, 0, BORDER, SIZE, 0)
    rect(SIZE - BORDER, 0, SIZE, SIZE, 0)
    rect(BORDER, BORDER, BORDER * 2, BORDER * 2, 0)

    raw = b"".join(b"\x00" + bytes(px[y * SIZE:(y + 1) * SIZE]) for y in range(SIZE))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 0, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(out_path, "wb") as f:
        f.write(png)

if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else SEED)

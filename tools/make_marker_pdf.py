"""Lay out calibration markers on a US Letter PDF at exact size, with a check ruler.

Usage:
  One marker (sync dock), unchanged layout:
    python3 -I tools/make_marker_pdf.py <CalibrationMarker.png> <output.pdf>
  Two markers (Diorama: LEFT = front-left corner, RIGHT = front-right corner):
    python3 -I tools/make_marker_pdf.py <CalibrationMarker.png> <CalibrationMarkerRight.png> <output.pdf>

From the project root, with R="PROXY/Assets.xcassets/AR Resources.arresourcegroup":
    python3 -I tools/make_marker_pdf.py "$R/CalibrationMarker.arreferenceimage/CalibrationMarker.png" \\
        CalibrationMarker_print_50mm.pdf
    python3 -I tools/make_marker_pdf.py "$R/CalibrationMarker.arreferenceimage/CalibrationMarker.png" \\
        "$R/CalibrationMarkerRight.arreferenceimage/CalibrationMarkerRight.png" CalibrationMarkers_print_50mm.pdf
  Field Unit 100 dock marker, 100 mm, fills the sync-dock pocket:
    python3 -I tools/make_marker_pdf.py --dock "$R/DockMarker.arreferenceimage/DockMarker.png" \\
        DockMarker_print_100mm.pdf

Print at 100% / "Actual Size" (never "Fit to page"), then measure the ruler.
In the two-marker layout the dashed cut guide sits exactly on each marker's outer black edge
(the PNG's black border runs to the image edge), and every label is at least 4 mm outside it.
Images are placed unrotated and unflipped: the black notch stays at top-left.
"""
import struct
import sys
import zlib

MM = 72 / 25.4        # PDF points per millimeter
MARKER_MM = 50.0
DOCK_MARKER_MM = 100.0  # pocket 100.6 mm square (Actuator Release.3dm): 0.3 mm clearance per side
PAGE_W, PAGE_H = 612, 792  # US Letter


def read_gray_png(path):
    """Decode the 8-bit grayscale PNG that make_marker.py writes (filter type 0 rows)."""
    data = open(path, "rb").read()
    pos, idat, width = 8, b"", 0
    while pos < len(data):
        (length,), tag = struct.unpack(">I", data[pos:pos + 4]), data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            width, height, depth, color = struct.unpack(">IIBB", body[:10])
            assert depth == 8 and color == 0, "expected 8-bit grayscale"
        elif tag == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    rows = [raw[r * (width + 1):(r + 1) * (width + 1)] for r in range(height)]
    assert all(row[0] == 0 for row in rows), "expected unfiltered rows"
    return width, height, b"".join(row[1:] for row in rows)


def esc(s):
    return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def text(x, y, s, pt=10, font="F1"):
    return f"BT /{font} {pt} Tf {x:.2f} {y:.2f} Td ({esc(s)}) Tj ET\n"


def text_ge(x, y, before, after, pt=10):
    """One line with a '>=' sign between two strings (Symbol font, code 0263)."""
    return f"BT /F1 {pt} Tf {x:.2f} {y:.2f} Td ({esc(before)}) Tj /F3 {pt} Tf (\\263) Tj /F1 {pt} Tf ({esc(after)}) Tj ET\n"


def ruler(x, y, size):
    """Check ruler as long as the marker (50 or 100 mm) with 10 mm ticks, left end at (x, y)."""
    ops = [f"1 w {x:.2f} {y:.2f} m {x + size:.2f} {y:.2f} l S\n"]
    for k in range(round(size / (10 * MM)) + 1):
        tx = x + k * 10 * MM
        ops.append(f"{tx:.2f} {y - 4:.2f} m {tx:.2f} {y + 4:.2f} l S\n")
    return ops


def single_layout(size):
    """Original sync-dock page: one marker. Returns (ops, [(x0, y0)]). Kept byte-identical."""
    x0, y0 = (PAGE_W - size) / 2, 430.0
    ruler_x, ruler_y = x0, y0 - 60
    ops = [
        f"q {size:.3f} 0 0 {size:.3f} {x0:.3f} {y0:.3f} cm /Im1 Do Q\n",
        # thin cut guide 3 mm outside the marker
        f"0.6 G 0.3 w [2 2] 0 d {x0 - 3 * MM:.2f} {y0 - 3 * MM:.2f} {size + 6 * MM:.2f} {size + 6 * MM:.2f} re S [] 0 d 0 G\n",
        text(x0, y0 + size + 46, "PROXY  CalibrationMarker", 16),
        text(x0, y0 + size + 28, "Print at 100% / Actual Size. Never 'Fit to page'.", 10),
        text(x0 + size / 2 - 52, y0 + size + 10, "TOP EDGE: toward the pins", 8),
        text(x0 + size / 2 - 66, y0 - 12 * MM + 18, "BOTTOM EDGE: toward you (front)", 8),
    ]
    ops += ruler(ruler_x, ruler_y, size)
    ops += [
        text(ruler_x, ruler_y - 16, "This line must measure exactly 50 mm. If not, check the print scale.", 9),
        text(ruler_x, ruler_y - 40, "Cut along the dashed line, then trim to the marker's black border.", 9),
        text(ruler_x, ruler_y - 54, "Matte paper or matte sticker only: gloss causes glare under classroom lights.", 9),
        text(ruler_x, ruler_y - 68, "Place it in the sync-dock corner guides, black notch at top-left as read from the front.", 9),
    ]
    return ops


GAP_MM = 40.0          # between the two markers' black edges (>= 20 mm to cut apart)
LABEL_CLEAR_MM = 5.0   # minimum distance from a black edge to any label glyph


def pair_layout(size):
    """Diorama page: LEFT (Im1) and RIGHT (Im2) side by side, as they sit in front of the model."""
    gap = GAP_MM * MM
    left_x = (PAGE_W - (2 * size + gap)) / 2
    y0 = 500.0
    clear = LABEL_CLEAR_MM * MM
    margin_x = left_x
    ops = [
        text(margin_x, 738, "PROXY  Diorama calibration markers (LEFT + RIGHT)", 16, "F2"),
        text(margin_x, 718, "Print at 100% / Actual Size. Never 'Fit to page'.", 11, "F2"),
    ]
    for im, x0, label in (("Im1", left_x, "LEFT: front-left corner"),
                          ("Im2", left_x + size + gap, "RIGHT: front-right corner")):
        ops += [
            f"q {size:.3f} 0 0 {size:.3f} {x0:.3f} {y0:.3f} cm /{im} Do Q\n",
            # dashed cut guide exactly on the marker's outer black edge
            f"0.5 G 0.3 w [2 2] 0 d {x0:.3f} {y0:.3f} {size:.3f} {size:.3f} re S [] 0 d 0 G\n",
            # above: baseline 'clear' above the top edge (no descenders in this string)
            text(x0, y0 + size + clear, "TOP EDGE: toward the model", 8),
            # below: cap height of 11 pt Helvetica-Bold is ~8 pt, so glyph tops sit 'clear' below the edge
            text(x0, y0 - clear - 8, label, 11, "F2"),
        ]
    ruler_x, ruler_y = margin_x, y0 - 70
    ops += ruler(ruler_x, ruler_y, size)
    ops.append(text(ruler_x, ruler_y - 16, "This line must measure exactly 50 mm. If not, check the print scale.", 9))
    steps = [  # each step is a list of lines, wrapped by hand to fit the page
        ["1. Trim each marker exactly along its black border (no white margin)."],
        ["2. Place both on the table in front of the diorama, top edges against the marble base's",
         "    front face, upright as read from the front (black notch at top-left)."],
        ["3. LEFT marker: left edge in line with the base's left side.",
         "    RIGHT marker: right edge in line with the base's right side."],
        ["4. Matte paper or matte sticker only."],
    ]
    y = ruler_y - 46
    for step in steps:
        for line in step:
            ops.append(text(margin_x, y, line, 10))
            y -= 13
        y -= 5
    return ops


def dock_layout(size):
    """Field Unit 100 page: one 100 mm DockMarker (Im1) that fills the sync-dock pocket."""
    x0, y0 = (PAGE_W - size) / 2, 372.0
    clear = LABEL_CLEAR_MM * MM
    ops = [
        text(x0, 738, "PROXY  DockMarker (Field Unit 100)", 16, "F2"),
        text(x0, 718, "Print at 100% / Actual Size. Never 'Fit to page'.", 11, "F2"),
        f"q {size:.3f} 0 0 {size:.3f} {x0:.3f} {y0:.3f} cm /Im1 Do Q\n",
        # dashed cut guide exactly on the marker's outer black edge
        f"0.5 G 0.3 w [2 2] 0 d {x0:.3f} {y0:.3f} {size:.3f} {size:.3f} re S [] 0 d 0 G\n",
        # above: baseline 'clear' above the top edge (no descenders in this string)
        text(x0, y0 + size + clear, "TOP EDGE: toward the pins", 9, "F2"),
        # below: cap height of 9 pt Helvetica is ~6.5 pt, so glyph tops sit 'clear' below the edge
        text(x0, y0 - clear - 7, "Fits the sync-dock pocket; black notch at top-left as read from the front", 9),
    ]
    ruler_x, ruler_y = x0, y0 - 52
    ops += ruler(ruler_x, ruler_y, size)
    ops.append(text(ruler_x, ruler_y - 16, "This line must measure exactly 100 mm. If not, check the print scale.", 9))
    y = ruler_y - 42
    lines = [
        (text, ["1. Cut exactly along the black border (no white margin): 100.0 mm square."]),
        (text_ge, ["2. Glue to stiff card (", "1 mm) so it lies flat on the corner guides."]),
        (text, ["    Trim the card flush with the print. Paper alone sags between the guides."]),
        (text, ["3. Drop it into the sync-dock pocket, upright as read from the front:",
                "    top edge toward the pins, black notch at top-left. The pocket walls register it."]),
        (text, ["4. Matte paper only. In the app, pick the \"Field Unit 100\" setup."]),
        (text, ["The app assumes the printed face sits 1.2 mm above the guides (1 mm card + paper + glue).",
                "Thicker card: lower Y by the extra thickness in the debug panel."]),
    ]
    for kind, parts in lines:
        if kind is text_ge:
            ops.append(text_ge(x0, y, *parts, pt=10))
            y -= 13
        else:
            for line in parts:
                ops.append(text(x0, y, line, 10 if line[:1] in "1234 " else 9))
                y -= 13
        y -= 4
    return ops


def write_pdf(pdf_path, images, ops):
    content = "".join(ops).encode("latin-1")
    n_img = len(images)
    img_objs = []
    for w, h, pixels in images:
        data = zlib.compress(pixels, 9)
        img_objs.append(
            (f"<< /Type /XObject /Subtype /Image /Width {w} /Height {h} /ColorSpace /DeviceGray "
             f"/BitsPerComponent 8 /Filter /FlateDecode /Interpolate false /Length {len(data)} >>\nstream\n").encode()
            + data + b"\nendstream")
    # Object order: catalog, pages, page, image(s), font(s), content.
    xobjs = " ".join(f"/Im{i + 1} {4 + i} 0 R" for i in range(n_img))
    font1 = 4 + n_img
    used = [("F1", "Helvetica"), ("F2", "Helvetica-Bold"), ("F3", "Symbol")]
    used = [(n, b) for n, b in used if n == "F1" or f"/{n} " in content.decode("latin-1")]
    fonts = [f"<< /Type /Font /Subtype /Type1 /BaseFont /{b} >>".encode() for _, b in used]
    font_refs = " ".join(f"/{n} {font1 + i} 0 R" for i, (n, _) in enumerate(used))
    contents_n = font1 + len(fonts)
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {PAGE_W} {PAGE_H}] "
         f"/Resources << /XObject << {xobjs} >> /Font << {font_refs} >> >> /Contents {contents_n} 0 R >>").encode(),
        *img_objs,
        *fonts,
        f"<< /Length {len(content)} >>\nstream\n".encode() + content + b"\nendstream",
    ]
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for n, body in enumerate(objects, 1):
        offsets.append(len(out))
        out += f"{n} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    out += b"".join(f"{o:010d} 00000 n \n".encode() for o in offsets)
    out += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    open(pdf_path, "wb").write(out)


def main(png_paths, pdf_path, dock=False):
    images = [read_gray_png(p) for p in png_paths]
    if dock:
        write_pdf(pdf_path, images, dock_layout(DOCK_MARKER_MM * MM))
        return
    size = MARKER_MM * MM
    ops = single_layout(size) if len(images) == 1 else pair_layout(size)
    write_pdf(pdf_path, images, ops)


if __name__ == "__main__":
    args = sys.argv[1:]
    dock = args[:1] == ["--dock"]
    if dock:
        args = args[1:]
    if len(args) not in ((2,) if dock else (2, 3)):
        sys.exit(__doc__)
    main(args[:-1], args[-1], dock)

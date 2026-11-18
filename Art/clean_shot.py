#!/usr/bin/env python3
"""Take the Dynamic Island out of an App Store screenshot.

    python3 Art/clean_shot.py shot.png                 # writes shot-clean.png
    python3 Art/clean_shot.py shot.png out.png
    python3 Art/clean_shot.py --rotate shot.png        # portrait grab -> landscape first

Why this exists
---------------
Every iPhone whose screen size the App Store accepts for the 6.9" slot has a
Dynamic Island, and a landscape game draws right under it, so every capture
comes back with a black pill bitten out of the artwork. `simctl io screenshot
--mask=ignored` does not help: it drops the rounded corners and leaves the
Island exactly where it was.

Apple allows edited screenshots as long as they represent the app, and the
Island is not part of the app — it is the hardware sitting on top of it. So we
put back what the game was already drawing underneath.

How
---
The pill is found rather than hard-coded, because it moves with the device and
the rotation: the largest near-black blob that hugs one of the short edges and
is far too big to be artwork. Each of its rows is then filled by interpolating
straight across, from a few pixels clear on one side to a few pixels clear on
the other.

At 1:1 — the size anyone actually views a screenshot — this is unnoticeable.
Zoomed in it has one tell: where a hill's silhouette crossed the pill, the
edge arrives as a soft horizontal smear instead of a crisp outline, because a
straight blend cannot reinvent a contour it never saw.

`--clone` copies the neighbouring strip across instead, which does carry hard
edges through. It was tried as the default and reverted: the strip beside the
pill is not guaranteed to be scenery, and on the first real frame it duplicated
Benny's tail into the sky and left vertical seams through the hills. Use it
only when you have checked that the area beside the Island is empty backdrop.
"""

import struct
import sys
import zlib
from collections import deque

NEAR_BLACK = 30        # a channel value at or under this, on all three, reads as the mask
MIN_BLOB = 20_000      # the Island is tens of thousands of pixels; glyphs are thousands
EDGE_BAND = 260        # how close to a short edge the pill must sit
PAD = 4                # pixels of margin taken around the blob, to catch its anti-aliasing


# ---------------------------------------------------------------- PNG in/out

def read_png(path):
    data = open(path, "rb").read()
    pos, idat = 8, b""
    w = h = color = 0
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        if kind == b"IHDR":
            w, h, depth, color = struct.unpack(">IIBB", data[pos + 8:pos + 18])
            if depth != 8:
                sys.exit(f"{path}: only 8-bit PNGs are handled, this one is {depth}-bit")
        elif kind == b"IDAT":
            idat += data[pos + 8:pos + 8 + length]
        pos += 12 + length
    if not w:
        sys.exit(f"{path}: no IHDR — is it a PNG?")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[color]
    raw = zlib.decompress(idat)
    stride = w * channels
    out = bytearray(stride * h)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        filt = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if filt == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 255
        elif filt == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif filt == 3:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif filt == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                c = prev[i - channels] if i >= channels else 0
                b = prev[i]
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                line[i] = (line[i] + (a if (pa <= pb and pa <= pc) else (b if pb <= pc else c))) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, channels, out


def write_png(path, w, h, channels, pixels):
    color = {1: 0, 2: 4, 3: 2, 4: 6}[channels]
    stride = w * channels
    raw = bytearray()
    for y in range(h):
        raw.append(0)                                   # filter 0: none
        raw += pixels[y * stride:(y + 1) * stride]

    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))

    open(path, "wb").write(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, color, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def rotate_left(w, h, channels, px):
    """Portrait framebuffer -> upright landscape."""
    out = bytearray(len(px))
    nw, nh = h, w
    for y in range(h):
        for x in range(w):
            src = (y * w + x) * channels
            nx, ny = y, w - 1 - x
            dst = (ny * nw + nx) * channels
            out[dst:dst + channels] = px[src:src + channels]
    return nw, nh, out


# ---------------------------------------------------------------- the pill

def find_island(w, h, channels, px):
    dark = bytearray(w * h)
    for y in range(h):
        row = y * w
        for x in range(w):
            o = (row + x) * channels
            if px[o] < NEAR_BLACK and px[o + 1] < NEAR_BLACK and px[o + 2] < NEAR_BLACK:
                dark[row + x] = 1

    seen = bytearray(w * h)
    best = None
    for sy in range(h):
        for sx in range(w):
            if not dark[sy * w + sx] or seen[sy * w + sx]:
                continue
            q = deque([(sx, sy)])
            seen[sy * w + sx] = 1
            n = 0
            l, r, t, b = w, -1, h, -1
            while q:
                x, y = q.popleft()
                n += 1
                if x < l: l = x
                if x > r: r = x
                if y < t: t = y
                if y > b: b = y
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and dark[ny * w + nx] and not seen[ny * w + nx]:
                        seen[ny * w + nx] = 1
                        q.append((nx, ny))
            if n < MIN_BLOB:
                continue
            # It has to hug a short edge. Anything dark and huge in the middle of
            # the frame is artwork, and painting over that would be vandalism.
            if not (l < EDGE_BAND or r > w - EDGE_BAND):
                continue
            if best is None or n > best[0]:
                best = (n, l, r, t, b)
    return best


def clone_across(w, h, channels, px, box):
    """Copy the strip immediately beside the pill over it.

    Preferred over blending because the backdrop here is parallax scenery —
    hills and bushes with real silhouettes. Interpolating across a hill's edge
    turns a crisp outline into a smear; translating the neighbouring strip
    carries the edge through, because at this scale the scenery barely changes
    over a hundred pixels horizontally.

    The source side is whichever has room, preferring the one further from the
    frame edge so there is more real scenery to draw from.
    """
    _, l, r, t, b = box
    l = max(0, l - PAD); r = min(w - 1, r + PAD)
    t = max(0, t - PAD); b = min(h - 1, b + PAD)
    span = r - l + 1

    if r + span <= w - 1:
        offset = span            # take from the right
    elif l - span >= 0:
        offset = -span           # take from the left
    else:
        return None              # no room either way; caller falls back

    for y in range(t, b + 1):
        row = y * w
        for x in range(l, r + 1):
            src = (row + x + offset) * channels
            dst = (row + x) * channels
            px[dst:dst + channels] = px[src:src + channels]

    # Feather the two vertical joins so the copy does not announce itself.
    feather = 6
    for y in range(t, b + 1):
        row = y * w
        for edge in (l, r + 1):
            for i in range(-feather, feather):
                x = edge + i
                if x <= 0 or x >= w - 1:
                    continue
                f = (i + feather) / (2 * feather)
                a = (row + x - 1) * channels
                z = (row + x + 1) * channels
                o = (row + x) * channels
                for c in range(channels):
                    px[o + c] = int(round(px[a + c] * (1 - f) + px[z + c] * f))
    return (l, r, t, b)


def paint_out(w, h, channels, px, box):
    _, l, r, t, b = box
    l = max(0, l - PAD); r = min(w - 1, r + PAD)
    t = max(0, t - PAD); b = min(h - 1, b + PAD)
    left_src = l - 2
    right_src = r + 2
    if left_src < 0 and right_src > w - 1:
        sys.exit("the pill spans the whole width — nothing to interpolate from")

    for y in range(t, b + 1):
        row = y * w
        # One clean sample each side; where the pill touches the frame edge there
        # is only one, and that row is filled flat from it.
        a = [px[(row + left_src) * channels + c] for c in range(channels)] if left_src >= 0 else None
        z = [px[(row + right_src) * channels + c] for c in range(channels)] if right_src <= w - 1 else None
        if a is None: a = z
        if z is None: z = a
        span = (r - l) or 1
        for x in range(l, r + 1):
            f = (x - l) / span
            o = (row + x) * channels
            for c in range(channels):
                px[o + c] = int(round(a[c] + (z[c] - a[c]) * f))
    return (l, r, t, b)


# ---------------------------------------------------------------- entry

def main(argv):
    rotate = False
    clone = False
    args = []
    for a in argv:
        if a in ("--rotate", "-r"):
            rotate = True
        elif a == "--clone":
            clone = True        # see the docstring — usually worse, occasionally better
        else:
            args.append(a)
    if not args:
        sys.exit(__doc__)

    src = args[0]
    dst = args[1] if len(args) > 1 else src.rsplit(".", 1)[0] + "-clean.png"

    w, h, channels, px = read_png(src)
    if rotate or h > w:
        w, h, px = rotate_left(w, h, channels, px)
        print(f"  rotated to {w}x{h}")

    box = find_island(w, h, channels, px)
    if not box:
        print("  no Island found — writing through unchanged")
    else:
        n, l, r, t, b = box
        print(f"  found a {r - l + 1}x{b - t + 1} pill at x {l}-{r}, y {t}-{b} ({n}px)")
        done = clone_across(w, h, channels, px, box) if clone else None
        how = "cloned from the neighbouring strip"
        if done is None:
            done = paint_out(w, h, channels, px, box)
            how = "blended across"
        l, r, t, b = done
        print(f"  {how}: x {l}-{r}, y {t}-{b}")

    write_png(dst, w, h, channels, px)
    print(f"  wrote {dst}  ({w}x{h})")


if __name__ == "__main__":
    main(sys.argv[1:])

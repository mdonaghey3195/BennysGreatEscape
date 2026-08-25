"""Benny's Great Escape - cuts the bark out of a recording of the real dog.

    python3 Sounds/cut_bark.py <recording>

Run from the repository root. The recording can be anything afconvert reads —
the one this was written for is a 3s mono AAC clip off a phone. Every bark it
finds is written to Sounds/preview/bark_N.wav to be listened to and picked from;
the chosen one becomes the game's.

Not synthesised, unlike everything in make_sfx.py. The other four are physical
noises and a physical noise can be drawn; an animal can't. A synthesised bark
sounds like a cartoon, and this dog is real and the whole opening clip is about
that.

Standard library plus afconvert, which ships with macOS. No ffmpeg needed.
"""

import math
import os
import struct
import subprocess
import sys
import wave

SR = 44100

# What counts as a bark, and how much of it to keep.
#
# Both thresholds are fractions of the loudest sample in the recording rather
# than absolute levels, so a quiet recording and a loud one are cut the same
# way.
OPEN = 0.20     # rises past this and a bark has started
CLOSE = 0.05    # falls back under this and it is ending
HANG = 0.09     # ...for this long, so a bark with a gap in it stays one bark
PREROLL = 0.03  # kept before the onset: the very front of a bark is its attack,
                # and a threshold always misses some of it
TAIL = 0.06     # kept after it closes, for the room the dog barked in
LONGEST = 1.20  # a safety net, not a shape

WINDOW = 0.010  # how much is looked at to decide how loud "now" is
HOP = 0.0025

PEAK = 10 ** (-3 / 20)  # matched to make_sfx.py
FADE = 0.005


def decode(path, into):
    """Whatever came off the phone, as 16-bit mono PCM at 44.1kHz."""
    subprocess.run(
        ["afconvert", "-f", "WAVE", "-d", f"LEI16@{SR}", "-c", "1", path, into],
        check=True,
    )
    with wave.open(into, "rb") as f:
        frames = f.readframes(f.getnframes())
    return [s / 32768 for (s,) in struct.iter_unpack("<h", frames)]


def envelope(x):
    """RMS in a sliding window — how loud it is around each hop, in order."""
    window = int(WINDOW * SR)
    hop = int(HOP * SR)
    out = []
    for start in range(0, max(len(x) - window, 1), hop):
        chunk = x[start : start + window]
        out.append(math.sqrt(sum(s * s for s in chunk) / len(chunk)))
    return out, hop


def barks(x):
    """Where each bark starts and stops, in samples."""
    env, hop = envelope(x)
    loudest = max(env) or 1.0
    opens, closes = OPEN * loudest, CLOSE * loudest
    hang = int(HANG / HOP)

    found = []
    start = None
    quiet = 0
    for i, level in enumerate(env):
        if start is None:
            if level >= opens:
                start = i
                quiet = 0
            continue
        if level < closes:
            quiet += 1
            if quiet >= hang:
                found.append((start * hop, (i - hang) * hop))
                start = None
        else:
            quiet = 0
    if start is not None:
        found.append((start * hop, len(env) * hop))

    # Give each one its attack back, its room back, and a ceiling.
    cut = []
    for begin, end in found:
        begin = max(0, begin - int(PREROLL * SR))
        end = min(len(x), end + int(TAIL * SR), begin + int(LONGEST * SR))
        if end - begin > int(0.06 * SR):  # anything shorter is a bump, not a bark
            cut.append((begin, end))
    return cut


def finish(x):
    n = len(x)
    fade = int(FADE * SR)
    out = list(x)
    for i in range(min(fade, n)):
        out[i] *= i / fade
        out[n - 1 - i] *= i / fade
    loudest = max(abs(s) for s in out) or 1.0
    return [s * PEAK / loudest for s in out]


def write(path, samples):
    frames = b"".join(
        struct.pack("<h", max(-32768, min(32767, int(s * 32767)))) for s in samples
    )
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(frames)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: python3 Sounds/cut_bark.py <recording>")

    os.makedirs("Sounds/preview", exist_ok=True)
    scratch = "Sounds/preview/.source.wav"
    audio = decode(sys.argv[1], scratch)
    print(f"\n{len(audio) / SR:.2f}s of audio")

    found = barks(audio)
    print(f"{len(found)} bark(s)\n")
    for index, (begin, end) in enumerate(found, start=1):
        clip = finish(audio[begin:end])
        path = f"Sounds/preview/bark_{index}.wav"
        write(path, clip)
        print(
            f"  {path}  at {begin / SR:4.2f}s  {(end - begin) / SR * 1000:5.0f}ms"
        )

    os.remove(scratch)
    print("\nlisten with:  afplay Sounds/preview/bark_1.wav")

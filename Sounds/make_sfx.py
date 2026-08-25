"""Benny's Great Escape - the game's sound effects. One script, four sounds.

    python3 Sounds/make_sfx.py

Run from the repository root. Rerunning overwrites the WAVs in place, so
retuning a sound is a rerun rather than a hand edit — which is the point of
having a script at all, and the same stance Art/SliceIntroSheets.swift takes
with the sprite sheets.

Standard library only, like Music/benny_theme.py. Nothing here needs a DAW: all
four are physical noises rather than music, and a physical noise is a shape of
noise and a shape of pitch over a few hundred milliseconds. The bark is the
exception and is not synthesised — see cut_bark.py.

Everything worth turning is in TUNING. The synthesis below reads those and
should mostly be left alone.
"""

import math
import random
import struct
import wave

SR = 44100

# Peak every sound is normalised to. -3 dBFS: Music/README.md notes the theme
# masters at -0.1 dBFS and that a hot master can clip on the way through AAC.
# These ship as uncompressed WAV so they can't clip in transit, but the headroom
# is what keeps an effect sitting under the music rather than on top of it.
PEAK = 10 ** (-3 / 20)

# How much of each end is faded, to be sure nothing starts or stops on a
# non-zero sample. A click is the one artefact a listener always notices.
FADE = 0.005

# The numbers to turn. Everything is seconds and hertz.
TUNING = {
    # A dog leaving the ground: air past the ears, and a little body under it.
    "jump": {
        "length": 0.18,
        "sweep": (700, 2600),  # where the whoosh starts and ends
        "q": 1.1,              # higher is thinner and more whistly
        "body": (230, 150),    # the soft "hup" under the air
        "body_level": 0.30,
        "decay": 0.075,
    },
    # Paws hitting turf. Mostly the low body; the rest is what sells the surface.
    "land": {
        "length": 0.16,
        "thump": (95, 55),     # pitch drop of the body
        "thump_decay": 0.048,
        "click": 0.008,        # the transient on the front
        "click_level": 0.26,
        "scuff_level": 0.30,   # turf under the paws
        "scuff_cut": 620,
    },
    # Grit under a dog on his side, for as long as the slide lasts.
    "slide": {
        "length": 0.36,
        "band": (1100, 3000),
        "attack": 0.02,
        "release": 0.10,
        "wobble": 17.0,        # Hz — the unevenness of the ground
        "wobble_depth": 0.35,
        "rumble_level": 0.28,
        "rumble_cut": 200,
    },
    # Running into something wooden. Heavier body, and a knock on top of it.
    "crash": {
        "length": 0.32,
        "thump": (72, 44),
        "thump_decay": 0.085,
        "knock": (430, 620),   # two inharmonic partials — wood, not a bell
        "knock_decay": 0.055,
        "knock_level": 0.55,
        "burst": 0.018,
        "burst_level": 0.40,
        "debris_level": 0.22,  # the tail of it coming to rest
        "debris_decay": 0.16,
    },
}

# Fixed, so a rerun gives byte-identical files and a diff means something
# actually changed.
SEED = 20260823


# MARK: - The pieces


def noise(n):
    return [random.uniform(-1, 1) for _ in range(n)]


def svf(x, freq_at, q=1.0, take="band"):
    """A Chamberlin state-variable filter, swept per sample.

    Time-varying cutoff is the whole reason for this one rather than a simpler
    one-pole: a whoosh *is* its sweep, and a filter you can only set once can't
    draw one.
    """
    low = band = 0.0
    out = []
    damp = 1.0 / q
    for i, s in enumerate(x):
        f = 2 * math.sin(math.pi * min(freq_at(i), SR * 0.45) / SR)
        high = s - low - damp * band
        band += f * high
        low += f * band
        out.append({"low": low, "band": band, "high": high}[take])
    return out


def onepole(x, cutoff):
    """A gentle fixed lowpass, for the times a sweep isn't wanted."""
    a = math.exp(-2 * math.pi * cutoff / SR)
    out = []
    prev = 0.0
    for s in x:
        prev = (1 - a) * s + a * prev
        out.append(prev)
    return out


def sweep(start, end, n, curve=2.0):
    """Start to end over n samples, easing rather than travelling evenly.

    Pitch and brightness are both heard logarithmically, so a linear ramp spends
    most of its time in the last octave and reads as arriving early.
    """
    return lambda i: start + (end - start) * ((i / max(n - 1, 1)) ** curve)


def decay(n, tau):
    """Exponential fall, the shape almost everything struck actually makes."""
    return [math.exp(-(i / SR) / tau) for i in range(n)]


def tone(freq_at, n):
    """A sine whose pitch can move under it."""
    out = []
    phase = 0.0
    for i in range(n):
        phase += 2 * math.pi * freq_at(i) / SR
        out.append(math.sin(phase))
    return out


def mix(*layers):
    n = max(len(layer) for layer in layers)
    out = [0.0] * n
    for layer in layers:
        for i, s in enumerate(layer):
            out[i] += s
    return out


def finish(x):
    """Fade both ends, then normalise to PEAK."""
    n = len(x)
    fade = int(FADE * SR)
    for i in range(min(fade, n)):
        x[i] *= i / fade
        x[n - 1 - i] *= i / fade
    loudest = max(abs(s) for s in x) or 1.0
    return [s * PEAK / loudest for s in x]


def write(path, samples):
    frames = b"".join(
        struct.pack("<h", max(-32768, min(32767, int(s * 32767)))) for s in samples
    )
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(frames)
    peak = max(abs(s) for s in samples)
    print(f"  {path}  {len(samples) / SR * 1000:5.0f}ms  peak {20 * math.log10(peak):.1f} dBFS")


# MARK: - The four sounds


def jump(t):
    n = int(t["length"] * SR)

    air = svf(noise(n), sweep(*t["sweep"], n), q=t["q"])
    # Swelling rather than struck: he is pushing off, and the air arrives after
    # the push. Squared, so the front is quiet and the middle is where it lives.
    for i in range(n):
        shape = (i / n) ** 0.6 * math.exp(-(i / SR) / t["decay"])
        air[i] *= shape * 3.0

    body = tone(sweep(*t["body"], n), n)
    weight = decay(n, t["decay"] * 0.8)
    body = [s * w * t["body_level"] for s, w in zip(body, weight)]

    return finish(mix(air, body))


def land(t):
    n = int(t["length"] * SR)

    body = tone(sweep(*t["thump"], n, curve=1.2), n)
    body = [s * d for s, d in zip(body, decay(n, t["thump_decay"]))]

    click = int(t["click"] * SR)
    front = svf(noise(click), lambda i: 2200, q=0.8, take="high")
    front = [s * (1 - i / click) * t["click_level"] for i, s in enumerate(front)]
    front += [0.0] * (n - click)

    scuff = onepole(noise(n), t["scuff_cut"])
    scuff = [
        # Shorter-lived than the body, deliberately. Turf outlasting the thump
        # is what turns a landing into a hiss.
        s * d * t["scuff_level"] * 2.5
        for s, d in zip(scuff, decay(n, t["thump_decay"] * 0.9))
    ]

    return finish(mix(body, front, scuff))


def slide(t):
    n = int(t["length"] * SR)
    attack = int(t["attack"] * SR)
    release = int(t["release"] * SR)

    # Lowpassed first: grit is a mid-range noise, and the top octave of white
    # noise on top of it reads as tape hiss rather than as ground.
    grit = svf(onepole(noise(n), 5200), sweep(*t["band"], n, curve=0.7), q=1.6)
    for i in range(n):
        if i < attack:
            shape = i / attack
        elif i > n - release:
            shape = (n - i) / release
        else:
            shape = 1.0
        # The ground is not smooth, and a scuff at a constant level sounds like
        # a held noise rather than something dragging over it.
        wobble = 1 - t["wobble_depth"] * (0.5 - 0.5 * math.cos(2 * math.pi * t["wobble"] * i / SR))
        grit[i] *= shape * wobble * 3.0

    rumble = onepole(noise(n), t["rumble_cut"])
    rumble = [
        s * t["rumble_level"] * 4.0 * (1 if i < n - release else (n - i) / release)
        for i, s in enumerate(rumble)
    ]

    return finish(mix(grit, rumble))


def crash(t):
    n = int(t["length"] * SR)

    body = tone(sweep(*t["thump"], n, curve=1.4), n)
    body = [s * d for s, d in zip(body, decay(n, t["thump_decay"]))]

    # Two partials that aren't a whole-number ratio apart. A ratio would ring
    # like a bell; wood doesn't.
    knock = mix(
        tone(sweep(t["knock"][0], t["knock"][0] * 0.82, n), n),
        [0.6 * s for s in tone(sweep(t["knock"][1], t["knock"][1] * 0.86, n), n)],
    )
    knock = [
        s * d * t["knock_level"] for s, d in zip(knock, decay(n, t["knock_decay"]))
    ]

    burst = int(t["burst"] * SR)
    hit = svf(noise(burst), sweep(4000, 1200, burst), q=0.7)
    hit = [s * (1 - i / burst) ** 2 * t["burst_level"] * 3.0 for i, s in enumerate(hit)]
    hit += [0.0] * (n - burst)

    debris = onepole(noise(n), 520)
    debris = [
        s * d * t["debris_level"] * 3.0
        for s, d in zip(debris, decay(n, t["debris_decay"]))
    ]

    return finish(mix(body, knock, hit, debris))


# MARK: - Rendering


if __name__ == "__main__":
    print("sound effects")
    for name, render in (("jump", jump), ("land", land), ("slide", slide), ("crash", crash)):
        random.seed(SEED)
        write(f"Sounds/preview/sfx_{name}.wav", render(TUNING[name]))
    print("\nlisten with:  afplay Sounds/preview/sfx_jump.wav")

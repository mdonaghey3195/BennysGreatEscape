"""Benny's Great Escape - gameplay loop. One score, two outputs: WAV and MIDI."""
import math, struct, wave

BPM   = 132.0
SPB   = 60.0 / BPM          # seconds per beat
BARS  = 16
BEATS = BARS * 4
SR    = 44100

# (midi note, start beat, length in beats)
LEAD = [
    # A - the main hop, C G Am F | C G F G
    (67,0,.5),(69,.5,.5),(72,1,1),(67,2,.5),(64,2.5,.5),(67,3,1),
    (74,4,.5),(71,4.5,.5),(67,5,1),(71,6,1),(74,7,1),
    (72,8,.5),(69,8.5,.5),(64,9,1),(69,10,1),(72,11,1),
    (69,12,.5),(65,12.5,.5),(69,13,1),(72,14,2),
    (67,16,.5),(69,16.5,.5),(72,17,1),(67,18,.5),(64,18.5,.5),(67,19,1),
    (74,20,.5),(71,20.5,.5),(67,21,1),(71,22,1),(74,23,1),
    (69,24,.5),(72,24.5,.5),(77,25,1),(76,26,1),(72,27,1),
    (74,28,1),(71,29,1),(67,30,2),
    # B - lifts an octave, Am F C G | Am F G G
    (76,32,.5),(72,32.5,.5),(69,33,1),(72,34,.5),(76,34.5,.5),(81,35,1),
    (79,36,.5),(77,36.5,.5),(72,37,1),(77,38,2),
    (76,40,.5),(79,40.5,.5),(76,41,1),(72,42,1),(67,43,1),
    (69,44,.5),(71,44.5,.5),(74,45,1),(71,46,2),
    (76,48,.5),(72,48.5,.5),(69,49,1),(72,50,.5),(76,50.5,.5),(81,51,1),
    (79,52,.5),(77,52.5,.5),(72,53,1),(77,54,2),
    (74,56,.5),(76,56.5,.5),(79,57,1),(77,58,1),(74,59,1),
    (71,60,1),(74,61,1),(72,62,2),
]
# one chord per bar: (root pitch class name, root midi, triad)
CHORDS = [("C",48,[60,64,67]),("G",43,[59,62,67]),("A",45,[57,60,64]),("F",41,[57,60,65]),
          ("C",48,[60,64,67]),("G",43,[59,62,67]),("F",41,[57,60,65]),("G",43,[59,62,67]),
          ("A",45,[57,60,64]),("F",41,[57,60,65]),("C",48,[60,64,67]),("G",43,[59,62,67]),
          ("A",45,[57,60,64]),("F",41,[57,60,65]),("G",43,[59,62,67]),("G",43,[59,62,67])]

BASS, STAB = [], []
for b, (_, root, triad) in enumerate(CHORDS):
    t = b * 4
    BASS += [(root, t, .9), (root + 7, t + 2, .9)]          # oom .. oom
    STAB += [(n, t + 1, .35) for n in triad]                 # .. pah
    STAB += [(n, t + 3, .35) for n in triad]
KICK = [b * 4 + o for b in range(BARS) for o in (0, 2)]
HAT  = [b * 4 + o / 2 for b in range(BARS) for o in (1, 3, 5, 7)]

def hz(n): return 440.0 * 2 ** ((n - 69) / 12.0)

def env(i, n, a, d, s, r):
    """ADSR over a note of n samples, returning gain at sample i."""
    A, D, R = int(a*SR), int(d*SR), int(r*SR)
    if i < A:            return i / max(A, 1)
    if i < A + D:        return 1 - (1 - s) * (i - A) / max(D, 1)
    if i < n - R:        return s
    return s * max(0.0, (n - i) / max(R, 1))

def render():
    tail = int(0.6 * SR)
    total = int(BEATS * SPB * SR)
    buf = [0.0] * (total + tail)

    def tone(note, start, beats, gain, harms, adsr, vib=0.0):
        f0 = hz(note)
        st = int(start * SPB * SR)
        n = int(beats * SPB * SR)
        for i in range(n + int(adsr[3] * SR)):
            k = st + i
            if k >= len(buf): break
            t = i / SR
            v = 1.0 + vib * math.sin(2 * math.pi * 5.2 * t)
            s = sum(a * math.sin(2 * math.pi * f0 * h * v * t) for h, a in harms)
            buf[k] += s * gain * env(i, n, *adsr)

    # mellow square: odd harmonics, rolled off so it stays sweet rather than buzzy
    sq = [(h, 1.0 / h) for h in (1, 3, 5, 7, 9, 11)]
    tri = [(h, 1.0 / (h * h)) for h in (1, 3, 5, 7)]
    for note, st, ln in LEAD:
        tone(note, st, ln * .92, 0.15, sq, (.006, .07, .72, .08), vib=.0016)
    for note, st, ln in BASS:
        tone(note, st, ln, 0.30, [(1, 1.0), (2, .22)], (.004, .10, .55, .06))
    for note, st, ln in STAB:
        tone(note, st, ln, 0.055, tri, (.004, .09, .30, .07))

    seed = 12345
    for st in HAT:                                   # noise burst hi-hat
        k0 = int(st * SPB * SR); n = int(.045 * SR)
        for i in range(n):
            if k0 + i >= len(buf): break
            seed = (1103515245 * seed + 12345) & 0x7FFFFFFF
            buf[k0+i] += ((seed / 0x3FFFFFFF) - 1.0) * .035 * (1 - i / n) ** 2.5
    for st in KICK:                                  # pitch-swept kick
        k0 = int(st * SPB * SR); n = int(.11 * SR)
        for i in range(n):
            if k0 + i >= len(buf): break
            t = i / SR
            f = 120 * math.exp(-t * 26) + 45
            buf[k0+i] += math.sin(2*math.pi*f*t) * .34 * (1 - i/n) ** 1.6

    # Fold the overhanging tail back onto the head: the loop point becomes
    # inaudible instead of a click or a swallowed note.
    for i in range(tail):
        buf[i] += buf[total + i]
    buf = buf[:total]

    peak = max(abs(v) for v in buf) or 1.0
    scale = 0.89 / peak
    return [max(-1.0, min(1.0, v * scale)) for v in buf]

def write_wav(path, samples):
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(v * 32767)) for v in samples))

# ---- MIDI ----------------------------------------------------------------
TPQ = 480
def vlq(n):
    out = bytearray([n & 0x7F]); n >>= 7
    while n: out.insert(0, (n & 0x7F) | 0x80); n >>= 7
    return bytes(out)

def track(events, name):
    """events: (tick, status, d1, d2) - emitted sorted, as delta times."""
    data = bytearray(b"\x00\xFF\x03" + vlq(len(name)) + name.encode())
    last = 0
    for tick, st, d1, d2 in sorted(events, key=lambda e: (e[0], e[1] & 0xF0 == 0x90)):
        data += vlq(tick - last) + bytes([st, d1, d2]); last = tick
    data += b"\x00\xFF\x2F\x00"
    return b"MTrk" + struct.pack(">I", len(data)) + bytes(data)

def notes_to_events(notes, ch, vel):
    ev = []
    for note, st, ln in notes:
        a, b = int(st * TPQ), int((st + ln) * TPQ)
        ev.append((a, 0x90 | ch, note, vel)); ev.append((b, 0x80 | ch, note, 0))
    return ev

def write_midi(path):
    us = int(60_000_000 / BPM)
    tempo = bytearray(b"\x00\xFF\x03\x05Tempo\x00\xFF\x51\x03" + us.to_bytes(3, "big"))
    tempo += b"\x00\xFF\x58\x04\x04\x02\x18\x08" + b"\x00\xFF\x2F\x00"
    trks = [b"MTrk" + struct.pack(">I", len(tempo)) + bytes(tempo),
            track(notes_to_events(LEAD, 0, 96), "Lead"),
            track(notes_to_events(BASS, 1, 100), "Bass"),
            track(notes_to_events(STAB, 2, 64), "Chords"),
            track([e for st in KICK for e in ((int(st*TPQ), 0x99, 36, 100), (int((st+.25)*TPQ), 0x89, 36, 0))] +
                  [e for st in HAT  for e in ((int(st*TPQ), 0x99, 42, 70),  (int((st+.15)*TPQ), 0x89, 42, 0))], "Drums")]
    with open(path, "wb") as f:
        f.write(b"MThd" + struct.pack(">IHHH", 6, 1, len(trks), TPQ))
        for t in trks: f.write(t)

if __name__ == "__main__":
    import sys
    s = render()
    write_wav(sys.argv[1], s)
    write_midi(sys.argv[2])
    print(f"{BARS} bars @ {BPM:.0f}bpm = {BEATS*SPB:.2f}s loop, {len(s)} samples")

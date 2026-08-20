# Benny's theme

`benny_theme.wav` is the track the game plays — written in GarageBand, exactly
60.000s, mono. It loops well: no leading or trailing silence, no fade-out (the
first 500ms and last 500ms sit within 1.4dB of each other, so the tune doesn't
dip every minute), and no near-silent stretches that would read as a gap.

The wrap discontinuity measures 0.0349 against a median sample-to-sample delta
of 0.0045. That's inside the normal range of steps in the waveform and well
masked by the material either side of the loop point, so it doesn't tick — but
it isn't the perfect zero-crossing match the previous 6.5s loop had, and it's
the first thing to look at if a click ever appears.

`../BennysGreatEscape/benny_theme.m4a` is what ships: the same audio at 128kbps
AAC, 385KB. The source peaks at -0.1 dBFS, which is hot enough to be worth
checking after any re-encode — this one decodes to -0.08 dBFS with zero clipped
samples, but a louder master could clip on the way through AAC.

## Replacing it

Export from GarageBand, then:

    afconvert -f m4af -d aac -b 128000 -s 3 new.wav ../BennysGreatEscape/benny_theme.m4a

No code changes needed — `Music.swift` looks the file up by that name. Two things
to keep true of any replacement:

- **a whole number of bars**, or the loop will drift against the beat
- **no clipped reverb tail** at the end, because the game loops it with
  `numberOfLoops = -1` and no crossfade

## The placeholder that came before

`benny_theme.py` and `benny_theme.mid` are a synthesised chiptune stand-in from
before the real track existed. The script emits both a WAV and a 5-track MIDI
(Tempo, Lead, Bass, Chords, Drums) from one score, so the MIDI can be opened in
GarageBand and re-voiced. Kept only in case the MIDI is a useful starting point;
nothing references them and they can be deleted.

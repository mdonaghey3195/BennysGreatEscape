# The game's sound effects

Five sounds ship: four synthesised, one real.

| Shipped as | From | What it is |
| --- | --- | --- |
| `sfx_jump.wav` | `make_sfx.py` | Air past the ears as he leaves the ground |
| `sfx_land.wav` | `make_sfx.py` | Paws down on turf |
| `sfx_slide.wav` | `make_sfx.py` | Grit under a dog on his side |
| `sfx_crash.wav` | `make_sfx.py` | Running into something wooden |
| `sfx_bark_0.wav`, `sfx_bark_1.wav` | `cut_bark.py` | Benny, off a phone recording |

They live in `../BennysGreatEscape/` beside `benny_theme.m4a`. That folder is a
synchronised group in the Xcode project, so a file dropped into it is in the
build — no project edits, and `Sfx.swift` finds them by name.

WAV rather than the theme's AAC. They are 14–32KB each and 143KB all told, so
compression buys nothing worth having, and an uncompressed file has no decode to
do on the frame it is asked to play on.

## Re-rendering the four

    python3 Sounds/make_sfx.py

Writes to `Sounds/preview/`. Listen with `afplay Sounds/preview/sfx_land.wav`,
and when you're happy, copy the ones you changed into `../BennysGreatEscape/`.
The preview step is deliberate: these are quick to render and slow to judge, and
nothing should reach the app unheard.

Everything worth turning is in `TUNING` at the top of the script — the pitch a
thud falls through, how bright the whoosh sweeps, how uneven the grit is. The
synthesis below it reads those and rarely needs touching. `SEED` is fixed, so a
re-render with nothing changed produces a byte-identical file and a diff always
means something actually moved.

Two things to keep true of any replacement:

- **-3 dBFS peak.** All five are mastered to the same level on purpose: a render
  is a shape, not a volume. How loud each one should *be* is a decision about
  the game, and it lives in one table in `Sfx.swift` rather than in the files.
- **Faded at both ends.** 5ms is enough. A sound that starts or stops on a
  non-zero sample clicks, and a click is the one artefact everybody hears.

## Re-cutting the bark

    python3 Sounds/cut_bark.py <recording>

Takes anything `afconvert` can read — the barks that ship came out of a 3s clip
off a phone. It decodes the audio, finds each bark by watching a sliding RMS
cross a threshold, and writes every one it finds to `Sounds/preview/bark_N.wav`
with its attack, its tail and its room intact.

Pick the ones you want and copy them in as `sfx_bark_0.wav`, `sfx_bark_1.wav`,
and so on. `Sfx` probes those numbers until one is missing and picks between
whatever it finds at random, so giving him a third bark is a file drop and no
code change — the same stance the sprite frames take.

Two is already worth having. The bark is the most recognisable sound in the
game, and one recording played twice is exactly what gives a sample away.

The bark is the one thing here that isn't synthesised, and it can't be. The
other four are physical noises, and a physical noise is a shape of noise and a
shape of pitch over a couple of hundred milliseconds. An animal is not, and a
synthesised bark sounds like a cartoon of a dog — which would be a strange thing
to put in a game whose opening exists to say that this one is real.

## Where they play

| Sound | Where |
| --- | --- |
| jump | `GameScene.jump()` |
| land | `GameScene.didBegin`, and only after he has actually been airborne |
| slide | `GameScene.slide()` |
| crash | `GameScene.endGame()` |
| bark | `GameScene.handOff()` — the moment the leash slips, once a run |

All of them obey the settings switch, which the painted row already describes as
"Turn game sounds on or off". Haptics don't: muting a game in a quiet room is
the moment a player still wants to feel it.

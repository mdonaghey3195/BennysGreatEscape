# Benny at full resolution

The 28 gameplay frames (run, jump, slide) exactly as they shipped before
`CutDogFrames.swift` started shrinking them for the catalogue: 1259 x 897 px,
cut from the sheets next door and untouched since.

They are here so the smaller frames can be judged against the originals and
rolled back if they don't look right. The game draws Benny about 350 px wide on
a Pro Max, and the shipped frames are now 640 px wide; these are the 1259 px
versions that were decoded, uploaded and held in memory at four times that.

## To roll back

Either regenerate the full-size frames from the sheets:

    swift Art/CutDogFrames.swift --full

or copy these straight over the catalogue:

    for f in Art/benny_fullres/benny_*.png; do
      n=$(basename "$f" .png); clip=${n#benny_}; clip=${clip%_*}
      cp "$f" "BennysGreatEscape/Assets.xcassets/phase_one/gameplay/benny/benny_$clip.spriteatlas/$n.imageset/$n.png"
    done

Nothing in `DogArt` needs changing either way: every measurement there is a
fraction of the canvas, and the aspect is read off the texture at runtime.

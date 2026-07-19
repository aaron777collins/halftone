# Halftone

A live, in-browser **comic / posterize stylization tuner** for video frames. Drag the
sliders until a still frame looks the way you want, then copy the matching **ffmpeg
command** and run it to batch-process your clips with the exact same look.

**Live tuner:** https://aaron777collins.github.io/halftone/

Built with plain WebGL — no frameworks, no build step, no dependencies. It's a single
`index.html` file.

## Use it

1. Open the [live page](https://aaron777collins.github.io/halftone/) (or open
   `index.html` locally in any modern browser).
2. Optionally **Load image / video** to preview the effect on your own media. Your
   media stays in your browser — it is never uploaded anywhere (see Privacy).
3. Drag the sliders — Color, Flatten, Posterize, Ink lines, Output — until the preview
   looks right.
4. Click **Copy** to grab the ffmpeg command (or **Copy batch** to loop over
   `input/*.mp4`).
5. Paste it into a terminal and run it on your clips. The `comicify.sh` script and the
   `presets/` files in this repo are the batch equivalents — their defaults reproduce
   the built-in "Halftone default" look (see `FAVORITE-PRESET.md`).

### Exporting from the page

The tuner also has an **Export** control by the preview:

- **Image / default scene loaded** → **Download frame (PNG)** saves the stylized still.
- **Video loaded** → **Record & download (WebM)** records the stylized canvas for one
  full pass (with source audio when the browser allows) and downloads a `.webm`; a
  **Stop** button ends it early.

WebM export is a quick in-browser copy — for final MP4 / Camtasia quality, use the
ffmpeg command. (Recording needs a browser with `MediaRecorder` + `captureStream`; if
unavailable the button is disabled.)

## How it works

The preview pipeline (WebGL) and the generated ffmpeg command apply the same chain:

1. **Color** — `eq` saturation and contrast boost to push the palette toward pop-art.
2. **Flatten** — an edge-preserving bilateral pass fills regions with flat color while
   keeping edges crisp (this is what makes it graphic instead of blurry).
3. **Posterize** — quantizes the image in YUV so luma steps to a chosen number of
   levels and chroma is centered so neutral tones don't cast a color.
4. **Ink lines** — a Sobel edge pass draws dark outlines, with adjustable threshold,
   thickness, and darkness.
5. **Output** — an optional 2× supersample renders at double size and scales back down
   for clean, anti-aliased ink lines.

The on-screen demo scene is drawn procedurally with the Canvas 2D API — it's a neutral
sunset/dock illustration, not a photo.

## Privacy

Media you load stays in your browser and is **never uploaded** — the tuner runs
entirely client-side. This repository contains **no personal imagery**: the default
preview is a procedurally-generated placeholder, and media/derived files are excluded
via `.gitignore`.

## Scripture

The rotating verses shown under the header are from the **World English Bible (WEB)**,
which is in the **public domain**.

## License

**Source-visible, all rights reserved.** See [`LICENSE`](LICENSE). The code is public to
read, but no rights to use, copy, modify, or redistribute are granted.

# ⭐ Favorite comic preset — "Halftone default"

The locked-in look. This is the canonical command; the tuner and `comicify.sh`
defaults should reproduce exactly this.

## Exact ffmpeg command

```bash
ffmpeg -i input.mp4 -filter_complex "[0:v]scale=iw*2:ih*2:flags=lanczos,eq=saturation=2.60:contrast=1.35,bilateral=sigmaS=30:sigmaR=0.1,bilateral=sigmaS=30:sigmaR=0.1,split[f1][f2];[f1]lutyuv=y='floor(val/51)*51':u='round((val-128)/51)*51+128':v='round((val-128)/51)*51+128'[base];[f2]edgedetect=low=0.40:high=0.93,negate,erosion,format=yuv420p[edges];[base][edges]blend=all_mode=multiply:c0_opacity=0.85:c1_opacity=0:c2_opacity=0,scale=iw/2:ih/2:flags=lanczos[out]" -map "[out]" -map 0:a? -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p -c:a copy output.mp4
```

## Batch a folder (Git Bash)

```bash
mkdir -p output
for f in input/*.mp4; do
  ffmpeg -y -i "$f" -filter_complex "[0:v]scale=iw*2:ih*2:flags=lanczos,eq=saturation=2.60:contrast=1.35,bilateral=sigmaS=30:sigmaR=0.1,bilateral=sigmaS=30:sigmaR=0.1,split[f1][f2];[f1]lutyuv=y='floor(val/51)*51':u='round((val-128)/51)*51+128':v='round((val-128)/51)*51+128'[base];[f2]edgedetect=low=0.40:high=0.93,negate,erosion,format=yuv420p[edges];[base][edges]blend=all_mode=multiply:c0_opacity=0.85:c1_opacity=0:c2_opacity=0,scale=iw/2:ih/2:flags=lanczos[out]" \
    -map "[out]" -map 0:a? -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p -c:a copy "output/$(basename "${f%.*}")_comic.mp4"
done
```

## Slider equivalents (Halftone tuner)

| Control      | Value |
|--------------|-------|
| Saturation   | 2.60  |
| Contrast     | 1.35  |
| Flatten strength | 6  (bilateral sigmaS=30) |
| Flatten passes   | 2  |
| Color levels     | 5  (lutyuv step 51) |
| Ink threshold    | 0.80 (edgedetect low 0.40 / high 0.93) |
| Ink thickness    | 1  (one erosion) |
| Ink darkness     | 0.85 (blend c0_opacity) |
| Edges            | on |
| Clean edges (2× supersample) | on |

## What each stage does
- `scale 2x lanczos` → supersample for clean, anti-aliased ink lines (scaled back down at the end)
- `eq` → saturation 2.6, contrast 1.35
- `bilateral ×2` → edge-preserving flatten into solid color blocks (graphic, not blurry)
- `lutyuv` → posterize luma + chroma to ~5 coherent levels (YUV so hues stay clean)
- `edgedetect → negate → erosion` → bold black ink outlines
- `blend multiply` (luma-only, c1/c2 opacity 0) → outlines darken without color cast

# Spider Night: making the art in an image generator

This guide is for making the **Spider Night** theme's pictures (icon tile, city skyline, spider web) in an outside image generator (ChatGPT / GPT-Image, Midjourney, Stable Diffusion, Firefly…) instead of using the art the script draws. It has the prompts, the exact file rules, and the one command that puts everything into the app.

The theme itself (colours, animation, fonts, store banner) is defined in [tool/seed/spider_night.dart](../tool/seed/spider_night.dart). The script draws its own placeholder art. You don't have to replace all of it: any file you leave out keeps the drawn version.

---

## 1. What is a picture, and what is animation

The live wallpaper is built from layers, back to front. Only the **bold** ones are pictures you can generate. Everything else is drawn and animated by the app, so **don't paint it into your pictures**, or it will appear twice.

| # | Layer | Made by | Moves? |
|---|---|---|---|
| 1 | Night sky gradient (navy → purple) | app | no |
| 2 | Stars | app | twinkle |
| 3 | Red moon with glow | app | pulses |
| 4 | **Spider web**, top-left corner, shown at 55 % opacity | **you** | no |
| 5 | Spider hanging on a thread | app | swings |
| 6 | **City skyline**, along the bottom | **you** | no |
| 7 | Rain | app | falls |

Plus the **icon tile** (Web Slinger icon pack): the picture every app's own logo sits on.

So the skyline and the web must have a **transparent (or green-screen) background**: the sky, moon and stars show through them.

---

## 2. The files

Put the generator's output here (this folder is git-ignored; only the processed copies get committed):

```
tool/seed/incoming/spider-night/
├── skyline.png          ← city skyline on green
├── web.png              ← spider web on green
└── icons/
    └── background.png   ← the icon tile, under every app's logo
```

- **Formats:** PNG, JPG or WebP. The name before the extension must match exactly.
- **Any size.** The import step resizes for you:
  - the icon tile: centre-cropped to a square, resized to 256 × 256
  - skyline and web: resized to 1080 px wide, keeping their shape
- **Transparency:** if your generator can export a transparent PNG (GPT-Image's "transparent background" option), use it. Otherwise ask for a **solid pure green `#00FF00` background**; the import step turns it transparent. It only does this when at least one corner of the picture is green, so leave one corner empty.
- **The icon tile doesn't need transparency.** Fill the whole square edge to edge. The app cuts it to the pack's shape (rounded square, circle, square or leaf; the user picks) and draws the border itself, so don't draw your own rounded corners or border.

---

## 3. One style for everything

Paste this **style block** into every prompt, so the 3 pictures look like one set:

> Flat vector illustration, bold comic-book style, clean shapes, thick black ink outlines, limited palette: spider red #E23636, deep red #8E0E14, night navy #0B1026, near-black #05070F, white #F5F1EA, warm window yellow #FFD27A. No text, no letters, no logos, no watermark, no people.

**Don't write "Spider-Man" (or Marvel, Miles Morales, etc.) in prompts.** Many generators refuse it or blur the result, and art that copies the character, suit or logo can't be shipped without a Marvel licence. Describe the look instead: red and black, webs, a spider, a night city.

**Tips per tool:**
- **ChatGPT / GPT-Image:** ask for "transparent background, PNG". Sizes: 1024 × 1536 for the skyline, 1024 × 1024 for the web and icons.
- **Midjourney:** add `--ar 2:3 --style raw` (skyline), `--ar 1:1 --style raw` (web, icons). Use `--sref <url of your first good icon>` on the other 19 so they match. It can't export transparency: use the green background.
- **Stable Diffusion:** negative prompt: `text, letters, watermark, logo, photo, 3d render, gradient background, people, character, blurry`.

---

## 4. Scene prompts

### 4.1 `skyline.png`: the city along the bottom

> [style block] A night city skyline seen straight from the front: a row of tall, flat-topped skyscrapers of different heights, near-black navy (#05070F), with small warm yellow (#FFD27A) lit windows in neat grids, a classic wooden water tower on one rooftop, a thin antenna with a red light on another, and a thin red rim light along the rooftop edges as if lit by a red moon. The buildings rise from the very bottom edge and fill the lower half of the image; the tallest rooftop stays below the middle. Everything above the rooftops is a solid flat pure green #00FF00 background. No sky, no moon, no stars, no clouds, no rain, no ground, no street. Portrait 2:3.

Check before using it:
- The background above the buildings is **one flat green**, with no gradient or shading.
- The buildings reach the **bottom edge** across the full width (the layer is pinned to the bottom of the screen).
- Rooftops stay in the lower half, so they don't cover the moon.
- No moon or rain is painted in (the app draws those).

### 4.2 `web.png`: the corner web

> [style block] A large spider web anchored in the top-left corner, fanning out across the image: about ten straight radial strands from the corner, connected by many curved threads that sag slightly toward the corner, delicate thin white (#F5F1EA) silk lines with even thickness. The web covers the top-left two thirds; the bottom-right corner is empty. No spider, no dew drops, no moon. Solid flat pure green #00FF00 background. Square 1:1.

Check before using it:
- Lines are **white or very light**. The app shows the web at 55 % opacity over the sky, so dark lines would disappear.
- The **bottom-right corner is plain green** (that's how the import step knows to remove the green).
- **No spider** in it. The swinging spider is animated by the app.

---

## 5. Icon tile prompt

> [style block] A square tile, filled edge to edge with spider red (#E23636), a thin dark red spider-web pattern radiating from the centre across the whole square. Nothing in the centre: leave the middle half calm and plain. Flat, no rounded corners, no border, no shadow, no text. Square 1:1.

Save it as `icons/background.png`. wallp Home puts **every** app on it, with the app's own logo (WhatsApp's bubble, Shopee's bag…) in the middle; there are no per-app pictures to make.

Check it:
- **Red reaches all four edges** (no white margin, no rounded corners).
- **The middle is calm.** A busy centre fights with the logos.
- **White logos still read on it.** Most logos are white or brightly coloured.

---

## 6. Build it

From the project root:

```sh
tool/seed/spider_night.sh --external
```

That runs four steps:

1. **Import:** reads `tool/seed/incoming/spider-night/`, crops and resizes each picture, makes the green background transparent, and saves the results over the drawn art in `tool/seed/source/`. Imported files are listed in `tool/seed/source/external-art.txt`.
2. **Render:** redraws the art that **wasn't** imported (and leaves the imported files alone).
3. **Generate:** hashes the pictures into the demo catalog, `assets/mock/catalog/v1/`, and checks it through the app's own parser.
4. **Preview:** draws the result into `build/spider-night-preview/`:
   - `scene-0.0.png`, `scene-1.3.png`, `scene-2.6.png`: the live wallpaper at three moments (the spider swings, the moon pulses)
   - `still.png`: the "Web Corner" still wallpaper
   - `icons.png`: the tile under a symbol for each kind of app, on the wallpaper, as the store's previews show it

Later runs **without** `--external` keep your imported pictures. To replace only some, put just those files in `incoming/` and run `--external` again. To go back to the drawn art:

```sh
tool/seed/spider_night.sh --drawn
```

---

## 7. Check it, then ship it to the app

1. **Look at the previews.** Common problems:

   | You see | Fix |
   |---|---|
   | A green box or green fringe around the skyline or web | The background wasn't one flat green. Regenerate with "solid flat pure green #00FF00", or remove the background in another tool and save a transparent PNG |
   | The web isn't see-through at all | No corner was green. Leave the bottom-right corner empty |
   | Buildings cover the moon | Ask for lower buildings ("tallest rooftop below the middle") |
   | Logos are hard to see on the tile | Ask for a calmer, plain middle, and less bright web lines |
   | Two spiders or two moons | Remove the spider or moon from your picture: the app draws them |

2. **Check the size.** Step 3 prints the demo catalog size (about 2.6 MB with the drawn art). Busy, detailed pictures make big PNGs, and every user downloads them when applying the theme. Keep the skyline and web under about 1 MB each; flat colours compress best.

3. **Bump the revisions in [tool/seed/spider_night.dart](../tool/seed/spider_night.dart) and [tool/seed/seed_data.dart](../tool/seed/seed_data.dart)** when you change art the app has already shown:
   - `rev: 1` → `rev: 2` on the Spider Night theme. Phones cache theme files by `rev` and never re-read one they have, so without this they keep the old pictures.
   - `demoRevision` +1 in `seed_data.dart` (with a note on the comment above it). Phones only download a catalog whose version is new.

   Then run `tool/seed/spider_night.sh` again.

4. **Run the tests:** `flutter test`. `test/catalog/demo_catalog_test.dart` checks every file's hash and that nothing is missing.

5. **Try it on the phone:** run the app, go to Store → Themes → Spider Night → Apply, and pick "Live wallpaper (animated)".

6. **Commit** the processed pictures in `tool/seed/source/` (including `external-art.txt`) and the regenerated `assets/mock/catalog/v1/`. `tool/seed/incoming/` is git-ignored.

---

## 8. Changing more than the art

All in [tool/seed/spider_night.dart](../tool/seed/spider_night.dart), then run `tool/seed/spider_night.sh` and bump the revisions (section 7.3):

- **Colours:** `_spiderPalette` (sky, ground, moon) and `_spiderAccents` (the accent choices on the theme page).
- **Animation:** `_spiderScene`: moon size and position, star and rain `count` / `speed` (max 150 particles a layer), the web's `opacity`. Particle effects available: `snow`, `rain`, `drops`, `bats`, `lanterns`, `petals`, `sparkles`, `stars`. Shape motions: `float`, `pulse`, `sway`.
- **The spider:** `_spider`: where it hangs (`x`, `y`), the box size `_spiderWidth` / `_spiderAspect`, and its leg shapes.
- **Names, fonts, banner text:** `buildSpiderNight`.

The full layer format is in [theme-api.md §4.9](theme-api.md#49-layers-scene-engine-layers).

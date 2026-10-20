# Icon tile: a prompt template for any image generator

A fill-in-the-blanks prompt for making an **icon pack tile** (the `background` of an `images` icon pack) in an outside image generator: ChatGPT / GPT-Image, Midjourney, Stable Diffusion, Firefly… Fill in the slots, paste, generate, check, upload.

The tile is **one picture per pack**. wallp Home puts every app's own logo (WhatsApp's bubble, Shopee's bag…) in the middle of it, so there are no per-app pictures to make. The rules come from [theme-api.md §4.7](theme-api.md#47-iconpack); Spider Night's own art guide is [spiderman-script.md](spiderman-script.md).

---

## 1. The rules every tile follows

| Rule | Why |
|---|---|
| **Square, filled edge to edge** | The app clips it to the user's shape (squircle, circle, square or leaf). A margin shows up as a white edge |
| **No rounded corners, no border, no shadow** | The app draws the rim itself, in the pack's `ring` colour, along whichever shape the user picked |
| **Calm middle half** | A logo sits there. Busy detail in the centre fights with it |
| **Dark or deep enough that white logos read** | Most logos are white or bright |
| **No text, no logos, no app symbols** | Real app logos go on top |
| **Flat colours** | It's the pack's only download; aim for a few dozen KB |

---

## 2. The template

Fill in the `{slots}` (section 3), then paste the whole block:

> A square app icon background tile, filled edge to edge with {base colour name} ({base hex}). {pattern}, in {pattern colour name} ({pattern hex}), kept to the outer edges and corners of the tile. The middle half of the tile is calm and plain: only the flat base colour, maybe a very soft {glow colour name} ({glow hex}) glow. {style}. Flat 2D design, no rounded corners, no border, no frame, no drop shadow, no 3D bevel. No text, no letters, no logos, no app symbols, no icons, no watermark, no people, no characters. Square 1:1.

**Negative prompt** (Stable Diffusion, or Midjourney `--no`):

```
text, letters, logo, watermark, icon, symbol, app, rounded corners, border, frame, drop shadow, bevel, 3d, photo, person, character, busy center, white background
```

---

## 3. The slots

| Slot | What to write | Example |
|---|---|---|
| `{base colour name}` / `{base hex}` | The tile's main colour. Usually the pack's `tile` colour, so the stand-in shown while it downloads matches | `midnight purple` / `#1A0B2E` |
| `{pattern}` | One simple motif from the theme, described as a shape, not a character or brand | `thin bare tree branches reaching in from the corners` |
| `{pattern colour name}` / `{pattern hex}` | Lower contrast than the logos will be: a darker or lighter shade of the base | `dark violet` / `#3B1F5C` |
| `{glow colour name}` / `{glow hex}` | Optional soft light behind the logo; delete the phrase if not wanted | `pumpkin orange` / `#FF7A1A` |
| `{style}` | The theme's art style, the same words as its wallpaper prompts so the set matches | `Flat vector illustration, clean shapes, limited palette` |

**Choosing the pack's three colours** to go with the tile (set them in the dashboard's icon pack editor or the seed file):

- `tile`: the base hex.
- `ring`: a colour that frames the tile on the wallpaper. Darker than the base for bright tiles, the accent for dark ones.
- `glyph`: the colour of the sample symbols in store previews. Usually `#FFFFFF`.

---

## 4. Filled-in examples

Each one is ready to paste. Swap colours to match your theme.

### Halloween: spooky

> A square app icon background tile, filled edge to edge with midnight purple (#1A0B2E). Thin bare tree branches and a few tiny bats reaching in from the corners, in dark violet (#3B1F5C), kept to the outer edges and corners of the tile. The middle half of the tile is calm and plain: only the flat base colour, maybe a very soft pumpkin orange (#FF7A1A) glow. Flat vector illustration, eerie, clean shapes, limited palette. Flat 2D design, no rounded corners, no border, no frame, no drop shadow, no 3D bevel. No text, no letters, no logos, no app symbols, no icons, no watermark, no people, no characters. Square 1:1.

Pack colours: `tile #1A0B2E`, `ring #FF7A1A`, `glyph #FFFFFF`.

### Christmas: snowy

> A square app icon background tile, filled edge to edge with pine green (#0F3D2E). Small snowflakes and tiny pine sprigs scattered along the edges, in soft frost white (#CFE8E0) at low contrast, kept to the outer edges and corners of the tile. The middle half of the tile is calm and plain: only the flat base colour, maybe a very soft warm gold (#FFD27A) glow. Flat vector illustration, cosy winter, clean shapes, limited palette. Flat 2D design, no rounded corners, no border, no frame, no drop shadow, no 3D bevel. No text, no letters, no logos, no app symbols, no icons, no watermark, no people, no characters. Square 1:1.

Pack colours: `tile #0F3D2E`, `ring #C8102E`, `glyph #FFFFFF`.

### Thingyan: water festival

> A square app icon background tile, filled edge to edge with deep water blue (#0B4F8A). Curling water splashes and small padauk flowers along the edges, in light aqua (#5FC3E4) and padauk yellow (#F6C344), kept to the outer edges and corners of the tile. The middle half of the tile is calm and plain: only the flat base colour, maybe a very soft light aqua (#5FC3E4) glow. Flat vector illustration, joyful Myanmar new year, clean shapes, limited palette. Flat 2D design, no rounded corners, no border, no frame, no drop shadow, no 3D bevel. No text, no letters, no logos, no app symbols, no icons, no watermark, no people, no characters. Square 1:1.

Pack colours: `tile #0B4F8A`, `ring #F6C344`, `glyph #FFFFFF`.

### Neon: cyberpunk night

> A square app icon background tile, filled edge to edge with near-black navy (#07071A). Thin glowing neon grid lines and short circuit traces along the edges, in magenta (#FF2BD6) and cyan (#22E4FF), kept to the outer edges and corners of the tile. The middle half of the tile is calm and plain: only the flat base colour, maybe a very soft violet (#7B2BFF) glow. Synthwave neon style, clean thin lines, limited palette. Flat 2D design, no rounded corners, no border, no frame, no drop shadow, no 3D bevel. No text, no letters, no logos, no app symbols, no icons, no watermark, no people, no characters. Square 1:1.

Pack colours: `tile #07071A`, `ring #22E4FF`, `glyph #FFFFFF`.

### Minimal: soft gradient

> A square app icon background tile, filled edge to edge with a smooth diagonal gradient from dusk blue (#2B3A67) to soft plum (#6B3A6B). No pattern. Very subtle fine grain texture. The middle half of the tile is calm and plain. Minimal modern design. Flat 2D design, no rounded corners, no border, no frame, no drop shadow, no 3D bevel. No text, no letters, no logos, no app symbols, no icons, no watermark, no people, no characters. Square 1:1.

Pack colours: `tile #2B3A67`, `ring #FFFFFF`, `glyph #FFFFFF`.

For Spider Night's Web Slinger tile, use the prompt in [spiderman-script.md §5](spiderman-script.md#5-icon-tile-prompt).

---

## 5. Tips per generator

- **ChatGPT / GPT-Image:** 1024 × 1024. If it adds a frame or rounded corners anyway, reply "fill the whole square edge to edge, square corners, no frame".
- **Midjourney:** add `--ar 1:1 --style raw --no text,logo,border,frame,rounded corners`. To match the theme's wallpaper, add `--sref <url of the wallpaper>`.
- **Stable Diffusion:** 1024 × 1024 (SDXL), the negative prompt from section 2, CFG around 6–7.
- **Firefly:** Square 1:1, content type "Art", and turn off any "photo" style.

**Don't name brands or characters** (Spider-Man, Hello Kitty, Pokémon…). Generators refuse or blur them, and the art can't ship without a licence. Describe colours and shapes instead.

---

## 6. Check it before uploading

Shrink the picture to about 64 px (a real icon's size) and put a white logo on it in your head, or in any image editor:

| You see | Fix |
|---|---|
| White or light edge, or rounded corners | Regenerate with "filled edge to edge, square corners", or crop inward a little |
| A border or frame drawn in | Remove "tile" wording that suggests a button; add "no frame" again |
| White logos are hard to see | Darker base colour, lower-contrast pattern |
| The centre is busy | "Pattern only along the outer edges; the middle half is empty" |
| Text or a fake logo appeared | Regenerate; add "no text, no letters" to the start of the prompt |
| File is hundreds of KB | Fewer details and gradients; save as WebP, or run it through a PNG optimiser |

---

## 7. Put it in the app

- **Any final size of 256 px or more** works; square PNG or WebP.
- **Dashboard-made packs:** upload it as the **Background tile** in the icon pack editor ([theme-dashboard.md §4.7](theme-dashboard.md#47-icon-packs)) and set `tile`, `glyph` and `ring`. Check the editor's preview in all four shapes.
- **Spider Night:** save it as `tool/seed/incoming/spider-night/icons/background.png` and run `tool/seed/spider_night.sh --external` ([spiderman-script.md §6](spiderman-script.md#6-build-it)); it's cropped and resized to 256 × 256 for you.
- **Changing a tile the app already shows:** bump the theme's `rev` and the catalog version, or phones keep the cached tile ([spiderman-script.md §7.3](spiderman-script.md#7-check-it-then-ship-it-to-the-app)).

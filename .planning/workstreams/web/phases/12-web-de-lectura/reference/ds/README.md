# Cíngula — Design System

Cíngula is an immersive work (*obra*) that takes place along a trail through native Patagonian forest. It has three simultaneous layers:

1. **A site-specific sound piece**, delivered through a mobile application — audio that is triggered by where the listener physically stands on the trail.
2. **A performative intervention** along the same trail.
3. **A projection with mapping**, on rock, trunk and canopy.

Cíngula is produced by **Tropical Poncho**, whose brand manual supplies this system's colour palette and its central graphic mark. Tropical Poncho's stated purpose, verbatim from the manual: *"Queremos promover el proceso de expansión de la consciencia (introspectiva y colectiva) a través de experiencias artísticas."* Its stated values: *Disfrute/goce · Consciencia · Cooperatividad · Horizontalidad · Comunicación clara · Humildad.*

The system is Spanish-first (Argentine, *voseo*-friendly), dark-ground by default, and built on two motifs that recur in every source material given: **the wave** (sound, frequency, the trail's own meander) and **the portal** (concentric contour rings — the Tropical Poncho mark itself, read as a tree ring, a topographic map and an aperture).

## Sources this system was built from

All were supplied as uploads; a reader of this repo may not have access to them.

| Source | What it gave |
| --- | --- |
| `uploads/tropical poncho - marca final.pdf` (8 pp., brand manual) | Colour palette (p.3), isologo / logotipo / isologotipo lockups (p.2), colour + monochrome variants (pp.4–5), typography page (p.6), flyer application (p.7) |
| `uploads/moodboard implicito.jpg` | Implicit moodboard: tarot cards (Rider–Waite *The Star*), waveform and Lissajous/frequency plates, hand-ink notebook sketches, Patagonian landscape photography, chord/network diagrams, the palette strip |
| `uploads/20260810_185420.jpg` | Hand-drawn project map naming the constellation of works: **CÍNGULA**, *Cíngula Festival*, MINGA, SINAPSIS, MURMULLOS, VECTORES, CUARTO VOLCÁN, and the phrase *"Portales Espacio/Sonoros"* |
| `uploads/Chillax_Complete/`, `uploads/Synonym_Complete/` | The webfonts (Fontshare / Indian Type Foundry), complete with OTF, TTF, variable and web builds |

Copies of what this system actually uses live in `assets/` (logo crops, fonts, moodboard, sketch map).

**Note on typography.** The Tropical Poncho manual (p.6) specifies *Roboto* and *Gotham*. The fonts uploaded for Cíngula are **Chillax** and **Synonym**, and this system uses those — Chillax sits in the same modern-geometric register as the TROPICAL PONCHO wordmark while reading as its own voice for the obra. No font substitution was needed; all binaries were provided.

---

## Content fundamentals

**Language.** Spanish, Argentine register. Voseo is welcome in second person (*"Caminá despacio"*, not *"Camina despacio"*). English appears only as a secondary layer for visiting audiences, never mixed inside a sentence.

**Person.** The work addresses **you**, singular, in the imperative or the invitation — never a crowd and never "users". *"Ponete los auriculares."* *"Vas a escuchar el bosque antes de verlo."* Institutional copy (credits, funding, press) switches to a plain third person: *"Cíngula es una obra inmersiva de Tropical Poncho."* We ("nosotros") is reserved for statements of intent, as in the manual's own *"Queremos promover…"*.

**Tone.** Mystical but concrete. The vocabulary is spatial and physical — *sendero, portal, umbral, capa, frecuencia, murmullo, bosque nativo, presente* — and instructions are literal. Symbolism is carried by the images and the naming, not by adjectives. No spiritual-wellness cliché, no "journey of self-discovery", no exclamation marks.

**Sentence length.** Short. Most lines are under twelve words; long lines are broken as verse rather than paragraphs when they appear in the app or in projection.

**Casing.** Title-case is not used. Three registers only:
- `CÍNGULA` — the name and section markers, uppercase, letterspaced `--ls-portal` (`.42em`).
- `PORTAL 03 · 1.2 KM` — metadata and labels, uppercase, `--ls-label` (`.12em`).
- Sentence case for everything else, including headings.

**Numbers.** Dates as `22.01.22` (the flyer convention from the manual, p.7). Distances in km with one decimal. Times in 24h. Durations as `48 min`.

**Emoji.** Never. Not in the app, not in social copy, not in the system. Where a glyph is needed, the portal mark or a wave rule does the work.

**Examples of correct copy**

> CÍNGULA
> Una obra para caminar y escuchar
>
> Sendero Cerro Amigo · El Bolsón · 48 min
> Ponete los auriculares antes de cruzar el primer portal.

> PORTAL 04 — MURMULLOS
> Estás a 120 m. El audio empieza solo.

> Esta obra no debe ser leída. Debe ser caminada.

**Examples to avoid**

> ✨ ¡Descubrí tu viaje interior! Una experiencia única que transformará tu vida.

> Welcome, users! Tap here to start your Cíngula Experience™.

---

## Visual foundations

### Ground and colour

The default ground is **near-black with a violet cast** (`--ink-900` `#08070B`) — the obra happens at dusk, in a forest. Light surfaces (`[data-theme="claro"]`) exist for printed matter, tickets and documents, and use a warm paper (`--paper-100` `#F7F5F2`), never pure white as a field.

The palette is taken verbatim from the brand manual: **mint `#8AE2C8`, azure `#578CCB`, violet `#9900FF`, magenta `#FF0074`, amber `#FFBC00`**, with `#111111` and `#FFFFFF`. The manual describes them as the rainbow with small modifications, and they are the five rings of the portal mark, outer to inner. Treat them as a *sequence*, not a set: when several hues appear together, they appear in ring order. A composition uses one hue as accent plus the ground; two accents is the ceiling; all five appear only as the aurora gradient or the mark itself.

Semantic mapping is deliberately borrowed rather than invented — mint = ready/available, magenta = live/now, amber = waiting/attention, azure = information, ink-200 = inactive. No new hues are ever introduced for status.

**Gradients** are permitted and are part of the brand (manual, pp.4–5: *"Las transiciones de color entre los colores de la paleta cromática son posibles en esta marca"*). Only two forms are used: `--grad-aurora` (linear, ring order, left to right — used as a 2–3px rule, a wordmark fill, or a full-bleed band) and `--grad-portal` (radial, amber core to mint rim — used behind the mark or as an aperture). Nothing else. No two-stop blue-purple "SaaS" gradients, ever.

### Type

Chillax (display) and Synonym (text). Display sizes run **light (300) at large sizes** — the wordmark's own logic — and step up to medium (500) only below 25px. Body copy is Synonym Regular at 17px/1.62. The signature typographic move is **extreme letterspacing on uppercase display lines** (`.42em`), which turns a word into a row of standing elements. Never letterspace lowercase running text.

Headings are sentence case and never bold. Small labels are uppercase Chillax Medium at 12px with `.12em` tracking. Body copy sets to a 60rem measure maximum; poetic/app text sets to 44rem and is broken by line, not wrapped.

### Layout

A 12-column grid on web with `--gutter-desktop` (40px) margins; a single column with 20px gutters on mobile. Vertical rhythm is the 4px spacing scale, but section spacing jumps to `--sp-24`/`--sp-32` — the system prefers a clearing to a comfortable gap. Full-bleed is the default for imagery and for section openers; contained-and-centred is for reading.

Fixed elements: a translucent top bar on web (`--surface-veil` + `--backdrop-veil`), and in the app a fixed bottom "trail" bar carrying the current portal and playback. Nothing else is sticky.

### Imagery

Photographic, **cool and atmospheric**: Patagonian ridge lines, cloud seas, lakes at dusk, silhouetted figures at distance. Slight analogue grain (`--grain-opacity` .055) and lifted blacks. Warm frames (fire, sunset) appear as punctuation, roughly one in five. People are always small in the frame and rarely identifiable. Photography is duotoned toward the ground colour when text must sit over it, with `--grad-veil` as the protection gradient — a bottom-up veil, never a flat black scrim and never a rounded caption capsule.

The second image family is **hand-ink drawing**: notebook line work, contour rings, spiky seed-forms, ink trees, tarot-plate compositions (the moodboard's *The Star* is the reference for framing: a centred figure, a symmetrical border, symbols at the corners). These are used at 100% black or 100% paper, never coloured, and never mixed into the same frame as photography.

### The two motifs

**Wave.** A single-stroke sine or beat-frequency line, `--wave-stroke` (1.25px), drawn edge-to-edge as a divider, a progress track, or a full-bleed backdrop at 12% opacity. Waves are generated from a formula, so they can drift; they are never a decorative squiggle.

**Portal.** Concentric closed contours, uneven spacing, hand-varying line weight. Used as: the logo mark; a card shape (`--r-portal`, an asymmetric organic radius); a loading/listening state (rings dilating outward); and the transition between screens (an aperture that opens from the point touched).

### Borders, radii, cards

Radii are generous — `--r-md` 14px for controls, `--r-lg` 22px for cards, `--r-pill` for chips and buttons. Cards on the dark ground are `--surface-card` (`#17151E`) with a 1px hairline at 12% white and `--shadow-card`; depth on a near-black ground comes from a light top edge, not from a drop shadow. On paper, cards are white with `--shadow-print` and no border. There is no "coloured left border" card. Corners are never square except for full-bleed media and tables.

### Shadows, glow, transparency, blur

Two systems. **Shadow** for physical depth (cards, sheets, printed matter). **Glow** for aliveness — `--glow-mint`, `--glow-violeta`, `--glow-magenta` — applied only to elements that are currently *live*: a playing portal, a focused field, an active projection cue. Glow is never decorative.

Transparency and blur appear in exactly two places: the fixed top bar / bottom trail bar (`--surface-veil` over `--backdrop-veil`), and modal veils. Nothing else is frosted.

### Animation

Everything drifts or breathes; nothing bounces. `--ease-drift` for UI, `--ease-emerge` (16,1,.3,1) for content arriving, `--ease-portal` for aperture transitions. Durations: 180ms for state, 320ms for movement, 640ms for content, 1200ms for veils, and a 6s `cg-breath` loop for the portal pulse and aurora drift. Entrances are a 10px rise plus fade. Exits are fade only. `prefers-reduced-motion` collapses all of it.

### States

- **Hover:** lighten. Primary buttons go violet → `--violeta-soft`; ghost buttons gain a 28%-white border; links move mint → mint-soft and the underline reaches full opacity. Never darken on the dark ground; never scale on hover.
- **Press:** `--press-scale` .985 plus the hover colour held. No shadow change.
- **Focus:** `--glow-focus` — a 2px ground gap and a 2px mint ring. Always visible, never removed.
- **Disabled:** 38% opacity, no colour change, `cursor:not-allowed`.
- **Live/now:** magenta plus a slow breathing glow. Reserved.

---

## Iconography

**No icon set was supplied in the sources** — the brand manual contains only the logo lockups, and no product code or Figma file was provided. Accordingly:

- **The portal mark is the primary glyph.** `assets/logo-mark-color.png` and `assets/logo-mark-mono.png` are the real thing, extracted from the manual; use the mark where another brand would use an app icon, a bullet, a section marker or a favicon.
- **The wave rule** (`AuroraRule`, `WaveLine`) substitutes for decorative dividers and progress metaphors.
- **UI icons are Lucide** (`https://unpkg.com/lucide-static`), 1.5px stroke, 20/24px, `currentColor`, round caps — chosen because its stroke weight and rounded terminals match the hand-drawn line of the mark. **This is a substitution and should be confirmed:** if Cíngula has or wants its own drawn glyph set (the notebook sketches suggest it easily could), replace it and update this section. Icons are never filled, never two-tone, never in more than one hue per screen.
- **Unicode** is used for two things only: the middle dot `·` as the metadata separator (`PORTAL 03 · 1.2 KM`) and the em dash. No arrows-as-icons.
- **Emoji: never.**

No logo was created for Cíngula — none exists in the sources. Wherever a Cíngula mark would go, the name is set in plain type (Chillax Light, uppercase, `--ls-portal`), optionally accompanied by the Tropical Poncho portal mark as the producing brand. **Do not draw or reconstruct a Cíngula logo.**

---

## Index

**Root**
- `styles.css` — the single entry point consumers link. `@import`s only.
- `readme.md` — this file.
- `SKILL.md` — Agent-Skill wrapper.
- `thumbnail.html` — homepage tile.

**`tokens/`** — `fonts.css` (@font-face), `colors.css`, `typography.css`, `spacing.css`, `effects.css`, `motion.css`, `base.css`.

**`assets/`** — `logo-tropical-poncho-vertical.png`, `logo-tropical-poncho-horizontal.png`, `logo-tropical-poncho-horizontal-light.png` (white type — the only lockup legible on the dark ground), `logo-mark-color.png`, `logo-mark-mono.png`, `logo-mark-light.png`, `logo-wordmark.png`, `moodboard.jpg`, `sketch-cingula-map.jpg`, `fonts/` (Chillax + Synonym woff2).

**`guidelines/`** — foundation specimen cards (colour, type, spacing, motif, brand).

**`components/`**
- `brand/` — `PortalMark`, `WaveLine`, `AuroraRule`
- `core/` — `Button`, `IconButton`, `Card`, `Badge`, `Tag`, `Icon`
- `forms/` — `Input`, `Select`, `Checkbox`, `Radio`, `Switch`, `Slider`
- `feedback/` — `Dialog`, `Toast`, `Tooltip`
- `navigation/` — `Tabs`, `TopBar`

**`ui_kits/`**
- `app/` — the Cíngula mobile app: onboarding, trail map, portal player, credits. Interactive click-through.
- `web/` — the obra's public site: hero, programme, and reservation.

**Intentional additions.** No source defined a component inventory, so the set above is a standard primitive kit sized to the two surfaces, plus three brand-motif components (`PortalMark`, `WaveLine`, `AuroraRule`) that exist because the wave and the portal are load-bearing in this brand and should not be re-drawn ad hoc, and an `Icon` wrapper over Lucide (the sources contain no glyph set — see Iconography).


## Using this system

- **Stylesheets, in this order:** `tokens.css` (generated from `tokens.json`: colours for the `oscuro` and `claro` themes, type, spacing, radii, shadows and the `@font-face` rules), then `components/bundle.css` (gradients, type shorthands such as `--type-body`, motion, the base layer and the keyframes). Dark is the default ground; `data-theme="claro"` on an ancestor switches to the light scope.
- **Fonts:** `fonts/` holds the Chillax and Synonym woff2 files that `tokens.css` names; copy them beside it. Licence: `assets/fonts/LICENSE-FFL.txt`.
- **Scripts:** React 18 and ReactDOM 18, then `components/bundle.js`, which defines `window.CNgulaDesignSystem_fa472e`. `Icon` (and anything using it) also needs `https://unpkg.com/lucide@0.468.0/dist/umd/lucide.js`.
- **Logos:** `assets/logo-*.png`. `PortalMark` takes a `base` prop and `TopBar` an `assetBase` prop with the path to that folder.
- **Per component:** properties in `components/index.d.ts`, guidelines in `components/<Name>/README.md`, sources in `components/src/`.

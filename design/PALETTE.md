# Data-visualisation palette — derivation and evidence

Every colour in `src/tokens.css` is either specified by the UI/UX guideline or
derived here and machine-checked. Nothing was picked by eye. This file is the
audit trail for the derived values.

Validator: the `dataviz` skill's `scripts/validate_palette.js`. ΔE throughout is
Euclidean distance in OKLab × 100. CVD simulation is Machado–Oliveira–Fernandes
2009 at severity 1.0, under both protanopia and deuteranopia.

Surfaces validated against are BMD's own, not the validator's defaults:

| Mode | Chart surface | Token |
|------|---------------|-------|
| Light | `#FFFFFF` | `surface.elevated` |
| Dark | `#161A2E` | `surface.elevated` (dark) |

---

## Categorical — series identity

Constraints going in:

1. **Slot 1 is fixed to brand red `#E71E25`.** Guideline §4.2 permits exactly one
   principal chart series in brand red.
2. **No slot may impersonate a reserved semantic hue** (`#1F7A4D` success,
   `#B54708` warning, `#B42318` error, `#175CD3` info).
3. Brand navy `#2B3674` sits at OKLCH L ≈ 0.36, below the light-mode band floor
   of 0.43, so it is lifted to `#3B4A96` — hue held, lightness moved. This is the
   documented "snap-to-passing" step, not a new colour.

Method: `design/scripts/derive_palette.mjs` enumerated every ordering of six hue
families drawn from a seven-family pool with slot 1 pinned, and every lightness
step per family, keeping only orderings that clear **all** gates in **both**
modes, then maximised the weakest adjacent CVD pair.

**Winning order: brand red → navy → ochre → violet → olive → magenta**

| Slot | Hue | Light | Dark |
|------|-----|-------|------|
| 1 | brand red | `#E71E25` | `#E71E25` |
| 2 | navy | `#3B4A96` | `#4657AE` |
| 3 | ochre | `#CA8A04` | `#B87309` |
| 4 | violet | `#6D28D9` | `#6D28D9` |
| 5 | olive | `#4D7C0F` | `#65A30D` |
| 6 | magenta | `#E85D95` | `#BE185D` |

### Results

| Check | Light (on `#FFFFFF`) | Dark (on `#161A2E`) | Gate |
|---|---|---|---|
| Lightness band | all 6 inside L 0.43–0.77 | all 6 inside L 0.48–0.67 | PASS |
| Chroma floor | all 6 ≥ 0.10 | all 6 ≥ 0.10 | PASS |
| Adjacent CVD ΔE | **15.9** (`#E85D95`↔`#4D7C0F`, protan) | **14.8** (`#BE185D`↔`#65A30D`, deutan) | target ≥ 8 — PASS |
| Adjacent normal-vision ΔE | **32.6** | **29.4** | floor ≥ 15 — PASS |
| Contrast vs surface | ochre 2.94:1 | navy 2.65 · violet 2.42 · magenta 2.85 | RELIEF REQUIRED |

Both modes clear the CVD target with roughly twice the required margin, and the
normal-vision floor with roughly twice the required margin.

### The relief obligation — not optional

Four slots sit below 3:1 against their own surface. Under the method that is
legal **only** where the value is readable another way. Every chart in this
system therefore ships:

* visible direct labels on the marks, and
* a table view toggle carrying the same numbers.

Removing either one makes the palette non-compliant. This is why
`components/charts.html` shows a `Chart / Table` switch on every figure — it is a
compliance mechanism, not a convenience.

### Series versus status

Status hues are reserved and never become "series 7". Where a series *means*
good or bad — verification outcome, pass/fail — it wears the status tokens with
an icon and a label. Where it is just identity — product, territory, campaign —
it wears a categorical slot. Never both in one chart.

---

## Ordinal — the conversion funnel

Funnel stages (target → registered → captured → verified) are **ordinal**:
swapping them changes the meaning, so colour must carry the order. That means one
hue with monotone lightness steps, not categorical hues.

Hue: BMD navy, the guideline's information-hierarchy colour.
Validated with `validateOrdinal` (`design/scripts/derive_ordinal.mjs`).

| Mode | Steps | Light-end contrast | Result |
|------|-------|--------------------|--------|
| Light | `#97A2DC` `#7382CC` `#5566C4` `#3B4A96` `#2B3674` | 2.47:1 (floor 2.0) | PASS |
| Dark | `#C3CAEE` `#A3ADE1` `#7E8CD1` `#5A6BC7` `#4657AE` | 2.65:1 (floor 2.0) | PASS |

Both ramps are monotone in lightness, hold adjacent ΔL ≥ 0.06, and keep a single
hue (spread ≤ 5°). The dark ramp reverses anchor — the far end of the sequence
carries the light steps — so no stage sinks into the dark surface.

Match bands (High / Medium / Low) are also ordinal and reuse this ramp.
"No reference" is not a band but a state, so it takes `semantic.warning`.

---

## Semantic status — from the guideline, checked

These four are specified in guideline §4.1; they were checked, not chosen.

| Role | Hex | Text contrast on `#FFFFFF` | AA normal text (4.5:1) |
|------|-----|---------------------------|------------------------|
| success | `#1F7A4D` | 5.32:1 | PASS |
| warning | `#B54708` | 5.43:1 | PASS |
| error | `#B42318` | 6.57:1 | PASS |
| info | `#175CD3` | 5.99:1 | PASS |

In dark mode these four are re-stepped (`#4ADE80`, `#FDBA4D`, `#FF8A80`,
`#7DB0FF`) to clear AA against `#161A2E`. The light values would fail there.

### One value that deliberately fails

`brand.primary.600 #E71E25` is **4.4:1** on white — below the 4.5:1 normal-text
floor. It is therefore never used as body text. It is legal on a filled button
(white on red is the same 4.4:1, which clears the 3:1 large-UI-text bar for a
14px 600 label), as a 12px 600 micro-label on a tonal ground, and as a chart
mark. This is recorded here so the failure is a known, bounded decision rather
than an oversight someone "fixes" later by using red for a paragraph.

---

## Reproducing

```bash
node design/scripts/derive_palette.mjs   # enumerate + validate the categorical set
node design/scripts/derive_ordinal.mjs   # validate the funnel ramp
```

Both scripts import the validator directly from the `dataviz` skill, via an
absolute path at the top of each file. That path points into a versioned skill
directory, so update the import if the skill moves or you vendor the validator
into this repo. If a brand
hue ever changes, re-run them rather than adjusting a hex by hand — the ordering
is the CVD-safety mechanism, and it does not survive manual edits.

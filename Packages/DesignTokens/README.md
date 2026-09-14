# DesignTokens

Plain-data port of the Bluesky **ALF** design tokens for the Swift rewrite
(`social-app-swift`). This is a **🌐 Linux-verifiable package**: it holds no
platform types, imports no UI framework, and every value is a `String`, `Double`
or `enum`. It exists so the tokens that drive the SwiftUI layer
(`Packages/DesignSystem`) can be validated on Linux, independent of a macOS
runner.

## Provenance

All values are transcribed from two read-only sources:

1. **`@bsky.app/alf@0.1.15`** (MIT) — the upstream design system package, from
   its `src/tokens.ts`, `src/palette.ts` and `src/themes.ts`.
   <https://github.com/bluesky-social/toolbox/tree/main/packages/alf>
2. **`social-app` `src/alf`** — the React Native app's ALF layer, from
   `src/alf/tokens.ts` (gradients), `src/alf/fonts.ts` (font scaling) and
   `src/alf/themes.ts` (theme composition).

Both sources are Bluesky code and reuse is cleared. The ALF package is MIT
licensed; its copyright and license notice are retained here for attribution.

## How the themes were composed

The RN app does **not** override any palette. `src/alf/themes.ts` simply calls
ALF's `createThemes({defaultPalette, subduedPalette})` and re-exports the
result. The composition is therefore entirely ALF's:

| Theme   | Scheme | Source palette            | Shadow opacity |
| ------- | ------ | ------------------------- | -------------- |
| `light` | light  | `DEFAULT_PALETTE`         | `0.1`          |
| `dark`  | dark   | `invertPalette(DEFAULT_PALETTE)`   | `0.4`  |
| `dim`   | dark   | `invertPalette(DEFAULT_SUBDUED_PALETTE)` | `0.4` |

`Palette.default` and `Palette.subdued` in `Palette.swift` are the two source
palettes, transcribed verbatim. `Palette.inverted()` is a direct port of ALF's
`invertPalette`, so `dark` and `dim` are *derived*, not hand-transcribed. This
matches the source composition exactly and keeps the derivation auditable.

### Inversion is not a simple index reflection

A subtlety worth recording: `contrast_0` maps to `contrast_1000`, but
`contrast_25` maps to `contrast_975` (not `_950`), `contrast_50` to `_950` and
`contrast_100` to `_900`. The `_500` step is unchanged. `Palette.inverted()`
reproduces ALF's mapping faithfully; `ThemeTests.invertIsNotASimpleIndexReflection`
pins it.

### Shadows

ALF builds each shadow from `alpha(palette.black, opacity)` where `alpha`
appends `round(opacity * 255)` as hex. So the web `boxShadow` strings carry
`#0000001a` (light) or `#00000066` (dark/dim), while the native `shadowColor` is
plain `#000000`. Both are recorded in `Shadow`.

## Contents

- `Scales.swift` — spacing (`2xs`..`5xl`), type size (`2xs`..`5xl`), relative
  line heights (`tight`/`snug`/`relaxed`), radius, font weights and tracking.
- `Palette.swift` — the `Palette` type, the two source palettes, and `inverted()`.
- `Theme.swift` — `create(scheme:name:palette:shadowOpacity:)`, the semantic
  `ThemeAtoms`, and the three composed themes (`Theme.light` / `.dark` / `.dim`).
- `Gradients.swift` — the eight gradient presets (`GradientPreset.designTokens`).
- `FontScale.swift` — the user font-scale steps and multipliers.

## Notable token behaviours reproduced faithfully

- **Font scale steps collapse at the extremes.** `fonts.ts` maps `-2` to
  `1 - 0.0625` (same as `-1`) and `2` to `1 + 0.0625` (same as `1`); the source
  marks the extremes "unused". Reproduced as-is.
- **Gradients have no angle in the token data.** The presets record only stop
  positions and colours. Consumers choose the axis: `GradientFill` uses
  `start=(0,0)`/`end=(1,1)` (recorded as `GradientPreset.diagonalStart`/`.End`),
  while `LinearGradientBackground` defaults to `sky` with Expo's default axis.
- **`TRACKING` is `0` from ALF**, but the RN app overrides letter spacing to
  `0.25` *only* for the `system` font family (`FontScale.systemFontLetterSpacing`).

## Verification

`swift build && swift test` on Linux. Tests pin values against the ALF source:
every scale value, every gradient stop, and per-theme assertions for the three
composed themes. During development the full palette (177 values) and atoms
(84 values) were diffed exhaustively against `@bsky.app/alf@0.1.15` and matched
byte-for-byte; the committed tests keep representative anchors for each theme.

## License

Values originate from Bluesky source. `@bsky.app/alf` is MIT licensed; see
<https://github.com/bluesky-social/toolbox>.

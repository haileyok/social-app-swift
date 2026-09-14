# DesignSystem

The SwiftUI wiring layer over [`DesignTokens`](../DesignTokens). This is the
first UI package in the repo and the counterpart of the RN app's ALF React
layer: tokens stay as plain data in `DesignTokens`; this package turns them into
`Color`s, `Font`s, spacing, gradients, shadows, breakpoint helpers and an
environment-injected theme.

- `DesignSystemCore` — no UI framework. Hex parsing, font-weight mapping,
  breakpoint math, shadow geometry, theme resolution. Built and tested on Linux
  (`swift build && swift test`).
- `DesignSystem` — SwiftUI. The theme environment, colors, typography,
  modifiers, `TokenGallery`. Verified on macOS CI only.

This is a **UI package**, so it is exempt from the repo's Linux boundary rule
(no `import SwiftUI`) and uses MainActor-default isolation. It is excluded from
the Linux build/test and boundary-lint loops in `linux.yml` alongside
`UIComponents`.

## Provenance

All token **values** come from `DesignTokens`, which is a byte-for-byte port of
**`@bsky.app/alf@0.1.15`** (MIT) and the RN app's `src/alf` (gradients, font
scaling, theme composition). This package re-derives nothing: it reads
`Theme.light`/`.dark`/`.dim`, `Scales`, `GradientPreset` and `FontScale` and only
adds the platform wiring. See `../DesignTokens/README.md`.

The one value set this package *does* add is the native shadow geometry, which
`DesignTokens` deliberately skipped because it is platform shadow state, not
colour data. It is transcribed from `@bsky.app/alf@0.1.15`
`src/atoms/index.native.ts` (the `shadow_xs`..`shadow_xl` atoms) into
`DesignSystemCore/ShadowGeometry.swift`.

## Inter font

`Sources/DesignSystem/Resources/InterVariable.ttf` (and the italic face) is the
**Inter variable font**, weights 100–900 with a 14–32 optical-size axis.

- Source: `rsms/inter` GitHub release **v4.1**
  (<https://github.com/rsms/inter/releases/tag/v4.1>), files `InterVariable.ttf`
  and `InterVariable-Italic.ttf` from `Inter-4.1.zip`. The same file is
  published by Google Fonts.
- License: **SIL Open Font License 1.1**. The upstream license text is committed
  verbatim as `Inter-LICENSE.txt` next to the font.
- Registered at runtime with `CTFontManagerRegisterFontsForURL` by
  `InterFontRegistry`, which is idempotent and falls back to the system font if
  registration fails, so a missing resource degrades instead of crashing.
- The registered names are `Inter Variable` (family) and `InterVariable`
  (PostScript), which is what `Font.custom` is given.

The RN app uses Inter (`InterVariable`) as the `theme` font family and the
platform UI font for the `system` family, where it also overrides letter
spacing to `0.25`. Both behaviours are reproduced (`FontFamilyPreference`,
`FontScale.systemFontLetterSpacing`).

## API surface

A consumer writes ordinary SwiftUI and reads the theme from the environment:

```swift
import DesignSystem
import DesignTokens
import SwiftUI

struct ProfileCard: View {
  @Environment(\.alfTheme) private var t   // ALF's `useTheme()`

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm.value) {
      Text("Hailey").themedFont(.lg, weight: Scales.FontWeight.semiBold)
      Text("native SwiftUI").themedFont(.sm)
    }
    .padding(.md)                             // ALF spacing step, 12pt
    .background(t.atomColors.bgContrast50)
    .cornerRadius(.md)                        // ALF radius step, 12pt
    .alfShadow(.sm)                           // ALF shadow atom
    .foregroundStyle(t.atomColors.text)
  }
}

// Inject a theme (runtime switchable; `.system` follows the OS appearance):
Content().theme(.dim)
Content().theme(ThemePreference.system)
```

Piece by piece:

| Need | API |
| --- | --- |
| Hex -> color | `Color(hex: "#RRGGBB")`, `Color(hex: "#RRGGBBAA")`, `Color(parsingHex:)` |
| Theme injection | `.theme(.dim)` (name), `.theme(Theme)`, `.theme(ThemePreference)` |
| Theme read-back | `@Environment(\.alfTheme) private var t` -> `t.colors.*`, `t.atomColors.*` |
| Type scale | `.themedFont(.md, weight: Scales.FontWeight.semiBold)`, `TypeScale.md.font(...)`, `AlfText(_:scale:weight:color:)` |
| Spacing | `Spacing.md.value`, `.padding(.md)`, `.padding(.md, .horizontal)` |
| Radius | `Radius.lg.value`, `.cornerRadius(.lg)` |
| Gradients | `GradientFill(.sky) { content }`, `GradientName.sky.linearGradient` |
| Shadows | `.alfShadow(.md)`, `theme.shadow(.md)` -> `ResolvedShadow` |
| Breakpoints | `@Environment(\.breakpoints)`, `.breakpoints(width:)`, `ScreenBreakpoints(width:isRegularWidth:)` |
| Font preferences | `.fontScale(.plus1)`, `.fontPreferences(family:scale:)` |
| Demo | `TokenGallery(themeName: .dim)` (internal, not shipped) |

## Pure/SwiftUI split

The split is by testability, not by taste. Everything that can be pure arithmetic
over token data lives in `DesignSystemCore` (no `import SwiftUI`, built on Linux):

- `HexColor` — `#RRGGBB` / `#RRGGBBAA` parsing.
- `FontWeightScale` — CSS weight string -> `Int` (see below).
- `Breakpoints` — the 500/800/1300 media-query math and the shell thresholds.
- `TextMetrics` — `normalizeTextStyles`'s font-scale and line-height arithmetic.
- `ShadowGeometry` / `ResolvedShadow` — the native shadow props and the
  theme-opacity x atom-opacity combination.
- `ThemeResolver` / `ThemePreference` / `FontFamilyPreference` — preference
  resolution.

The SwiftUI target consumes those and adds only platform glue. `swift test` in
this package covers the core target on Linux; the SwiftUI target is verified by
the `ios-selfhosted` macOS run.

## Font weights: the DesignTokens open question

`DesignTokens.Scales.FontWeight` records ALF's weights as CSS-style strings
(`"400"`, `"500"`, `"600"`, `"700"`), matching what the RN app passes to
`applyFonts`. SwiftUI wants numbers, so the mapping is resolved in
`FontWeightScale.numericWeight(forCSSWeight:)`, which is total over the four
tokens and falls back to 400 (ALF's `Inter-Regular` fallback) for anything else.
The tokens stay strings; the numeric mapping is a `DesignSystemCore` concern.

## Breakpoints: the RN -> SwiftUI mapping

The RN app uses `react-responsive` media queries; SwiftUI has size classes and a
container width, so the mapping combines both.

| RN query | SwiftUI equivalent |
| --- | --- |
| `minWidth: 500` (`gtPhone`) | regular horizontal size class and width >= 500 |
| `minWidth: 800` (`gtMobile`) | regular horizontal size class and width >= 800 |
| `minWidth: 1300` (`gtTablet`) | width >= 1300 (pure width; iPads at that width are regular anyway) |
| `minWidth: 1100` (`rightNavVisible`) | width >= 1100 |
| `minWidth: 1100, maxWidth: 1300` (`centerColumnOffset`) | 1100 <= width <= 1300 |
| `maxWidth: 1300` (`leftNavMinimal`) | width <= 1300 |

Rationale: 500pt+ with a compact width class (an iPhone in landscape) is still a
phone layout, so the two wider steps require `.regular`; the 1300 line is a raw
width line on iPad/Mac-class hardware. The predicate table is unit-tested on
Linux; the size class is read from `@Environment(\.horizontalSizeClass)`.

## Deviations from the RN app

- **Dynamic Type.** `TypeScale.font(respectsDynamicType:)` defaults to `true`,
  so type also scales with the user's Dynamic Type setting relative to a
  `Font.TextStyle`. The RN app only honors its own font-scale preference. Pass
  `false` for exact RN parity.
- **Shadow radius.** RN's `shadowRadius` maps 1:1 to SwiftUI's `shadow.radius`;
  the native offset and the theme x atom opacity multiplication are reproduced
  exactly. `elevation` is Android-only and unused on iOS.
- **Corner curves.** ALF's `curve_continuous` (iOS) is applied by default in
  `.cornerRadius(_:)`.
- **Pills.** `Radius.full` (999) cannot be a fixed SwiftUI radius; use
  `.clipShape(.capsule)` for pill shapes and the radius modifier for finite steps.

## Layout

```
Sources/
  DesignSystemCore/     # 🌐 Linux-verifiable: no UI framework
  DesignSystem/         # SwiftUI
    Resources/          # InterVariable.ttf, InterVariable-Italic.ttf, Inter-LICENSE.txt
    TokenGallery.swift  # internal demo, not shipped
Tests/
  DesignSystemCoreTests/ # Swift Testing, runs on Linux
```

## Verification

- Linux: `cd Packages/DesignSystem && swift build && swift test` (core target).
- macOS: pushing touches `.github/workflows/ios-selfhosted.yml`, which builds
  `App/` (and therefore this package) for the iOS Simulator SDK on a real Mac.
- `swiftlint lint --strict` from the repo root.

## License

Token values originate from Bluesky source; `@bsky.app/alf` is MIT licensed
(<https://github.com/bluesky-social/toolbox>). The bundled Inter font is under
the SIL Open Font License 1.1; its license text ships with the font.

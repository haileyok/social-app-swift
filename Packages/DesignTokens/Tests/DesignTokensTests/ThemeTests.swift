import Testing

@testable import DesignTokens

/**
 Pins the three composed themes against values produced by
 `@bsky.app/alf@0.1.15` (`createThemes` over `DEFAULT_PALETTE` /
 `DEFAULT_SUBDUED_PALETTE`), which is exactly what `src/alf/themes.ts` in the
 RN app re-exports. The `light`/`dim` source palettes are transcribed from
 `palette.ts`; dark and dim ramps are derived via `Palette.inverted()`, which
 is a direct port of `invertPalette`.
 */
@Suite struct ThemeTests {
  @Test func lightComposition() {
    let t = Theme.light
    #expect(t.scheme == .light)
    #expect(t.name == .light)
    #expect(t.shadowOpacity == 0.1)
    // Atoms
    #expect(t.atoms.text == "#000000")
    #expect(t.atoms.textLink == "#006AFF")  // light scheme -> primary_500
    #expect(t.atoms.textContrastLow == "#8798B0")
    #expect(t.atoms.textContrastMedium == "#405168")
    #expect(t.atoms.textContrastHigh == "#232E3E")
    #expect(t.atoms.textInverted == "#FFFFFF")
    #expect(t.atoms.bg == "#FFFFFF")
    #expect(t.atoms.bgContrast100 == "#DCE2EA")
    #expect(t.atoms.borderContrastLow == "#DCE2EA")
    #expect(t.atoms.borderContrastHigh == "#A5B2C5")
    // Palette anchors
    #expect(t.palette.contrast1000 == "#000000")
    #expect(t.palette.primary500 == "#006AFF")
    #expect(t.palette.negative500 == "#E91646")
  }

  @Test func darkComposition() {
    let t = Theme.dark
    #expect(t.scheme == .dark)
    #expect(t.name == .dark)
    #expect(t.shadowOpacity == 0.4)
    // Atoms - resolved from the inverted DEFAULT_PALETTE
    #expect(t.atoms.text == "#FFFFFF")
    #expect(t.atoms.textLink == "#4291FF")  // dark scheme -> primary_600
    #expect(t.atoms.textContrastLow == "#526580")
    #expect(t.atoms.textContrastMedium == "#A5B2C5")
    #expect(t.atoms.textContrastHigh == "#DCE2EA")
    #expect(t.atoms.textInverted == "#000000")
    #expect(t.atoms.bg == "#000000")
    #expect(t.atoms.bgContrast100 == "#232E3E")
    #expect(t.atoms.borderContrastLow == "#232E3E")
    #expect(t.atoms.borderContrastHigh == "#405168")
    // Palette anchors
    #expect(t.palette.contrast0 == "#000000")
    #expect(t.palette.contrast1000 == "#FFFFFF")
    #expect(t.palette.primary600 == "#4291FF")
    #expect(t.palette.positive500 == "#09B35E")
  }

  @Test func dimComposition() {
    let t = Theme.dim
    #expect(t.scheme == .dark)
    #expect(t.name == .dim)
    #expect(t.shadowOpacity == 0.4)
    // Atoms - resolved from the inverted DEFAULT_SUBDUED_PALETTE
    #expect(t.atoms.text == "#FFFFFF")
    #expect(t.atoms.textLink == "#4D97FF")  // dark scheme -> primary_600
    #expect(t.atoms.textContrastLow == "#586C89")
    #expect(t.atoms.textContrastMedium == "#ABB8C9")
    #expect(t.atoms.textContrastHigh == "#E2E7EE")
    #expect(t.atoms.textInverted == "#151D28")
    #expect(t.atoms.bg == "#151D28")
    #expect(t.atoms.bgContrast100 == "#2C3A4E")
    #expect(t.atoms.borderContrastLow == "#2C3A4E")
    #expect(t.atoms.borderContrastHigh == "#485B75")
    // Palette anchors
    #expect(t.palette.contrast0 == "#151D28")
    #expect(t.palette.contrast1000 == "#FFFFFF")
    #expect(t.palette.primary500 == "#0F73FF")
    #expect(t.palette.positive500 == "#0AC266")
    #expect(t.palette.negative500 == "#EB2452")
  }

  @Test func invertIsNotASimpleIndexReflection() {
    // contrast_0 -> contrast_1000, but contrast_25 -> contrast_975 (not _950).
    let inverted = Palette.default.inverted()
    #expect(inverted.contrast0 == Palette.default.contrast1000)
    #expect(inverted.contrast25 == Palette.default.contrast975)
    #expect(inverted.contrast100 == Palette.default.contrast900)
    #expect(inverted.contrast500 == Palette.default.contrast500)  // midpoint unchanged
  }

  @Test func constantColorsSurviveInversion() {
    for theme in [Theme.light, Theme.dark, Theme.dim] {
      #expect(theme.palette.white == "#FFFFFF")
      #expect(theme.palette.black == "#000000")
      #expect(theme.palette.pink == "#EC4899")
      #expect(theme.palette.yellow == "#FFC404")
      #expect(theme.palette.like == theme.palette.pink)
    }
  }

  @Test func shadowOpacityBakesIntoHexColors() {
    // ALF alpha(): round(opacity * 255) as two hex digits.
    #expect(Theme.alphaHex(0.1) == "1a")
    #expect(Theme.alphaHex(0.4) == "66")
    #expect(Theme.light.atoms.shadowXS.boxShadow == "0 2px 8px 0 #0000001a")
    #expect(Theme.dark.atoms.shadowXS.boxShadow == "0 2px 8px 0 #00000066")
    #expect(Theme.dim.atoms.shadowXL.boxShadow == "0 10px 40px 0 #00000066")
    #expect(Theme.light.atoms.shadowLG.boxShadow == "0 20px 25px -5px #0000001a, 0 8px 10px -6px #0000001a")
    // Native shadowColor is always palette black, independent of opacity.
    #expect(Theme.dark.atoms.shadowXS.color == "#000000")
  }

  @Test func allThemesAreRegistered() {
    #expect(Theme.all.count == 3)
    #expect(Theme.all[.light]?.name == .light)
    #expect(Theme.all[.dark]?.name == .dark)
    #expect(Theme.all[.dim]?.name == .dim)
  }
}

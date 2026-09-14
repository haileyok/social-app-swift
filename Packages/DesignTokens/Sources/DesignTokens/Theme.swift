/**
 A shadow atom as ALF defines it: a native `shadowColor` plus the web
 `boxShadow` string. Both are plain values so the type stays platform-free.
 */
public struct Shadow: Equatable, Sendable {
  /** The `shadowColor` prop (always ALF's palette black). */
  public let color: String
  /** The CSS `box-shadow` value, including the alpha-suffixed colour. */
  public let boxShadow: String

  public init(color: String, boxShadow: String) {
    self.color = color
    self.boxShadow = boxShadow
  }
}

/**
 The semantic colour aliases of a theme (`Theme.atoms` in ALF). Every field is
 a hex string resolved against the theme's palette.
 */
public struct ThemeAtoms: Equatable, Sendable {
  public let text: String
  public let textLink: String
  public let textContrastLow: String
  public let textContrastMedium: String
  public let textContrastHigh: String
  public let textInverted: String

  public let bg: String
  public let bgContrast25: String
  public let bgContrast50: String
  public let bgContrast100: String
  public let bgContrast200: String
  public let bgContrast300: String
  public let bgContrast400: String
  public let bgContrast500: String
  public let bgContrast600: String
  public let bgContrast700: String
  public let bgContrast800: String
  public let bgContrast900: String
  public let bgContrast950: String
  public let bgContrast975: String

  public let borderContrastLow: String
  public let borderContrastMedium: String
  public let borderContrastHigh: String

  public let shadowXS: Shadow
  public let shadowSM: Shadow
  public let shadowMD: Shadow
  public let shadowLG: Shadow
  public let shadowXL: Shadow
}

/** Whether a theme is a light or dark scheme, matching ALF's `ThemeScheme`. */
public enum ThemeScheme: String, Equatable, Sendable {
  case light
  case dark
}

/** The three ALF theme names, matching `ThemeName`. */
public enum ThemeName: String, Equatable, Sendable, CaseIterable {
  case light
  case dark
  case dim
}

/**
 A fully composed theme: scheme, name, the resolved palette and the semantic
 atoms. Mirrors ALF's `Theme` type plus the shadow opacity used to build it.
 */
public struct Theme: Equatable, Sendable {
  public let scheme: ThemeScheme
  public let name: ThemeName
  public let palette: Palette
  public let atoms: ThemeAtoms
  /** Alpha applied to black when building web shadow colours. */
  public let shadowOpacity: Double
}

extension Theme {
  /**
   Builds a theme from a palette exactly as ALF's `createTheme` does: alias the
   semantic atoms to palette entries, choose `primary_600` for dark-scheme link
   text, and bake the shadow colour into both the native and web values.
   */
  public static func create(
    scheme: ThemeScheme,
    name: ThemeName,
    palette: Palette,
    shadowOpacity: Double = 0.1
  ) -> Theme {
    let shadowColorHex = palette.black + alphaHex(shadowOpacity)
    let shadowColor = palette.black

    func shadow(_ boxShadow: String) -> Shadow {
      Shadow(color: shadowColor, boxShadow: boxShadow)
    }

    return Theme(
      scheme: scheme,
      name: name,
      palette: palette,
      atoms: ThemeAtoms(
        text: palette.contrast1000,
        textLink: scheme == .dark ? palette.primary600 : palette.primary500,
        textContrastLow: palette.contrast400,
        textContrastMedium: palette.contrast700,
        textContrastHigh: palette.contrast900,
        textInverted: palette.contrast0,
        bg: palette.contrast0,
        bgContrast25: palette.contrast25,
        bgContrast50: palette.contrast50,
        bgContrast100: palette.contrast100,
        bgContrast200: palette.contrast200,
        bgContrast300: palette.contrast300,
        bgContrast400: palette.contrast400,
        bgContrast500: palette.contrast500,
        bgContrast600: palette.contrast600,
        bgContrast700: palette.contrast700,
        bgContrast800: palette.contrast800,
        bgContrast900: palette.contrast900,
        bgContrast950: palette.contrast950,
        bgContrast975: palette.contrast975,
        borderContrastLow: palette.contrast100,
        borderContrastMedium: palette.contrast200,
        borderContrastHigh: palette.contrast300,
        shadowXS: shadow("0 2px 8px 0 \(shadowColorHex)"),
        shadowSM: shadow(
          "0 4px 6px -1px \(shadowColorHex), 0 2px 4px -2px \(shadowColorHex)"),
        shadowMD: shadow(
          "0 10px 15px -3px \(shadowColorHex), 0 4px 6px -4px \(shadowColorHex)"),
        shadowLG: shadow(
          "0 20px 25px -5px \(shadowColorHex), 0 8px 10px -6px \(shadowColorHex)"),
        shadowXL: shadow("0 10px 40px 0 \(shadowColorHex)")
      ),
      shadowOpacity: shadowOpacity
    )
  }

  /**
   Port of ALF's `alpha()` for the six-digit hex colours ALF uses for shadows:
   append `round(opacity * 255)` as two hex digits.
   */
  static func alphaHex(_ opacity: Double) -> String {
    let value = Int((opacity * 255).rounded())
    let hex = String(value, radix: 16)
    return String(repeating: "0", count: max(0, 2 - hex.count)) + hex
  }
}

extension Theme {
  /** ALF `themes.light`: `DEFAULT_PALETTE`, light scheme, default shadow opacity. */
  public static let light = Theme.create(
    scheme: .light, name: .light, palette: .default)

  /** ALF `themes.dark`: inverted `DEFAULT_PALETTE`, shadow opacity `0.4`. */
  public static let dark = Theme.create(
    scheme: .dark, name: .dark, palette: .default.inverted(), shadowOpacity: 0.4)

  /** ALF `themes.dim`: inverted `DEFAULT_SUBDUED_PALETTE`, shadow opacity `0.4`. */
  public static let dim = Theme.create(
    scheme: .dark, name: .dim, palette: .subdued.inverted(), shadowOpacity: 0.4)

  /// All three themes keyed by name, mirroring ALF's `createThemes` return value.
  public static let all: [ThemeName: Theme] = [.light: .light, .dark: .dark, .dim: .dim]
}

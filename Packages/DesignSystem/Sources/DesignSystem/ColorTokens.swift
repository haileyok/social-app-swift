#if canImport(SwiftUI)
import DesignSystemCore
import DesignTokens
import SwiftUI

/**
 Hex -> `Color`, and the ALF palette/atom mirrors the theme exposes.

 DesignTokens keeps every colour as a hex string; this file is the only place
 that knows how to turn one into a `Color`. The parse itself lives in
 `DesignSystemCore.HexColor` so it is testable on Linux.
 */
extension Color {
  /**
   Builds a colour from `#RRGGBB` or `#RRGGBBAA` (the `#` is optional).

   In debug builds a malformed string trips an assertion and renders clear, so a
   bad token is loud in development and harmless in release.
   */
  public init(hex: String) {
    guard let parsed = HexColor(hex: hex) else {
      assertionFailure("Malformed hex colour token: \(hex)")
      self = .clear
      return
    }
    self.init(parsed)
  }

  /// Failable variant, for callers that want to handle a bad token themselves.
  public init?(parsingHex hex: String) {
    guard let parsed = HexColor(hex: hex) else { return nil }
    self.init(parsed)
  }

  /** Builds a colour from already-parsed components. */
  public init(_ hexColor: HexColor) {
    self.init(
      .sRGB,
      red: hexColor.red,
      green: hexColor.green,
      blue: hexColor.blue,
      opacity: hexColor.alpha)
  }
}

/**
 The theme palette with `Color` values, the SwiftUI counterpart of ALF's
 `t.palette`.

 The colours are held in a name-keyed dictionary shaped exactly like
 `Palette.allValues` (ALF field names such as `contrast_500`, `primary_500`), and
 each field is a typed accessor over it. That keeps the mapping mechanical and
 the type total: a field can never drift from its token.
 */
public struct PaletteColors: Sendable {
  /** Every palette colour by its ALF field name. */
  public let values: [String: Color]

  init(_ palette: Palette) {
    values = palette.allValues.mapValues { Color(hex: $0) }
  }

  public var white: Color { self["white"] }
  public var black: Color { self["black"] }
  public var pink: Color { self["pink"] }
  public var yellow: Color { self["yellow"] }
  public var like: Color { self["like"] }

  public var contrast0: Color { self["contrast_0"] }
  public var contrast25: Color { self["contrast_25"] }
  public var contrast50: Color { self["contrast_50"] }
  public var contrast100: Color { self["contrast_100"] }
  public var contrast200: Color { self["contrast_200"] }
  public var contrast300: Color { self["contrast_300"] }
  public var contrast400: Color { self["contrast_400"] }
  public var contrast500: Color { self["contrast_500"] }
  public var contrast600: Color { self["contrast_600"] }
  public var contrast700: Color { self["contrast_700"] }
  public var contrast800: Color { self["contrast_800"] }
  public var contrast900: Color { self["contrast_900"] }
  public var contrast950: Color { self["contrast_950"] }
  public var contrast975: Color { self["contrast_975"] }
  public var contrast1000: Color { self["contrast_1000"] }

  public var primary25: Color { self["primary_25"] }
  public var primary50: Color { self["primary_50"] }
  public var primary100: Color { self["primary_100"] }
  public var primary200: Color { self["primary_200"] }
  public var primary300: Color { self["primary_300"] }
  public var primary400: Color { self["primary_400"] }
  public var primary500: Color { self["primary_500"] }
  public var primary600: Color { self["primary_600"] }
  public var primary700: Color { self["primary_700"] }
  public var primary800: Color { self["primary_800"] }
  public var primary900: Color { self["primary_900"] }
  public var primary950: Color { self["primary_950"] }
  public var primary975: Color { self["primary_975"] }

  public var positive25: Color { self["positive_25"] }
  public var positive50: Color { self["positive_50"] }
  public var positive100: Color { self["positive_100"] }
  public var positive200: Color { self["positive_200"] }
  public var positive300: Color { self["positive_300"] }
  public var positive400: Color { self["positive_400"] }
  public var positive500: Color { self["positive_500"] }
  public var positive600: Color { self["positive_600"] }
  public var positive700: Color { self["positive_700"] }
  public var positive800: Color { self["positive_800"] }
  public var positive900: Color { self["positive_900"] }
  public var positive950: Color { self["positive_950"] }
  public var positive975: Color { self["positive_975"] }

  public var negative25: Color { self["negative_25"] }
  public var negative50: Color { self["negative_50"] }
  public var negative100: Color { self["negative_100"] }
  public var negative200: Color { self["negative_200"] }
  public var negative300: Color { self["negative_300"] }
  public var negative400: Color { self["negative_400"] }
  public var negative500: Color { self["negative_500"] }
  public var negative600: Color { self["negative_600"] }
  public var negative700: Color { self["negative_700"] }
  public var negative800: Color { self["negative_800"] }
  public var negative900: Color { self["negative_900"] }
  public var negative950: Color { self["negative_950"] }
  public var negative975: Color { self["negative_975"] }

  /**
   A palette colour by ALF field name. Clear when the name is unknown, which
   lets a missing token render harmlessly instead of crashing.
   */
  public subscript(name: String) -> Color {
    values[name] ?? .clear
  }
}

/**
 The theme's semantic atoms with `Color` values, the SwiftUI counterpart of
 ALF's `t.atoms` (`t.atoms.text`, `t.atoms.bg`, `t.atoms.border_contrast_low`).
 */
public struct AtomColors: Sendable {
  public let text: Color
  public let textLink: Color
  public let textContrastLow: Color
  public let textContrastMedium: Color
  public let textContrastHigh: Color
  public let textInverted: Color

  public let bg: Color
  public let bgContrast25: Color
  public let bgContrast50: Color
  public let bgContrast100: Color
  public let bgContrast200: Color
  public let bgContrast300: Color
  public let bgContrast400: Color
  public let bgContrast500: Color
  public let bgContrast600: Color
  public let bgContrast700: Color
  public let bgContrast800: Color
  public let bgContrast900: Color
  public let bgContrast950: Color
  public let bgContrast975: Color

  public let borderContrastLow: Color
  public let borderContrastMedium: Color
  public let borderContrastHigh: Color

  init(_ atoms: ThemeAtoms) {
    text = Color(hex: atoms.text)
    textLink = Color(hex: atoms.textLink)
    textContrastLow = Color(hex: atoms.textContrastLow)
    textContrastMedium = Color(hex: atoms.textContrastMedium)
    textContrastHigh = Color(hex: atoms.textContrastHigh)
    textInverted = Color(hex: atoms.textInverted)

    bg = Color(hex: atoms.bg)
    bgContrast25 = Color(hex: atoms.bgContrast25)
    bgContrast50 = Color(hex: atoms.bgContrast50)
    bgContrast100 = Color(hex: atoms.bgContrast100)
    bgContrast200 = Color(hex: atoms.bgContrast200)
    bgContrast300 = Color(hex: atoms.bgContrast300)
    bgContrast400 = Color(hex: atoms.bgContrast400)
    bgContrast500 = Color(hex: atoms.bgContrast500)
    bgContrast600 = Color(hex: atoms.bgContrast600)
    bgContrast700 = Color(hex: atoms.bgContrast700)
    bgContrast800 = Color(hex: atoms.bgContrast800)
    bgContrast900 = Color(hex: atoms.bgContrast900)
    bgContrast950 = Color(hex: atoms.bgContrast950)
    bgContrast975 = Color(hex: atoms.bgContrast975)

    borderContrastLow = Color(hex: atoms.borderContrastLow)
    borderContrastMedium = Color(hex: atoms.borderContrastMedium)
    borderContrastHigh = Color(hex: atoms.borderContrastHigh)
  }
}

extension Theme {
  /** ALF `t.palette`, as SwiftUI colours. */
  public var colors: PaletteColors { PaletteColors(palette) }

  /** ALF `t.atoms`, as SwiftUI colours. */
  public var atomColors: AtomColors { AtomColors(atoms) }
}
#endif

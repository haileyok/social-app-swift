/**
 A full ALF colour palette. Every field is a CSS hex colour string; the
 palette carries no platform colour type so it builds on Linux.

 Non-ramp fields (`white`, `black`, `pink`, `yellow`, `like`) are constant
 across every palette. The `*_25`..`*_975` families are thirteen-step ramps
 that dark themes derive by inverting the light ramp (see `Palette.inverted()`).
 */
public struct Palette: Equatable, Sendable {
  public let white: String
  public let black: String
  public let pink: String
  public let yellow: String

  /// Deprecated alias for `pink`, retained for parity with ALF.
  public let like: String

  public let contrast0: String
  public let contrast25: String
  public let contrast50: String
  public let contrast100: String
  public let contrast200: String
  public let contrast300: String
  public let contrast400: String
  public let contrast500: String
  public let contrast600: String
  public let contrast700: String
  public let contrast800: String
  public let contrast900: String
  public let contrast950: String
  public let contrast975: String
  public let contrast1000: String

  public let primary25: String
  public let primary50: String
  public let primary100: String
  public let primary200: String
  public let primary300: String
  public let primary400: String
  public let primary500: String
  public let primary600: String
  public let primary700: String
  public let primary800: String
  public let primary900: String
  public let primary950: String
  public let primary975: String

  public let positive25: String
  public let positive50: String
  public let positive100: String
  public let positive200: String
  public let positive300: String
  public let positive400: String
  public let positive500: String
  public let positive600: String
  public let positive700: String
  public let positive800: String
  public let positive900: String
  public let positive950: String
  public let positive975: String

  public let negative25: String
  public let negative50: String
  public let negative100: String
  public let negative200: String
  public let negative300: String
  public let negative400: String
  public let negative500: String
  public let negative600: String
  public let negative700: String
  public let negative800: String
  public let negative900: String
  public let negative950: String
  public let negative975: String

  /// Every colour in the palette keyed by its ALF field name, for iteration and tests.
  public var allValues: [String: String] {
    [
      "white": white, "black": black, "pink": pink, "yellow": yellow, "like": like,
      "contrast_0": contrast0,
      "contrast_25": contrast25, "contrast_50": contrast50, "contrast_100": contrast100,
      "contrast_200": contrast200, "contrast_300": contrast300, "contrast_400": contrast400,
      "contrast_500": contrast500, "contrast_600": contrast600, "contrast_700": contrast700,
      "contrast_800": contrast800, "contrast_900": contrast900, "contrast_950": contrast950,
      "contrast_975": contrast975, "contrast_1000": contrast1000,
      "primary_25": primary25, "primary_50": primary50, "primary_100": primary100,
      "primary_200": primary200, "primary_300": primary300, "primary_400": primary400,
      "primary_500": primary500, "primary_600": primary600, "primary_700": primary700,
      "primary_800": primary800, "primary_900": primary900, "primary_950": primary950,
      "primary_975": primary975,
      "positive_25": positive25, "positive_50": positive50, "positive_100": positive100,
      "positive_200": positive200, "positive_300": positive300, "positive_400": positive400,
      "positive_500": positive500, "positive_600": positive600, "positive_700": positive700,
      "positive_800": positive800, "positive_900": positive900, "positive_950": positive950,
      "positive_975": positive975,
      "negative_25": negative25, "negative_50": negative50, "negative_100": negative100,
      "negative_200": negative200, "negative_300": negative300, "negative_400": negative400,
      "negative_500": negative500, "negative_600": negative600, "negative_700": negative700,
      "negative_800": negative800, "negative_900": negative900, "negative_950": negative950,
      "negative_975": negative975,
    ]
  }
}

extension Palette {
  /**
   Builds the dark-theme palette by mirroring the contrast, primary, positive
   and negative ramps of `self`. A direct port of ALF's `invertPalette`: note
   the ramps are not a fixed `n -> 1000 - n` reflection. `contrast_0` maps to
   `contrast_1000` but `contrast_25` maps to `contrast_975`, `contrast_50` to
   `contrast_950`, and `contrast_100` to `contrast_900`; the middle
   (`_500`) is unchanged.
   */
  public func inverted() -> Palette {
    Palette(
      white: white, black: black, pink: pink, yellow: yellow, like: like,
      contrast0: contrast1000,
      contrast25: contrast975, contrast50: contrast950, contrast100: contrast900,
      contrast200: contrast800, contrast300: contrast700, contrast400: contrast600,
      contrast500: contrast500, contrast600: contrast400, contrast700: contrast300,
      contrast800: contrast200, contrast900: contrast100, contrast950: contrast50,
      contrast975: contrast25, contrast1000: contrast0,
      primary25: primary975, primary50: primary950, primary100: primary900,
      primary200: primary800, primary300: primary700, primary400: primary600,
      primary500: primary500, primary600: primary400, primary700: primary300,
      primary800: primary200, primary900: primary100, primary950: primary50,
      primary975: primary25,
      positive25: positive975, positive50: positive950, positive100: positive900,
      positive200: positive800, positive300: positive700, positive400: positive600,
      positive500: positive500, positive600: positive400, positive700: positive300,
      positive800: positive200, positive900: positive100, positive950: positive50,
      positive975: positive25,
      negative25: negative975, negative50: negative950, negative100: negative900,
      negative200: negative800, negative300: negative700, negative400: negative600,
      negative500: negative500, negative600: negative400, negative700: negative300,
      negative800: negative200, negative900: negative100, negative950: negative50,
      negative975: negative25
    )
  }
}

extension Palette {
  /// ALF `DEFAULT_PALETTE` (`@bsky.app/alf/src/palette.ts`), the light source palette.
  public static let `default` = Palette(
    white: "#FFFFFF", black: "#000000", pink: "#EC4899", yellow: "#FFC404", like: "#EC4899",
    contrast0: "#FFFFFF",
    contrast25: "#F9FAFB", contrast50: "#EFF2F6", contrast100: "#DCE2EA",
    contrast200: "#C0CAD8", contrast300: "#A5B2C5", contrast400: "#8798B0",
    contrast500: "#667B99", contrast600: "#526580", contrast700: "#405168",
    contrast800: "#313F54", contrast900: "#232E3E", contrast950: "#19222E",
    contrast975: "#111822", contrast1000: "#000000",
    primary25: "#F5F9FF", primary50: "#E5F0FF", primary100: "#CCE1FF",
    primary200: "#A8CCFF", primary300: "#75AFFF", primary400: "#4291FF",
    primary500: "#006AFF", primary600: "#0059D6", primary700: "#0048AD",
    primary800: "#00398A", primary900: "#002861", primary950: "#001E47",
    primary975: "#001533",
    positive25: "#ECFEF5", positive50: "#D3FDE8", positive100: "#A3FACF",
    positive200: "#6AF6B0", positive300: "#2CF28F", positive400: "#0DD370",
    positive500: "#09B35E", positive600: "#04904A", positive700: "#036D38",
    positive800: "#04522B", positive900: "#033F21", positive950: "#032A17",
    positive975: "#021D0F",
    negative25: "#FFF5F7", negative50: "#FEE7EC", negative100: "#FDD3DD",
    negative200: "#FBBBCA", negative300: "#F891A9", negative400: "#F65A7F",
    negative500: "#E91646", negative600: "#CA123D", negative700: "#A71134",
    negative800: "#7F0B26", negative900: "#5F071C", negative950: "#430413",
    negative975: "#30030D"
  )

  /// ALF `DEFAULT_SUBDUED_PALETTE`, the source palette for the `dim` theme.
  public static let subdued = Palette(
    white: "#FFFFFF", black: "#000000", pink: "#EC4899", yellow: "#FFC404", like: "#EC4899",
    contrast0: "#FFFFFF",
    contrast25: "#F9FAFB", contrast50: "#F2F4F8", contrast100: "#E2E7EE",
    contrast200: "#C3CDDA", contrast300: "#ABB8C9", contrast400: "#8D9DB4",
    contrast500: "#6F839F", contrast600: "#586C89", contrast700: "#485B75",
    contrast800: "#394960", contrast900: "#2C3A4E", contrast950: "#222E3F",
    contrast975: "#1C2736", contrast1000: "#151D28",
    primary25: "#F5F9FF", primary50: "#EBF3FF", primary100: "#D6E7FF",
    primary200: "#ADCFFF", primary300: "#80B5FF", primary400: "#4D97FF",
    primary500: "#0F73FF", primary600: "#0661E0", primary700: "#0A52B8",
    primary800: "#0E4490", primary900: "#123464", primary950: "#122949",
    primary975: "#122136",
    positive25: "#ECFEF5", positive50: "#D8FDEB", positive100: "#A8FAD1",
    positive200: "#6FF6B3", positive300: "#31F291", positive400: "#0EDD75",
    positive500: "#0AC266", positive600: "#049F52", positive700: "#038142",
    positive800: "#056636", positive900: "#04522B", positive950: "#053D21",
    positive975: "#052917",
    negative25: "#FFF5F7", negative50: "#FEEBEF", negative100: "#FDD8E1",
    negative200: "#FCC0CE", negative300: "#F99AB0", negative400: "#F76486",
    negative500: "#EB2452", negative600: "#D81341", negative700: "#BA1239",
    negative800: "#910D2C", negative900: "#6F0B22", negative950: "#500B1C",
    negative975: "#3E0915"
  )
}

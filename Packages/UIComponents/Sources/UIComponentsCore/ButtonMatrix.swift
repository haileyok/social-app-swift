/// The button matrix from the RN app's `src/components/Button.tsx`, expressed as
/// data so it can be resolved (and tested) without SwiftUI.
///
/// The RN component decides two things from `color`/`size`/`shape`:
///
/// - which palette/atom tokens paint the background, border and label, per
///   state (enabled, hovered, disabled);
/// - the padding, gap, fixed size and corner radius of the container.
///
/// Both are pure functions of the three variant props, so they live here; the
/// SwiftUI layer only maps a ``ColorToken`` onto a `Color` and the metrics onto
/// a `ButtonStyle`.
public enum ButtonColor: String, Sendable, CaseIterable {
  case primary
  case secondary
  case secondaryInverted = "secondary_inverted"
  case negative
  case primarySubtle = "primary_subtle"
  case negativeSubtle = "negative_subtle"
}

/// `tiny`/`small`/`medium`/`large`, matching the RN `ButtonSize` union. The v1
/// brief asked for tiny/small/large; `medium` is kept so the matrix is total.
public enum ButtonSize: String, Sendable, CaseIterable {
  case tiny
  case small
  case medium
  case large
}

/// `default` is the pill used by most buttons; `round`/`square` are the
/// icon-only shapes; `rectangular` is the form-adjacent shape.
public enum ButtonShape: String, Sendable, CaseIterable {
  case `default`
  case round
  case square
  case rectangular
}

/// A colour token, named rather than resolved.
///
/// Names match ALF's token vocabulary: `.palette("primary_500")` reads
/// `Theme.palette.primary_500`, and `.atom("bgContrast50")` reads the
/// `ThemeAtoms` field of the same name. Keeping the name here means the matrix
/// is testable on Linux and the SwiftUI layer stays a thin lookup.
public enum ColorToken: Hashable, Sendable {
  case palette(String)
  case atom(String)
}

/// The tokens that paint one button in one state.
public struct ButtonColorScheme: Equatable, Sendable {
  /// Enabled background. `nil` means "no background" (transparent).
  public let background: ColorToken?
  /// Background while hovered/pressed. `nil` falls back to ``background``.
  public let hoverBackground: ColorToken?
  /// Disabled background. `nil` falls back to ``background``.
  public let disabledBackground: ColorToken?
  /// Enabled label colour.
  public let foreground: ColorToken
  /// Disabled label colour.
  public let disabledForeground: ColorToken
  /// Border colour, when the variant is outlined. v1 buttons are solid only.
  public let border: ColorToken?

  public init(
    background: ColorToken?,
    hoverBackground: ColorToken?,
    disabledBackground: ColorToken?,
    foreground: ColorToken,
    disabledForeground: ColorToken,
    border: ColorToken? = nil
  ) {
    self.background = background
    self.hoverBackground = hoverBackground
    self.disabledBackground = disabledBackground
    self.foreground = foreground
    self.disabledForeground = disabledForeground
    self.border = border
  }
}

/// The container metrics for one button.
public struct ButtonMetrics: Equatable, Sendable {
  public let paddingVertical: Double
  public let paddingHorizontal: Double
  /// Minimum space between the label and any icon.
  public let gap: Double
  /// Fixed square/circle side, for the `round`/`square` shapes.
  public let side: Double?
  /// Corner radius. `nil` means "capsule" (the pill shapes).
  public let cornerRadius: Double?
  /// The ALF type step the label uses.
  public let textScale: TextScaleName
  /// The ALF weight token the label uses.
  public let fontWeight: FontWeightToken

  public init(
    paddingVertical: Double,
    paddingHorizontal: Double,
    gap: Double,
    side: Double? = nil,
    cornerRadius: Double? = nil,
    textScale: TextScaleName,
    fontWeight: FontWeightToken
  ) {
    self.paddingVertical = paddingVertical
    self.paddingHorizontal = paddingHorizontal
    self.gap = gap
    self.side = side
    self.cornerRadius = cornerRadius
    self.textScale = textScale
    self.fontWeight = fontWeight
  }

  /// True when the shape is a pill and the container should clip to a capsule.
  public var isCapsule: Bool { cornerRadius == nil }
}

/// The ALF type steps a button label can use, mirroring `TypeScale`.
public enum TextScaleName: String, Sendable, CaseIterable {
  case xxs
  case xs
  case sm
  case md
  case lg
  case xl
  case xxl
  case xxxl
  case xxxxl
  case xxxxxl
}

/// The ALF weight tokens, by name.
public enum FontWeightToken: String, Sendable, CaseIterable {
  case normal = "400"
  case medium = "500"
  case semiBold = "600"
  case bold = "700"
}

/// The whole resolved button: tokens plus metrics.
public struct ResolvedButton: Equatable, Sendable {
  public let color: ButtonColor
  public let size: ButtonSize
  public let shape: ButtonShape
  public let scheme: ButtonColorScheme
  public let metrics: ButtonMetrics

  public init(
    color: ButtonColor,
    size: ButtonSize,
    shape: ButtonShape,
    scheme: ButtonColorScheme,
    metrics: ButtonMetrics
  ) {
    self.color = color
    self.size = size
    self.shape = shape
    self.scheme = scheme
    self.metrics = metrics
  }

  /// The background for a state, applying the RN fallbacks.
  public func background(disabled: Bool, interacting: Bool) -> ColorToken? {
    if disabled { return scheme.disabledBackground ?? scheme.background }
    if interacting { return scheme.hoverBackground ?? scheme.background }
    return scheme.background
  }

  /// The label colour for a state.
  public func foreground(disabled: Bool) -> ColorToken {
    disabled ? scheme.disabledForeground : scheme.foreground
  }
}

extension ButtonColor {
  /// The token scheme, ported from the `variant === 'solid'` branch of RN's
  /// `useButtonStyles` (the non-deprecated path, which `color` selects).
  public var scheme: ButtonColorScheme {
    switch self {
    case .primary:
      ButtonColorScheme(
        background: .palette("primary_500"),
        hoverBackground: .palette("primary_600"),
        disabledBackground: .palette("primary_200"),
        // The RN enabled label is `palette.white`; the disabled label is
        // `white` in light and `atoms.text_inverted` in dim/dark, which the
        // theme atom resolves correctly across all three themes.
        foreground: .palette("white"),
        disabledForeground: .atom("textInverted"))
    case .secondary:
      ButtonColorScheme(
        background: .atom("bgContrast50"),
        hoverBackground: .atom("bgContrast100"),
        disabledBackground: .atom("bgContrast50"),
        foreground: .atom("textContrastMedium"),
        disabledForeground: .palette("contrast_300"))
    case .secondaryInverted:
      ButtonColorScheme(
        background: .palette("contrast_900"),
        hoverBackground: .palette("contrast_975"),
        disabledBackground: .palette("contrast_600"),
        foreground: .atom("textInverted"),
        disabledForeground: .palette("contrast_300"))
    case .negative:
      ButtonColorScheme(
        background: .palette("negative_500"),
        hoverBackground: .palette("negative_600"),
        disabledBackground: .palette("negative_700"),
        foreground: .palette("white"),
        disabledForeground: .palette("negative_300"))
    case .primarySubtle:
      ButtonColorScheme(
        background: .palette("primary_50"),
        hoverBackground: .palette("primary_100"),
        disabledBackground: .palette("primary_50"),
        foreground: .palette("primary_600"),
        disabledForeground: .palette("primary_200"))
    case .negativeSubtle:
      ButtonColorScheme(
        background: .palette("negative_50"),
        hoverBackground: .palette("negative_100"),
        disabledBackground: .palette("negative_50"),
        foreground: .palette("negative_600"),
        disabledForeground: .palette("negative_200"))
    }
  }
}

extension ButtonSize {
  /// Label type scale and weight, from RN's `useSharedButtonTextStyles`.
  public var labelStyle: (scale: TextScaleName, weight: FontWeightToken) {
    switch self {
    case .large: (.md, .medium)
    case .medium, .small: (.sm, .medium)
    case .tiny: (.xs, .semiBold)
    }
  }
}

extension ResolvedButton {
  /// Builds the resolved button for a variant triple. Defaults match the RN
  /// component: primary/small/default.
  public static func resolve(
    color: ButtonColor = .primary,
    size: ButtonSize = .small,
    shape: ButtonShape = .`default`
  ) -> ResolvedButton {
    let label = size.labelStyle
    let metrics: ButtonMetrics
    switch shape {
    case .`default`:
      metrics = pillMetrics(size: size, label: label)
    case .rectangular:
      metrics = rectangularMetrics(size: size, label: label)
    case .round, .square:
      metrics = squareMetrics(size: size, shape: shape, label: label)
    }
    return ResolvedButton(
      color: color, size: size, shape: shape, scheme: color.scheme, metrics: metrics)
  }

  private static func pillMetrics(
    size: ButtonSize, label: (scale: TextScaleName, weight: FontWeightToken)
  ) -> ButtonMetrics {
    let values: (Double, Double, Double) =
      switch size {
      case .large: (12, 24, 6)
      case .medium: (9, 28, 5)
      case .small: (8, 14, 5)
      case .tiny: (5, 10, 3)
      }
    return ButtonMetrics(
      paddingVertical: values.0,
      paddingHorizontal: values.1,
      gap: values.2,
      textScale: label.scale,
      fontWeight: label.weight)
  }

  private static func rectangularMetrics(
    size: ButtonSize, label: (scale: TextScaleName, weight: FontWeightToken)
  ) -> ButtonMetrics {
    let values: (Double, Double, Double, Double) =
      switch size {
      case .large: (12, 25, 10, 3)
      case .medium: (9, 16, 8, 3)
      case .small: (8, 13, 8, 3)
      case .tiny: (5, 9, 6, 2)
      }
    return ButtonMetrics(
      paddingVertical: values.0,
      paddingHorizontal: values.1,
      gap: values.3,
      cornerRadius: values.2,
      textScale: label.scale,
      fontWeight: label.weight)
  }

  private static func squareMetrics(
    size: ButtonSize, shape: ButtonShape, label: (scale: TextScaleName, weight: FontWeightToken)
  ) -> ButtonMetrics {
    let side: Double =
      switch size {
      case .large: 44
      case .medium, .small: 33
      case .tiny: 25
      }
    // `round` is a circle; `square` is a small-radius rect whose tiny step uses
    // the 6pt radius.
    let corner: Double? =
      switch shape {
      case .round: nil
      case .square: size == .tiny ? 6 : 8
      case .`default`, .rectangular: nil
      }
    return ButtonMetrics(
      paddingVertical: 0,
      paddingHorizontal: 0,
      gap: 0,
      side: side,
      cornerRadius: corner,
      textScale: label.scale,
      fontWeight: label.weight)
  }
}

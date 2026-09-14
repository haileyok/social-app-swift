import DesignTokens

/**
 The resolved geometry of one type-scale step: a size in points, an absolute
 line height in points, and letter tracking in points.

 The RN app composes this at render time in `normalizeTextStyles`: the base size
 is multiplied by the user font-scale multiplier, and any relative line height
 (`<= 2`) is turned into an absolute value by rounding `fontSize * lineHeight`.
 Both rules are pure arithmetic, so they live here and are tested on Linux.
 */
public struct TextMetrics: Equatable, Sendable {
  /** Font size in points, already scaled by the user font-scale multiplier. */
  public let size: Double
  /**
   Absolute line height in points, rounded the way `normalizeTextStyles` rounds.
   `nil` means "the platform default" (native RN leaves it unset).
   */
  public let lineHeight: Double?
  /** Letter tracking in points. */
  public let tracking: Double
  /** The numeric font weight, for consumers that build a `Font`. */
  public let weight: Int

  public init(size: Double, lineHeight: Double?, tracking: Double, weight: Int) {
    self.size = size
    self.lineHeight = lineHeight
    self.tracking = tracking
    self.weight = weight
  }
}

extension TextMetrics {
  /**
   Resolves one step of the type scale.

   - `relativeLineHeight` is the ALF token (`Scales.LineHeight.tight` etc.); a
     token `<= 2` is treated as a multiplier, anything larger as absolute, which
     is exactly `normalizeTextStyles`'s branch.
   - `fontScale` is `FontScale.multiplier(for:)`; pass `1` for the default.
   - `tracking` is `Scales.tracking` (zero) for the theme font, and
     `FontScale.systemFontLetterSpacing` for the `system` font family, matching
     `applyFonts`.
   */
  public static func resolve(
    size: Double,
    relativeLineHeight: Double,
    fontScale: Double = 1,
    weight: String = Scales.FontWeight.normal,
    tracking: Double = Scales.tracking
  ) -> TextMetrics {
    let scaledSize = size * fontScale
    let lineHeight: Double?
    if relativeLineHeight > 0 && relativeLineHeight <= 2 {
      lineHeight = (scaledSize * relativeLineHeight).rounded()
    } else if relativeLineHeight > 0 {
      lineHeight = relativeLineHeight
    } else {
      lineHeight = nil
    }
    return TextMetrics(
      size: scaledSize,
      lineHeight: lineHeight,
      tracking: tracking,
      weight: FontWeightScale.numericWeight(forCSSWeight: weight) ?? FontWeightScale.fallback)
  }
}

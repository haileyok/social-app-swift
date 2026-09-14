import DesignTokens

/**
 Maps ALF's CSS-style font-weight strings to numeric weights.

 `DesignTokens.Scales.FontWeight` records the four weights ALF uses as strings
 (`"400"`, `"500"`, `"600"`, `"700"`), because that is what the RN app passes to
 `applyFonts`. SwiftUI and UIKit want numbers (or `Font.Weight`), so the mapping
 is resolved here, in the Linux-testable target, and is the answer to the open
 question the DesignTokens port left: the tokens stay strings, the mapping is
 numeric and total over the four tokens.
 */
public enum FontWeightScale {
  public static let normal = 400
  public static let medium = 500
  public static let semiBold = 600
  public static let bold = 700

  /**
   The weight used when a token cannot be mapped. ALF's `applyFonts` falls back
   to `Inter-Regular` for an unrecognised weight, i.e. 400.
   */
  public static let fallback = normal

  /// The four mapped tokens, in ascending weight, for iteration and tests.
  public static let all: [(token: String, weight: Int)] = [
    (Scales.FontWeight.normal, normal),
    (Scales.FontWeight.medium, medium),
    (Scales.FontWeight.semiBold, semiBold),
    (Scales.FontWeight.bold, bold),
  ]

  /**
   The numeric weight for a CSS-style weight string, or `nil` when the string is
   not one of the four ALF tokens.
   */
  public static func numericWeight(forCSSWeight weight: String) -> Int? {
    all.first { $0.token == weight }?.weight
  }
}

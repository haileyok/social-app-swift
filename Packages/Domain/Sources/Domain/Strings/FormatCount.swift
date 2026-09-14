import Foundation

/// Port of `src/view/com/util/numeric/format.ts`:
/// `i18n.number(num, {notation: 'compact', maximumFractionDigits: 1, roundingMode: 'trunc'})`.
///
/// Intl's English compact notation has four suffixes (`K`, `M`, `B`, `T`). Only
/// the `T` tier can carry a mantissa large enough to need digit grouping, and
/// Intl group-separates that mantissa only once it reaches five integer digits
/// (`9999T` but `10,000T`). Fractional digits are truncated toward zero and a
/// trailing `.0` is dropped.
///
/// Deviation: Foundation on Linux exposes no compact-notation formatter, so the
/// English suffix table and mantissa formatting are implemented directly. A
/// caller needing another locale's compact suffixes (which Intl supplies from
/// CLDR) must provide them.
public enum FormatCount {

  /// Compact suffixes, largest first. Magnitudes at or above `1e15` reuse `T`.
  static let suffixes: [(threshold: Double, suffix: String)] = [
    (1e12, "T"),
    (1e9, "B"),
    (1e6, "M"),
    (1e3, "K"),
  ]

  /// Formats `num` the way the RN app's `formatCount` does.
  public static func formatCount(_ num: Double, locale: Locale = Locale(identifier: "en_US")) -> String {
    if num.isNaN { return "NaN" }
    if num.isInfinite { return num < 0 ? "-∞" : "∞" }

    let isNegative = num < 0
    let magnitude = abs(num)

    let mantissa: Double
    let suffix: String
    if let match = suffixes.first(where: { magnitude >= $0.threshold }) {
      mantissa = magnitude / match.threshold
      suffix = match.suffix
    } else {
      mantissa = magnitude
      suffix = ""
    }

    // Truncate toward zero to at most one fractional digit, then drop a
    // trailing zero so `1.0` renders as `1`.
    let truncated = (mantissa * 10).rounded(.down) / 10
    let body = formatMantissa(truncated, locale: locale)
    return (isNegative ? "-" : "") + body + suffix
  }

  /// Integer convenience.
  public static func formatCount(_ num: Int, locale: Locale = Locale(identifier: "en_US")) -> String {
    formatCount(Double(num), locale: locale)
  }

  static func formatMantissa(_ value: Double, locale: Locale) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    // Intl starts group-separating the compact mantissa at five integer digits.
    formatter.usesGroupingSeparator = value >= 10000
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 1
    formatter.roundingMode = .down
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
  }
}

import Foundation

/// Compact engagement counts, ported from `Domain.FormatCount` (a port of the RN
/// app's `formatCount`).
///
/// The `Domain` package is not usable from an iOS target today: it declares no
/// iOS platform, and it transitively pulls in `Lexicons` (iOS 18) and
/// `SwiftAtproto` (iOS 17), so linking it fails with "requires minimum platform
/// version". The component library needs exactly two functions from it, so they
/// are reproduced here, unchanged, rather than forcing the platform requirement
/// on every consumer. Delete this file and import `Domain` once that package
/// gains an iOS platform declaration.
public enum MetricFormat {
  /// Compact suffixes, largest first. Magnitudes at or above `1e15` reuse `T`.
  static let suffixes: [(threshold: Double, suffix: String)] = [
    (1e12, "T"),
    (1e9, "B"),
    (1e6, "M"),
    (1e3, "K"),
  ]

  /// Formats `num` the way the RN app's `formatCount` does.
  public static func formatCount(
    _ num: Double, locale: Locale = Locale(identifier: "en_US")
  ) -> String {
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
  public static func formatCount(
    _ num: Int, locale: Locale = Locale(identifier: "en_US")
  ) -> String {
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

/// The unit of a relative-time difference.
public enum RelativeTimeUnit: String, Hashable, Sendable {
  case now
  case second
  case minute
  case hour
  case day
  case month
}

/// How a relative-time difference was classified, with the dates it came from.
public struct RelativeTime: Hashable, Sendable {
  public let value: Int
  public let unit: RelativeTimeUnit
  public let earlier: Date
  public let later: Date

  public init(value: Int, unit: RelativeTimeUnit, earlier: Date, later: Date) {
    self.value = value
    self.unit = unit
    self.earlier = earlier
    self.later = later
  }
}

/// Relative timestamps for the post header, ported from `Domain.DomainTime`
/// (itself a port of the RN app's `useTimeAgo`).
///
/// Same provenance caveat as ``MetricFormat``: reproduced here because the
/// `Domain` package cannot be linked into the iOS target.
public enum MetricTime {
  /// Seconds below which a difference reads as "now".
  public static let diffNow = 5
  static let secondsPerMinute = 60
  static let secondsPerHour = secondsPerMinute * 60
  static let secondsPerDay = secondsPerHour * 24
  static let secondsPerMonth30 = secondsPerDay * 30

  /// Whole-second difference, matching date-fns `differenceInSeconds`
  /// (truncation toward zero).
  static func differenceInSeconds(_ later: Date, _ earlier: Date) -> Int {
    let diff = later.timeIntervalSince1970 - earlier.timeIntervalSince1970
    return Int(diff < 0 ? diff.rounded(.up) : diff.rounded(.down))
  }

  /// The difference between two dates on the opinionated `useTimeAgo` scale.
  ///
  /// - All months are considered exactly 30 days.
  /// - Dates assume `earlier <= later`, and otherwise return `.now`.
  public static func dateDiff(earlier: Date, later: Date) -> RelativeTime {
    var value = 0
    var unit = RelativeTimeUnit.now
    let diffSeconds = differenceInSeconds(later, earlier)

    if diffSeconds < diffNow {
      value = 0
      unit = .now
    } else if diffSeconds < secondsPerMinute {
      value = diffSeconds
      unit = .second
    } else if diffSeconds < secondsPerHour {
      value = diffSeconds / secondsPerMinute
      unit = .minute
    } else if diffSeconds < secondsPerDay {
      value = diffSeconds / secondsPerHour
      unit = .hour
    } else if diffSeconds < secondsPerMonth30 {
      value = diffSeconds / secondsPerDay
      unit = .day
    } else {
      value = diffSeconds / secondsPerMonth30
      unit = .month
    }

    return RelativeTime(value: value, unit: unit, earlier: earlier, later: later)
  }

  /// Formats a difference as a short relative label (`2h`, `5m`, `now`), or a
  /// short locale date once the difference passes twelve months.
  public static func formatDateDiff(
    _ diff: RelativeTime, locale: Locale = Locale(identifier: "en_US")
  ) -> String {
    switch diff.unit {
    case .now: return "now"
    case .second: return "\(diff.value)s"
    case .minute: return "\(diff.value)m"
    case .hour: return "\(diff.value)h"
    case .day: return "\(diff.value)d"
    case .month:
      if diff.value < 12 {
        return "\(diff.value)mo"
      }
      let formatter = DateFormatter()
      formatter.locale = locale
      formatter.dateStyle = .short
      formatter.timeStyle = .none
      return formatter.string(from: diff.earlier)
    }
  }
}

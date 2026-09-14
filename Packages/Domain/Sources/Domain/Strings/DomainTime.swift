import Foundation

/// Port of `src/lib/strings/time.ts` and the pure parts of
/// `src/lib/hooks/useTimeAgo.ts`.
///
/// Deviation: the RN versions take a Lingui `i18n` instance and return
/// translated copy. There is no i18n runtime in Domain (Linux-verifiable), so
/// the plural/date formatting here takes a `Locale` and produces the English
/// source strings. Callers that need translated copy can re-map the units.
public enum DomainTime {

  /// Age in whole years between `birthDate` and `today`.
  public static func getAge(birthDate: Date, now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
    let todayYear = calendar.component(.year, from: now)
    let todayMonth = calendar.component(.month, from: now)
    let todayDay = calendar.component(.day, from: now)
    let birthYear = calendar.component(.year, from: birthDate)
    let birthMonth = calendar.component(.month, from: birthDate)
    let birthDay = calendar.component(.day, from: birthDate)

    var age = todayYear - birthYear
    let monthDelta = todayMonth - birthMonth
    if monthDelta < 0 || (monthDelta == 0 && todayDay < birthDay) {
      age -= 1
    }
    return age
  }

  /// A date `years` years before `now` (mirrors `date.setFullYear(getFullYear() - years)`).
  public static func getDateAgo(years: Int, now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: now)
    components.year = (components.year ?? 0) - years
    return calendar.date(from: components) ?? now
  }

  /// Compares two dates by year, month, and day only.
  public static func simpleAreDatesEqual(_ a: Date, _ b: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
    let comps: Set<Calendar.Component> = [.year, .month, .day]
    let ac = calendar.dateComponents(comps, from: a)
    let bc = calendar.dateComponents(comps, from: b)
    return ac.year == bc.year && ac.month == bc.month && ac.day == bc.day
  }

  /// Default (`dateStyle: .long`, `timeStyle: .short`) date/time rendering.
  public static func niceDate(
    _ date: Date,
    dateStyle: DateFormatter.Style = .long,
    timeStyle: DateFormatter.Style? = .short,
    locale: Locale = Locale(identifier: "en_US")
  ) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.dateStyle = dateStyle
    if let timeStyle {
      formatter.timeStyle = timeStyle
      return formatter.string(from: date)
    }
    formatter.timeStyle = .none
    return formatter.string(from: date)
  }

  /// `dateStyle: 'dot separated'` - `[time] · [date]`.
  public static func dotSeparatedDate(
    _ date: Date,
    timeStyle: DateFormatter.Style = .short,
    locale: Locale = Locale(identifier: "en_US")
  ) -> String {
    let time = niceDate(date, dateStyle: .none, timeStyle: timeStyle, locale: locale)
    let day = niceDate(date, dateStyle: .medium, timeStyle: nil, locale: locale)
    return "\(time) · \(day)"
  }
}

// MARK: - Relative time (`useTimeAgo.ts`)

/// The unit of a `dateDiff` result.
public enum DateDiffUnit: String, Hashable, Sendable {
  case now
  case second
  case minute
  case hour
  case day
  case month
}

/// Output format for ``DomainTime/formatDateDiff(_:format:locale:)``.
public enum DateDiffFormat: String, Hashable, Sendable {
  case long
  case short
}

/// The difference between two dates on the opinionated `useTimeAgo` scale.
public struct DateDiff: Hashable, Sendable {
  public let value: Int
  public let unit: DateDiffUnit
  public let earlier: Date
  public let later: Date

  public init(value: Int, unit: DateDiffUnit, earlier: Date, later: Date) {
    self.value = value
    self.unit = unit
    self.earlier = earlier
    self.later = later
  }
}

extension DomainTime {
  /// Seconds below which a difference reads as "now".
  public static let diffNow = 5
  static let secondsPerMinute = 60
  static let secondsPerHour = secondsPerMinute * 60
  static let secondsPerDay = secondsPerHour * 24
  static let secondsPerMonth30 = secondsPerDay * 30

  /// Whole-second difference, matching date-fns `differenceInSeconds`
  /// (truncation toward zero).
  static func differenceInSeconds(_ later: Date, _ earlier: Date) -> Int {
    let diff = (later.timeIntervalSince1970 - earlier.timeIntervalSince1970)
    return Int(diff < 0 ? diff.rounded(.up) : diff.rounded(.down))
  }

  /// Returns the difference between `earlier` and `later` dates, based on
  /// opinionated rules.
  ///
  /// - All months are considered exactly 30 days.
  /// - Dates assume `earlier <= later`, and will otherwise return `.now`.
  /// - All values round down (or up when `rounding == .up`).
  public static func dateDiff(
    earlier: Date,
    later: Date,
    rounding: Rounding = .down
  ) -> DateDiff {
    var value = 0
    var unit = DateDiffUnit.now
    let diffSeconds = differenceInSeconds(later, earlier)

    if diffSeconds < diffNow {
      value = 0
      unit = .now
    } else if diffSeconds < secondsPerMinute {
      value = diffSeconds
      unit = .second
    } else if diffSeconds < secondsPerHour {
      value = divide(diffSeconds, secondsPerMinute, rounding)
      unit = .minute
    } else if diffSeconds < secondsPerDay {
      value = divide(diffSeconds, secondsPerHour, rounding)
      unit = .hour
    } else if diffSeconds < secondsPerMonth30 {
      value = divide(diffSeconds, secondsPerDay, rounding)
      unit = .day
    } else {
      value = divide(diffSeconds, secondsPerMonth30, rounding)
      unit = .month
    }

    return DateDiff(value: value, unit: unit, earlier: earlier, later: later)
  }

  /// Rounding direction for the non-exact units.
  public enum Rounding: Hashable, Sendable {
    case up
    case down
  }

  private static func divide(_ seconds: Int, _ unitSeconds: Int, _ rounding: Rounding) -> Int {
    switch rounding {
    case .up: Int((Double(seconds) / Double(unitSeconds)).rounded(.up))
    case .down: seconds / unitSeconds
    }
  }

  /// Formats a ``DateDiff`` as a natural-language string.
  ///
  /// - All months are considered exactly 30 days.
  /// - Differences >= 360 days are returned as a short locale date.
  public static func formatDateDiff(
    _ diff: DateDiff,
    format: DateDiffFormat = .short,
    locale: Locale = Locale(identifier: "en_US")
  ) -> String {
    let long = format == .long

    switch diff.unit {
    case .now:
      return "now"
    case .second:
      return long ? DomainTime.plural(diff.value, "second") : "\(diff.value)s"
    case .minute:
      return long ? DomainTime.plural(diff.value, "minute") : "\(diff.value)m"
    case .hour:
      return long ? DomainTime.plural(diff.value, "hour") : "\(diff.value)h"
    case .day:
      return long ? DomainTime.plural(diff.value, "day") : "\(diff.value)d"
    case .month:
      if diff.value < 12 {
        return long ? DomainTime.plural(diff.value, "month") : "\(diff.value)mo"
      }
      let formatter = DateFormatter()
      formatter.locale = locale
      formatter.dateStyle = .short
      formatter.timeStyle = .none
      return formatter.string(from: diff.earlier)
    }
  }

  /// `# second` / `# seconds` - the English singular/plural source strings
  /// Lingui emits for these messages.
  static func plural(_ value: Int, _ noun: String) -> String {
    "\(value) \(value == 1 ? noun : noun + "s")"
  }
}

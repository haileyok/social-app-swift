import Foundation

/// Datetime helpers for the wire `format: datetime` strings.
///
/// The generated lexicon runtime parses and validates ISO-8601 datetime strings
/// (`FormatString<Date>`), but constructing one from a `Date` still needs the
/// string form. RN's `toDatetimeString` in `src/lib/strings/time.ts` is the
/// port source: a millisecond-precision UTC ISO-8601 string.
public enum MessagesDate {
  /// Formats a date as the wire datetime string, e.g.
  /// `2026-08-31T00:00:00.000Z`.
  public static func datetimeString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
  }

  /// Parses a wire datetime string, or `nil` when it is not ISO-8601.
  public static func date(from string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)
  }
}

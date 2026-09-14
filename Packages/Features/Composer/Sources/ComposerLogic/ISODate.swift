import Foundation

/// Formats a `Date` the way `toDatetimeString` does in the RN app
/// (`@atproto/syntax`): an ISO-8601 instant with milliseconds and a `Z` suffix.
///
/// The lexicon `FormatString<Date>` validator accepts this shape, and the
/// composer's record builders all funnel through here so timestamps are
/// formatted identically everywhere.
public func isoString(_ date: Date) -> String {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  return formatter.string(from: date)
}

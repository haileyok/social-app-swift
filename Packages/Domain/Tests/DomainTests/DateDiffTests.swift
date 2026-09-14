import Foundation
import Testing

@testable import Domain

/// Port of `src/lib/hooks/__tests__/useTimeAgo.test.ts` (the `dateDiff` suite,
/// case for case).
@Suite("dateDiff")
struct DateDiffTests {
  let base = ISO8601DateFormatter().date(from: "2024-06-17T00:00:00Z")!

  func sub(_ base: Date, seconds: Double) -> Date {
    base.addingTimeInterval(-seconds)
  }

  func sub(_ base: Date, minutes: Double) -> Date {
    base.addingTimeInterval(-minutes * 60)
  }

  func sub(_ base: Date, hours: Double) -> Date {
    base.addingTimeInterval(-hours * 3600)
  }

  func sub(_ base: Date, days: Double) -> Date {
    base.addingTimeInterval(-days * 86400)
  }

  func expectDiff(_ diff: DateDiff, value: Int, unit: DateDiffUnit, earlier: Date, later: Date) {
    #expect(diff.value == value)
    #expect(diff.unit == unit)
    #expect(diff.earlier == earlier)
    #expect(diff.later == later)
  }

  @Test func worksWithNumbers() {
    let earlier = sub(base, days: 3)
    expectDiff(DomainTime.dateDiff(earlier: earlier, later: base), value: 3, unit: .day, earlier: earlier, later: base)
  }

  @Test func worksWithStrings() {
    let earlier = sub(base, days: 3)
    let later = ISO8601DateFormatter().date(from: "2024-06-17T00:00:00Z")!
    expectDiff(DomainTime.dateDiff(earlier: earlier, later: later), value: 3, unit: .day, earlier: earlier, later: later)
  }

  @Test func worksWithDates() {
    let earlier = sub(base, days: 3)
    expectDiff(DomainTime.dateDiff(earlier: earlier, later: base), value: 3, unit: .day, earlier: earlier, later: base)
  }

  @Test func equalValuesReturnNow() {
    expectDiff(DomainTime.dateDiff(earlier: base, later: base), value: 0, unit: .now, earlier: base, later: base)
  }

  @Test func futureDatesReturnNow() {
    let earlier = base.addingTimeInterval(3 * 86400)
    expectDiff(DomainTime.dateDiff(earlier: earlier, later: base), value: 0, unit: .now, earlier: earlier, later: base)
  }

  @Test func valuesUnder5SecondsAgoReturnNow() {
    let then = sub(base, seconds: 4)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 0, unit: .now, earlier: then, later: base)
  }

  @Test func valuesAtLeast5SecondsAgoReturnSeconds() {
    let then = sub(base, seconds: 5)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 5, unit: .second, earlier: then, later: base)
  }

  @Test func valuesUnder1MinReturnSeconds() {
    let then = sub(base, seconds: 59)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 59, unit: .second, earlier: then, later: base)
  }

  @Test func valuesAtLeast1MinReturnMinutes() {
    let then = sub(base, seconds: 60)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 1, unit: .minute, earlier: then, later: base)
  }

  @Test func minutesRoundDown() {
    let then = sub(base, seconds: 119)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 1, unit: .minute, earlier: then, later: base)
  }

  @Test func valuesUnder1HourReturnMinutes() {
    let then = sub(base, minutes: 59)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 59, unit: .minute, earlier: then, later: base)
  }

  @Test func valuesAtLeast1HourReturnHours() {
    let then = sub(base, minutes: 60)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 1, unit: .hour, earlier: then, later: base)
  }

  @Test func hoursRoundDown() {
    let then = sub(base, minutes: 119)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 1, unit: .hour, earlier: then, later: base)
  }

  @Test func valuesUnder1DayReturnHours() {
    let then = sub(base, hours: 23)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 23, unit: .hour, earlier: then, later: base)
  }

  @Test func valuesAtLeast1DayReturnDays() {
    let then = sub(base, hours: 24)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 1, unit: .day, earlier: then, later: base)
  }

  @Test func daysRoundDown() {
    let then = sub(base, hours: 47)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 1, unit: .day, earlier: then, later: base)
  }

  @Test func valuesUnder30DaysReturnDays() {
    let then = sub(base, days: 29)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 29, unit: .day, earlier: then, later: base)
  }

  @Test func valuesAtLeast30DaysReturnMonths() {
    let then = sub(base, days: 30)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 1, unit: .month, earlier: then, later: base)
  }

  @Test func monthsRoundDown() {
    let then = sub(base, days: 59)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 1, unit: .month, earlier: then, later: base)
  }

  @Test func valuesAreRoundedByIncrementsOf30() {
    let then = sub(base, days: 61)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 2, unit: .month, earlier: then, later: base)
  }

  @Test func valuesUnder360DaysReturnMonths() {
    let then = sub(base, days: 359)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 11, unit: .month, earlier: then, later: base)
  }

  @Test func valuesAtLeast360DaysReturnTheEarlierValue() {
    let then = sub(base, days: 360)
    expectDiff(DomainTime.dateDiff(earlier: then, later: base), value: 12, unit: .month, earlier: then, later: base)
  }

  // MARK: - formatDateDiff (the narrow forms the app renders)

  @Test func formatShortForms() {
    let cases: [(Int, DateDiffUnit, String)] = [
      (0, .now, "now"),
      (2, .second, "2s"),
      (5, .minute, "5m"),
      (3, .hour, "3h"),
      (2, .day, "2d"),
      (3, .month, "3mo"),
    ]
    for (value, unit, expected) in cases {
      let diff = DateDiff(value: value, unit: unit, earlier: base, later: base)
      #expect(DomainTime.formatDateDiff(diff, format: .short) == expected)
    }
  }

  @Test func formatLongForms() {
    let cases: [(Int, DateDiffUnit, String)] = [
      (0, .now, "now"),
      (1, .second, "1 second"),
      (2, .second, "2 seconds"),
      (1, .minute, "1 minute"),
      (5, .minute, "5 minutes"),
      (1, .hour, "1 hour"),
      (3, .hour, "3 hours"),
      (1, .day, "1 day"),
      (2, .day, "2 days"),
      (1, .month, "1 month"),
      (3, .month, "3 months"),
    ]
    for (value, unit, expected) in cases {
      let diff = DateDiff(value: value, unit: unit, earlier: base, later: base)
      #expect(DomainTime.formatDateDiff(diff, format: .long) == expected)
    }
  }

  /// `diff.value >= 12` months (i.e. >= 360 days) renders the earlier date.
  @Test func twelveMonthsRenderTheDate() {
    let diff = DateDiff(value: 12, unit: .month, earlier: base, later: base)
    let rendered = DomainTime.formatDateDiff(diff, format: .short)
    #expect(!rendered.hasSuffix("mo"))
    #expect(!rendered.isEmpty)
  }
}

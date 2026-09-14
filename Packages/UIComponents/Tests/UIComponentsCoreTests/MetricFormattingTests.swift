import Foundation
import Testing

@testable import UIComponentsCore

/// The formatters are ports of `Domain.FormatCount`/`Domain.DomainTime`, which
/// cannot be linked into the iOS target. These assert the ported behaviour, so a
/// drift from the originals is caught here.
@Suite("Metric formatting")
struct MetricFormattingTests {
  @Test("Counts use the compact suffix table")
  func counts() {
    #expect(MetricFormat.formatCount(0) == "0")
    #expect(MetricFormat.formatCount(999) == "999")
    #expect(MetricFormat.formatCount(1000) == "1K")
    #expect(MetricFormat.formatCount(1200) == "1.2K")
    #expect(MetricFormat.formatCount(2500) == "2.5K")
    #expect(MetricFormat.formatCount(1_234_567) == "1.2M")
    #expect(MetricFormat.formatCount(1_000_000_000) == "1B")
    #expect(MetricFormat.formatCount(1_000_000_000_000) == "1T")
  }

  @Test("A negative count keeps its sign")
  func negative() {
    #expect(MetricFormat.formatCount(-2500) == "-2.5K")
  }

  @Test("Non-finite counts render their symbols rather than trapping")
  func nonFinite() {
    #expect(MetricFormat.formatCount(Double.nan) == "NaN")
    #expect(MetricFormat.formatCount(Double.infinity) == "∞")
    #expect(MetricFormat.formatCount(-Double.infinity) == "-∞")
  }

  @Test("The mantissa truncates rather than rounding")
  func truncation() {
    // 1999 / 1000 = 1.999, truncated to one fractional digit.
    #expect(MetricFormat.formatCount(1999) == "1.9K")
  }
}

@Suite("Relative time formatting")
struct MetricTimeTests {
  private func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
  }

  @Test("Differences below the threshold read as now")
  func now() {
    let earlier = date("2026-09-14T12:00:00Z")
    let later = date("2026-09-14T12:00:03Z")
    #expect(MetricTime.formatDateDiff(MetricTime.dateDiff(earlier: earlier, later: later)) == "now")
  }

  @Test("Each unit renders its short label")
  func units() {
    let earlier = date("2026-09-14T12:00:00Z")
    func label(seconds: TimeInterval) -> String {
      let later = earlier.addingTimeInterval(seconds)
      return MetricTime.formatDateDiff(MetricTime.dateDiff(earlier: earlier, later: later))
    }
    #expect(label(seconds: 30) == "30s")
    #expect(label(seconds: 300) == "5m")
    #expect(label(seconds: 7200) == "2h")
    #expect(label(seconds: 86_400 * 3) == "3d")
    #expect(label(seconds: 86_400 * 60) == "2mo")
  }

  @Test("Past a year the label becomes a short date")
  func dateAfterAMonth() {
    let earlier = date("2024-01-15T12:00:00Z")
    let later = date("2026-09-14T12:00:00Z")
    let label = MetricTime.formatDateDiff(MetricTime.dateDiff(earlier: earlier, later: later))
    // `dateStyle = .short` in en_US renders M/d/yy.
    #expect(label == "1/15/24")
  }

  @Test("The ported output matches the Domain original")
  func parityWithDomain() {
    // These are the values the Domain package produces for the same inputs;
    // recorded here so the port cannot drift silently while the dependency is
    // unusable from iOS.
    let earlier = date("2026-09-14T10:00:00Z")
    let later = date("2026-09-14T12:00:00Z")
    #expect(MetricTime.formatDateDiff(MetricTime.dateDiff(earlier: earlier, later: later)) == "2h")
  }
}

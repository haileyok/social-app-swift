import Foundation
import Testing

@testable import Domain

/// `formatCount` matches `Intl.NumberFormat('en', {notation: 'compact',
/// maximumFractionDigits: 1, roundingMode: 'trunc'})`.
///
/// There is no TS test for this in the RN repo; the expectations below were
/// captured from Node's Intl implementation, which is what the RN app calls.
@Suite("formatCount")
struct FormatCountTests {

  @Test func smallNumbersAreUnchanged() {
    #expect(FormatCount.formatCount(0) == "0")
    #expect(FormatCount.formatCount(5) == "5")
    #expect(FormatCount.formatCount(999) == "999")
    #expect(FormatCount.formatCount(950) == "950")
  }

  @Test func thousandsUseK() {
    #expect(FormatCount.formatCount(1000) == "1K")
    #expect(FormatCount.formatCount(1001) == "1K")
    #expect(FormatCount.formatCount(1049) == "1K")
    #expect(FormatCount.formatCount(1234) == "1.2K")
    #expect(FormatCount.formatCount(1450) == "1.4K")
    #expect(FormatCount.formatCount(1500) == "1.5K")
    #expect(FormatCount.formatCount(1999) == "1.9K")
    #expect(FormatCount.formatCount(15300) == "15.3K")
  }

  @Test func fractionalDigitsAreTruncatedNotRounded() {
    #expect(FormatCount.formatCount(1450) == "1.4K")
    #expect(FormatCount.formatCount(1999) == "1.9K")
    #expect(FormatCount.formatCount(999499) == "999.4K")
    #expect(FormatCount.formatCount(123.456) == "123.4")
  }

  @Test func largeMagnitudesUseMBAndT() {
    #expect(FormatCount.formatCount(999999) == "999.9K")
    #expect(FormatCount.formatCount(1_000_000) == "1M")
    #expect(FormatCount.formatCount(1_234_567) == "1.2M")
    #expect(FormatCount.formatCount(999_999_999) == "999.9M")
    #expect(FormatCount.formatCount(1_000_000_000) == "1B")
    #expect(FormatCount.formatCount(1_000_000_000_000) == "1T")
  }

  /// Only the `T` tier reaches a mantissa large enough to need grouping, and
  /// Intl group-separates it once it has five integer digits.
  @Test func trillionMantissaGroupsAtFiveDigits() {
    #expect(FormatCount.formatCount(2_500_000_000_000_000) == "2500T")
    #expect(FormatCount.formatCount(1e16) == "10,000T")
  }

  @Test func negativeValuesKeepTheirSign() {
    #expect(FormatCount.formatCount(-1) == "-1")
    #expect(FormatCount.formatCount(-1_234) == "-1.2K")
    #expect(FormatCount.formatCount(-999_999) == "-999.9K")
  }

  @Test func subOneValuesTruncateToZeroOrOneDecimal() {
    #expect(FormatCount.formatCount(0.5) == "0.5")
    #expect(FormatCount.formatCount(0.05) == "0")
  }
}

/// Port of `src/lib/numbers.ts` (`clamp`).
@Suite("clamp")
struct ClampTests {
  @Test func clampsWithinBounds() {
    #expect(DomainNumbers.clamp(5.0, 0.0, 10.0) == 5.0)
    #expect(DomainNumbers.clamp(-5.0, 0.0, 10.0) == 0.0)
    #expect(DomainNumbers.clamp(15.0, 0.0, 10.0) == 10.0)
    #expect(DomainNumbers.clamp(5, 0, 10) == 5)
    #expect(DomainNumbers.clamp(-5, 0, 10) == 0)
    #expect(DomainNumbers.clamp(15, 0, 10) == 10)
  }
}

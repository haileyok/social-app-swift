import DesignTokens
import Testing

@testable import DesignSystemCore

@Suite("Text metric resolution")
struct TextMetricsTests {
  @Test("relative line heights become rounded absolute points")
  func relativeLineHeight() {
    // 15pt * 1.3 snug = 19.5 -> 20
    let snug = TextMetrics.resolve(
      size: Scales.FontSize.md, relativeLineHeight: Scales.LineHeight.snug)
    #expect(snug.size == 15)
    #expect(snug.lineHeight == 20)

    // 9.4pt * 1.15 tight = 10.81 -> 11
    let tight = TextMetrics.resolve(
      size: Scales.FontSize.xxs, relativeLineHeight: Scales.LineHeight.tight)
    #expect(tight.lineHeight == 11)
  }

  @Test("values above 2 are treated as absolute, per normalizeTextStyles")
  func absoluteLineHeight() {
    let metrics = TextMetrics.resolve(size: 15, relativeLineHeight: 24)
    #expect(metrics.lineHeight == 24)
  }

  @Test("a zero line height resolves to the platform default")
  func zeroLineHeight() {
    #expect(TextMetrics.resolve(size: 15, relativeLineHeight: 0).lineHeight == nil)
  }

  @Test("the font scale multiplier is applied to the size before line height")
  func fontScale() {
    let scaled = TextMetrics.resolve(
      size: Scales.FontSize.md,
      relativeLineHeight: Scales.LineHeight.snug,
      fontScale: FontScale.multiplier(for: .plus1))
    #expect(abs(scaled.size - 15 * 1.0625) < 0.0001)
    // 15.9375 * 1.3 = 20.71875 -> 21
    #expect(scaled.lineHeight == 21)
  }

  @Test("tracking defaults to the ALF token and follows the system override")
  func tracking() {
    #expect(TextMetrics.resolve(size: 15, relativeLineHeight: 1.3).tracking == Scales.tracking)
    let system = TextMetrics.resolve(
      size: 15, relativeLineHeight: 1.3, tracking: FontScale.systemFontLetterSpacing)
    #expect(system.tracking == 0.25)
  }

  @Test("the weight resolves to a number and falls back to 400")
  func weight() {
    #expect(TextMetrics.resolve(size: 15, relativeLineHeight: 1.3, weight: Scales.FontWeight.bold).weight == 700)
    #expect(TextMetrics.resolve(size: 15, relativeLineHeight: 1.3, weight: "800").weight == 400)
  }
}

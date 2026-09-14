import Testing

@testable import DesignTokens

/**
 Pins every static scale value against `@bsky.app/alf@0.1.15` `src/tokens.ts`.
 These are AC.7 assertions: if ALF ever changes a value, these fail loudly.
 */
@Suite struct ScalesTests {
  @Test func spacing() {
    #expect(Scales.Spacing.xxs == 2)  // _2xs
    #expect(Scales.Spacing.xs == 4)
    #expect(Scales.Spacing.sm == 8)
    #expect(Scales.Spacing.md == 12)
    #expect(Scales.Spacing.lg == 16)
    #expect(Scales.Spacing.xl == 20)
    #expect(Scales.Spacing.xxl == 24)  // _2xl
    #expect(Scales.Spacing.xxxl == 28)  // _3xl
    #expect(Scales.Spacing.xxxxl == 32)  // _4xl
    #expect(Scales.Spacing.xxxxxl == 40)  // _5xl
  }

  @Test func fontSize() {
    #expect(Scales.FontSize.xxs == 9.4)  // _2xs
    #expect(Scales.FontSize.xs == 11.3)
    #expect(Scales.FontSize.sm == 13.1)
    #expect(Scales.FontSize.md == 15)
    #expect(Scales.FontSize.lg == 16.9)
    #expect(Scales.FontSize.xl == 18.8)
    #expect(Scales.FontSize.xxl == 20.6)  // _2xl
    #expect(Scales.FontSize.xxxl == 24.3)  // _3xl
    #expect(Scales.FontSize.xxxxl == 30)  // _4xl
    #expect(Scales.FontSize.xxxxxl == 37.5)  // _5xl
  }

  @Test func lineHeight() {
    #expect(Scales.LineHeight.tight == 1.15)
    #expect(Scales.LineHeight.snug == 1.3)
    #expect(Scales.LineHeight.relaxed == 1.5)
  }

  @Test func radius() {
    #expect(Scales.Radius.xxs == 2)  // _2xs
    #expect(Scales.Radius.xs == 4)
    #expect(Scales.Radius.sm == 8)
    #expect(Scales.Radius.md == 12)
    #expect(Scales.Radius.lg == 16)
    #expect(Scales.Radius.xl == 20)
    #expect(Scales.Radius.full == 999)
  }

  @Test func fontWeight() {
    #expect(Scales.FontWeight.normal == "400")
    #expect(Scales.FontWeight.medium == "500")
    #expect(Scales.FontWeight.semiBold == "600")
    #expect(Scales.FontWeight.bold == "700")
  }

  @Test func tracking() {
    #expect(Scales.tracking == 0)
  }
}

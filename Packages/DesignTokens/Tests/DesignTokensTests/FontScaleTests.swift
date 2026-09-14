import Testing

@testable import DesignTokens

/** Pins the user font-scale steps against `src/alf/fonts.ts`. */
@Suite struct FontScaleTests {
  @Test func step() {
    #expect(FontScale.step == 0.0625)
  }

  @Test func multipliersMatchALF() {
    // ALF deliberately collapses the extreme steps onto their neighbours.
    #expect(FontScale.multiplier(for: .minus2) == 1 - 0.0625)
    #expect(FontScale.multiplier(for: .minus1) == 1 - 0.0625)
    #expect(FontScale.multiplier(for: .zero) == 1)
    #expect(FontScale.multiplier(for: .plus1) == 1 + 0.0625)
    #expect(FontScale.multiplier(for: .plus2) == 1 + 0.0625)
  }

  @Test func allStepsCovered() {
    #expect(FontScale.Step.allCases.count == 5)
    for step in FontScale.Step.allCases {
      #expect(FontScale.multipliers[step] != nil)
    }
  }

  @Test func systemFontLetterSpacing() {
    #expect(FontScale.systemFontLetterSpacing == 0.25)
  }
}

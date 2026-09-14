import DesignTokens
import Testing

@testable import DesignSystemCore

@Suite("Font weight mapping")
struct FontWeightTests {
  @Test("the four ALF tokens map to their numeric weights")
  func tokens() {
    #expect(FontWeightScale.numericWeight(forCSSWeight: Scales.FontWeight.normal) == 400)
    #expect(FontWeightScale.numericWeight(forCSSWeight: Scales.FontWeight.medium) == 500)
    #expect(FontWeightScale.numericWeight(forCSSWeight: Scales.FontWeight.semiBold) == 600)
    #expect(FontWeightScale.numericWeight(forCSSWeight: Scales.FontWeight.bold) == 700)
  }

  @Test("the mapping is total over the token set")
  func total() {
    #expect(FontWeightScale.all.allSatisfy { FontWeightScale.numericWeight(forCSSWeight: $0.token) != nil })
    #expect(FontWeightScale.all.count == 4)
  }

  @Test("unknown weights do not map", arguments: ["", "800", "900", "regular", "bolder"])
  func unknown(_ input: String) {
    #expect(FontWeightScale.numericWeight(forCSSWeight: input) == nil)
  }

  @Test("the fallback is ALF's Inter-Regular, i.e. 400")
  func fallback() {
    #expect(FontWeightScale.fallback == 400)
  }
}

import Testing
@testable import ATSyntax

@Suite struct SmokeTests {
  @Test func placeholderCompiles() {
    #expect(true)
  }
}

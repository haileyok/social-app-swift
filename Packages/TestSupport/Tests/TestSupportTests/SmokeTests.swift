import Testing
@testable import TestSupport

@Suite struct SmokeTests {
  @Test func placeholderCompiles() {
    #expect(true)
  }
}

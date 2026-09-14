import Testing

@testable import DesignSystemCore

@Suite("Breakpoint math")
struct BreakpointTests {
  @Test("thresholds are the RN media queries")
  func thresholds() {
    #expect(Breakpoints.phone == 500)
    #expect(Breakpoints.mobile == 800)
    #expect(Breakpoints.tablet == 1300)
    #expect(Breakpoints.rightNavMinWidth == 1100)
    #expect(Breakpoints.centerColumnMaxWidth == 1300)
  }

  @Test("thresholds are inclusive, as react-responsive minWidth is")
  func inclusive() {
    #expect(Breakpoints.isAtLeast(.phone, width: 500, isRegularWidth: true))
    #expect(Breakpoints.isAtLeast(.mobile, width: 800, isRegularWidth: true))
    #expect(Breakpoints.isAtLeast(.tablet, width: 1300, isRegularWidth: true))
    #expect(!Breakpoints.isAtLeast(.phone, width: 499.9, isRegularWidth: true))
    #expect(!Breakpoints.isAtLeast(.tablet, width: 1299.9, isRegularWidth: true))
  }

  @Test("the width class gates the phone and mobile steps")
  func sizeClassGate() {
    #expect(!Breakpoints.isAtLeast(.phone, width: 600, isRegularWidth: false))
    #expect(!Breakpoints.isAtLeast(.mobile, width: 900, isRegularWidth: false))
    // The tablet step is a pure width threshold: iPad Pro landscape is always
    // regular width anyway, and the 1300 line is not about the class.
    #expect(Breakpoints.isAtLeast(.tablet, width: 1400, isRegularWidth: false))
  }

  @Test("active reports the largest threshold cleared")
  func active() {
    #expect(Breakpoints.active(width: 400, isRegularWidth: false) == nil)
    #expect(Breakpoints.active(width: 500, isRegularWidth: true) == .phone)
    #expect(Breakpoints.active(width: 800, isRegularWidth: true) == .mobile)
    #expect(Breakpoints.active(width: 1300, isRegularWidth: true) == .tablet)
    #expect(Breakpoints.active(width: 1200, isRegularWidth: false) == nil)
  }

  @Test("shell layout breakpoints", arguments: [
    (1000.0, false, false, true),
    (1100.0, true, true, true),
    (1200.0, true, true, true),
    (1300.0, true, true, true),
    (1301.0, true, false, false),
  ])
  func shellLayout(width: Double, rightNav: Bool, offset: Bool, leftMinimal: Bool) {
    #expect(Breakpoints.isRightNavVisible(width: width) == rightNav)
    #expect(Breakpoints.isCenterColumnOffset(width: width) == offset)
    #expect(Breakpoints.isLeftNavMinimal(width: width) == leftMinimal)
  }
}

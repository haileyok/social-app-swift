import DesignTokens
import Testing

@testable import DesignSystemCore

@Suite("Shadow geometry")
struct ShadowGeometryTests {
  @Test("the five atoms match ALF's native shadow props")
  func atoms() {
    #expect(ShadowGeometry.xs == ShadowGeometry(radius: 8, elevation: 4, offsetX: 0, offsetY: 2, opacity: 0.1))
    #expect(ShadowGeometry.sm == ShadowGeometry(radius: 4, elevation: 8, offsetX: 0, offsetY: 4, opacity: 0.1))
    #expect(ShadowGeometry.md == ShadowGeometry(radius: 8, elevation: 16, offsetX: 0, offsetY: 8, opacity: 0.1))
    #expect(ShadowGeometry.lg == ShadowGeometry(radius: 16, elevation: 32, offsetX: 0, offsetY: 16, opacity: 0.1))
    #expect(ShadowGeometry.xl == ShadowGeometry(radius: 40, elevation: 48, offsetX: 0, offsetY: 10, opacity: 0.1))
  }

  @Test("every atom carries the same 0.1 opacity", arguments: ShadowGeometry.Size.allCases)
  func uniformOpacity(size: ShadowGeometry.Size) {
    #expect(ShadowGeometry.for(size).opacity == 0.1)
  }

  @Test("resolving combines the theme opacity with the atom opacity")
  func resolve() {
    let light = ResolvedShadow.resolve(.md, themeShadowOpacity: Theme.light.shadowOpacity)
    #expect(abs(light.alpha - 0.01) < 0.0001)
    #expect(light.radius == 8)
    #expect(light.offsetY == 8)

    let dark = ResolvedShadow.resolve(.md, themeShadowOpacity: Theme.dark.shadowOpacity)
    #expect(abs(dark.alpha - 0.04) < 0.0001)
  }
}

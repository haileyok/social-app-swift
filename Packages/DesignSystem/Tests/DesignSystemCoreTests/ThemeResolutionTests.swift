import DesignTokens
import Testing

@testable import DesignSystemCore

@Suite("Theme resolution")
struct ThemeResolutionTests {
  @Test("system follows the appearance scheme")
  func system() {
    #expect(ThemeResolver.resolve(preference: .system, systemScheme: .light).name == .light)
    #expect(ThemeResolver.resolve(preference: .system, systemScheme: .dark).name == .dark)
  }

  @Test("an explicit preference wins over the scheme")
  func explicit() {
    #expect(ThemeResolver.resolve(preference: .light, systemScheme: .dark).name == .light)
    #expect(ThemeResolver.resolve(preference: .dark, systemScheme: .light).name == .dark)
    #expect(ThemeResolver.resolve(preference: .dim, systemScheme: .light).name == .dim)
    #expect(ThemeResolver.resolve(preference: .dim, systemScheme: .dark).name == .dim)
  }

  @Test("the resolved theme is the token theme, unrecomposed")
  func identity() {
    #expect(ThemeResolver.resolve(preference: .dark, systemScheme: .light) == Theme.dark)
    #expect(ThemeResolver.resolve(preference: .dim, systemScheme: .dark) == Theme.dim)
  }

  @Test("name lookup covers all three themes")
  func lookup() {
    for name in ThemeName.allCases {
      #expect(ThemeResolver.theme(for: name).name == name)
    }
  }

  @Test("dim is a dark-scheme theme")
  func dimScheme() {
    #expect(ThemeResolver.resolve(preference: .dim, systemScheme: .light).scheme == .dark)
  }
}

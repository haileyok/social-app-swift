import DesignSystem
import DesignSystemCore
import SearchViews
import SwiftUI

// Re-exported so the app and its test targets reach `SearchAccessibility` (and
// the rest of the surface) through `import AppShell` alone, the same way they
// reach `ShellAccessibility` and `LoginAccessibility`. XCUITest bundles are
// built by the project rather than by a package, so they link only the AppShell
// product.
@_exported import SearchViews

/**
 The search surfaces the app shell can present.

 Mirrors `AppShell+Login.swift`: the hook lives in its own file so shell work on
 the root view and this debug surface do not conflict, and nothing here is
 referenced by the root view by default - the search screen is reachable from a
 tab toolbar, which keeps the 5-tab root and its smoke tests untouched.

 ```swift
 // A tab's toolbar, alongside the token-gallery and login links:
 SearchDebugButton()
 ```

 The fixture entry points build their state through `SearchLogic`'s own assembly
 and fixtures rather than hard-coding a page shape, so a screenshot of the
 completed state is an honest render of what the logic layer produces.
 */
public enum SearchSurfaces {
  /**
   The search screen, themed and ready to place above the tab bar.

   - Parameter theme: the theme preference the surface renders under, so the CI
     screenshot loop can capture it in each appearance without the root view
     knowing about search.
   */
  @MainActor
  public static func searchScreen(theme: ThemePreference = .system) -> some View {
    NavigationStack {
      SearchScreen(
        viewModel: SearchViewModel(),
        exploreData: SearchFixtures.explorePage,
        title: SearchCopy.searchTitle)
        .theme(theme)
    }
  }

  /**
   The search screen in its results state, over fixture posts.

   Used by previews and the screenshot loop: the state is driven through a
   fixture-backed view model rather than by the state machine's debounce, so the
   capture is deterministic.
   */
  @MainActor
  public static func searchResultsScreen(theme: ThemePreference = .system) -> some View {
    NavigationStack {
      SearchResultsScreen(theme: theme)
    }
  }

  /**
   The suggestion panel over fixture history and profiles.

   Rendered on its own so its three branches (search-for row, recents, resolved
   profiles) are all visible in one capture.
   */
  @MainActor
  public static func searchSuggestionsScreen(theme: ThemePreference = .system) -> some View {
    SearchSuggestionsList(
      suggestions: SearchFixtures.suggestions,
      history: SearchFixtures.history)
      .theme(theme)
      .background(ThemeResolver.theme(for: theme).atomColors.bg)
  }
}

/**
 The results surface over fixture data, wrapped in the screen chrome the search
 flow would otherwise provide.
 */
@MainActor
private struct SearchResultsScreen: View {
  let theme: ThemePreference

  var body: some View {
    SearchResultsView(
      model: SearchFixtures.resultsModel,
      posts: SearchFixtures.posts,
      starterPacks: [SearchFixtures.starterPack(name: "Bluesky Swift devs")],
      listState: .content)
      .theme(theme)
  }
}

/**
 The debug toolbar button that presents the search screen.

 `showsExplore` is on so the debug entry point always lands on the Explore
 fixture: the idle branch is the one the smoke test asserts, and whatever the
 machine happens to hold must not change that.
 */
public struct SearchDebugButton: View {
  @State private var isPresented = false

  public init() {}

  public var body: some View {
    Button {
      isPresented = true
    } label: {
      Image(systemName: "magnifyingglass")
    }
    .accessibilityLabel(SearchCopy.searchTitle)
    .accessibilityIdentifier(ShellAccessibility.searchButton)
    .sheet(isPresented: $isPresented) {
      SearchDebugSheet()
    }
  }
}

/**
 The presented search screen, with its own navigation stack for a title bar and
 the platform's close affordance.
 */
public struct SearchDebugSheet: View {
  @AppStorage("alfTheme") private var themePreference = ThemePreference.system.rawValue

  @Environment(\.dismiss) private var dismiss

  public init() {}

  public var body: some View {
    NavigationStack {
      SearchScreen(exploreData: SearchFixtures.explorePage)
        .theme(ThemePreference(rawValue: themePreference) ?? .system)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Close") { dismiss() }
              .accessibilityIdentifier(ShellAccessibility.searchCloseButton)
          }
        }
    }
    .accessibilityIdentifier(ShellAccessibility.searchSheet)
  }
}

#Preview("Search surfaces") {
  SearchSurfaces.searchScreen(theme: .light)
}

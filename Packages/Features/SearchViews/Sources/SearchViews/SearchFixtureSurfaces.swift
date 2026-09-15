import DesignSystem
import DesignSystemCore
import SwiftUI

/// Whole-surface fixtures for the search feature.
///
/// These build and return complete views, so a consumer that only wants to show
/// a search surface - the app shell's debug hook, the screenshot loop, a
/// preview - never has to name an `ExplorePageData`, a `SearchStateModel` or any
/// lexicon type at its own call site. That matters for the iOS link closure: a
/// call site that passes such a value as an argument emits a reference to the
/// defining module's type metadata, which would otherwise force every consumer
/// to declare a direct dependency on it.
///
/// The break-down of what each surface renders therefore lives here, next to the
/// fixtures it renders.
public enum SearchFixtureSurfaces {
  /// The search screen over the Explore fixture, wrapped in a navigation stack.
  @MainActor
  public static func searchScreen(theme: ThemePreference = .system) -> some View {
    NavigationStack {
      searchContent(theme: theme)
    }
  }

  /// The search screen's content over the Explore fixture, without navigation
  /// chrome, for callers that supply their own stack.
  @MainActor
  public static func searchContent(theme: ThemePreference = .system) -> some View {
    SearchScreen(
      viewModel: SearchViewModel(),
      exploreData: SearchFixtures.explorePage,
      title: SearchCopy.searchTitle)
      .theme(theme)
  }

  /// The results surface over the fixture posts, wrapped in a navigation stack.
  @MainActor
  public static func searchResultsScreen(theme: ThemePreference = .system) -> some View {
    NavigationStack {
      SearchResultsView(
        model: SearchFixtures.resultsModel,
        posts: SearchFixtures.posts,
        starterPacks: [SearchFixtures.starterPack(name: "Bluesky Swift devs")],
        listState: .content)
        .navigationTitle(SearchCopy.searchTitle)
        .navigationBarTitleDisplayMode(.inline)
        .theme(theme)
    }
  }

  /// The suggestion panel over the fixture history and profiles.
  @MainActor
  public static func searchSuggestionsScreen(theme: ThemePreference = .system) -> some View {
    ThemedSurface(theme: theme) {
      SearchSuggestionsList(
        suggestions: SearchFixtures.suggestions,
        history: SearchFixtures.history)
    }
  }
}

/// A fixture surface that fills its host and paints the active theme's page
/// background.
///
/// The `.theme(_:)` injection is outermost so the background reads the injected
/// theme too; a `.background(_:)` written after the injection would sit outside
/// it and see the default.
@MainActor
private struct ThemedSurface<Content: View>: View {
  let theme: ThemePreference
  let content: Content

  init(theme: ThemePreference, @ViewBuilder content: () -> Content) {
    self.theme = theme
    self.content = content()
  }

  var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(SurfaceBackground())
      .theme(theme)
  }
}

/// The active theme's page background.
@MainActor
private struct SurfaceBackground: View {
  @Environment(\.alfTheme) private var theme

  var body: some View {
    theme.atomColors.bg.ignoresSafeArea()
  }
}

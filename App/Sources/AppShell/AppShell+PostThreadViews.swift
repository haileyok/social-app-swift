import DesignSystem
import DesignSystemCore
import PostThreadViews
import SwiftUI
import UIComponents

/// The debug entry points into the thread surfaces.
///
/// Kept in its own file so this work does not touch `AppRootView.swift` or
/// `AppShell.swift`: nothing here is referenced by the root view yet, and the
/// shell can mount a screen once it wants one. The screens are driven entirely
/// by the fixture thread in `PostThreadViews`, so they render without a session,
/// a server or a query store.
///
/// ```swift
/// NavigationLink("Thread") { PostThreadSurfaces.threadScreen() }
/// ```
@MainActor
public enum PostThreadSurfaces {
  /// The thread screen over the sample fixture: two ancestors, a highlighted
  /// anchor, a nested conversation, a deleted reply, an OP-liked reply and a
  /// partly-hydrated branch that renders a read-more row.
  ///
  /// This is the surface the iOS screenshot loop captures.
  public static func threadScreen(
    theme preference: ThemePreference = .system
  ) -> some View {
    NavigationStack {
      PostThreadScreen(
        thread: ThreadFixtures.sampleThread(),
        now: fixtureNow)
        .theme(preference)
    }
  }

  /// The thread screen for a post that no longer exists, for the placeholder
  /// route.
  public static func deletedThreadScreen(
    theme preference: ThemePreference = .system
  ) -> some View {
    NavigationStack {
      PostThreadScreen(
        thread: ThreadFixtures.deletedAnchorThread(),
        now: fixtureNow)
        .theme(preference)
    }
  }

  /// The liked-by list over sample rows.
  public static func likesScreen(
    theme preference: ThemePreference = .system
  ) -> some View {
    NavigationStack {
      ThreadLikesScreen(likes: ThreadFixtures.sampleLikes())
        .theme(preference)
    }
  }

  /// The reposted-by list over sample rows.
  public static func repostsScreen(
    theme preference: ThemePreference = .system
  ) -> some View {
    NavigationStack {
      ThreadRepostsScreen(repostedBy: ThreadFixtures.sampleReposts())
        .theme(preference)
    }
  }

  /// The quotes list over sample rows.
  public static func quotesScreen(
    theme preference: ThemePreference = .system
  ) -> some View {
    NavigationStack {
      ThreadQuotesScreen(quotes: ThreadFixtures.sampleQuotes())
        .theme(preference)
    }
  }

  /// The blocked / not-found placeholders.
  public static func placeholderScreen(
    kind: PostThreadPlaceholderKind = .blocked,
    theme preference: ThemePreference = .system
  ) -> some View {
    PostThreadPlaceholderScreen(kind: kind)
      .theme(preference)
  }

  /// A fixed clock, so the relative timestamps in a screenshot do not drift
  /// between runs.
  private static let fixtureNow = ISO8601DateFormatter().date(from: "2026-01-01T13:00:00Z")!
}

import ATProtoClient
import DesignSystem
import DesignSystemCore
import Foundation
import Lexicons
import PostThreadLogic
import PostThreadViews
import SwiftUI
import UIComponents
import UIComponentsCore

struct PostLikesRouteView: View {
  let uri: String
  @Environment(ShellRouter.self) private var router
  @State private var likes: [PostLike]?
  @State private var failed = false

  var body: some View {
    Group {
      if let likes {
        ThreadLikesScreen(likes: likes, onSelect: { router.open(.profile(actor: $0)) })
      } else if failed {
        ThreadLikesScreen(
          likes: [],
          state: .error(
            .init(title: "Could not load likes", message: "Try again.", hasContent: false)),
          onRetry: { Task { await load() } })
      } else {
        ThreadLikesScreen(likes: [], state: .loading)
      }
    }
    .task { await load() }
  }

  private func load() async {
    guard let clients = router.clients else { failed = true; return }
    do {
      let output: App.Bsky.FeedGetLikes_Output = try await clients.appview.get(
        App.Bsky.FeedGetLikes.id,
        params: [("uri", uri), ("limit", String(PostThreadList.pageSize))])
      likes = output.likes.map {
        PostLike(
          actor: $0.actor, createdAt: $0.createdAt.rawValue, indexedAt: $0.indexedAt.rawValue)
      }
      failed = false
    } catch {
      failed = true
    }
  }
}

struct PostRepostsRouteView: View {
  let uri: String
  @Environment(ShellRouter.self) private var router
  @State private var profiles: [App.Bsky.ActorDefs_ProfileView]?
  @State private var failed = false

  var body: some View {
    Group {
      if let profiles {
        ThreadRepostsScreen(
          repostedBy: profiles, onSelect: { router.open(.profile(actor: $0)) })
      } else if failed {
        ThreadRepostsScreen(
          repostedBy: [],
          state: .error(
            .init(title: "Could not load reposts", message: "Try again.", hasContent: false)),
          onRetry: { Task { await load() } })
      } else {
        ThreadRepostsScreen(repostedBy: [], state: .loading)
      }
    }
    .task { await load() }
  }

  private func load() async {
    guard let clients = router.clients else { failed = true; return }
    do {
      let output: App.Bsky.FeedGetRepostedBy_Output = try await clients.appview.get(
        App.Bsky.FeedGetRepostedBy.id,
        params: [("uri", uri), ("limit", String(PostThreadList.pageSize))])
      profiles = output.repostedBy
      failed = false
    } catch {
      failed = true
    }
  }
}

struct PostQuotesRouteView: View {
  let uri: String
  @Environment(ShellRouter.self) private var router
  @State private var quotes: [PostQuote]?
  @State private var failed = false

  var body: some View {
    Group {
      if let quotes {
        ThreadQuotesScreen(quotes: quotes, onOpen: { router.open($0) })
      } else if failed {
        ThreadQuotesScreen(
          quotes: [],
          state: .error(
            .init(title: "Could not load quotes", message: "Try again.", hasContent: false)),
          onRetry: { Task { await load() } })
      } else {
        ThreadQuotesScreen(quotes: [], state: .loading)
      }
    }
    .task { await load() }
  }

  private func load() async {
    guard let clients = router.clients else { failed = true; return }
    do {
      let output: App.Bsky.FeedGetQuotes_Output = try await clients.appview.get(
        App.Bsky.FeedGetQuotes.id,
        params: [("uri", uri), ("limit", String(PostThreadList.pageSize))])
      quotes = output.posts.map(PostQuote.init)
      failed = false
    } catch {
      failed = true
    }
  }
}

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

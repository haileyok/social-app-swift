import DesignSystem
import DesignTokens
import Lexicons
import PostThreadLogic
import SwiftUI
import UIComponents
import UIComponentsCore

/// The actor lists behind a post: who liked it, who reposted it, who quoted it.
///
/// Three screens over the same shape, because they are three lists of rows with
/// different cells. RN splits these across `PostLikes`/`PostReposts`/
/// `PostQuotes`; here one screen per list with a shared row vocabulary keeps the
/// navigation titles and empty states in the strings seam.
///
/// The screens take their rows as values rather than queries. The query objects
/// (`LikedByQuery`, `RepostedByQuery`, `QuotesQuery`) live in `PostThreadLogic`
/// and are driven by the app's query store; a screen that rendered a query
/// would have to know about the store, and these lists are simple enough that
/// the caller can hand over the current page.

/// The liked-by list.
public struct ThreadLikesScreen: View {
  private let likes: [PostLike]
  private let strings: PostThreadStrings
  private let state: ListState
  private let onRetry: () -> Void
  private let onSelect: (String) -> Void

  public init(
    likes: [PostLike],
    strings: PostThreadStrings = .defaults,
    state: ListState = .content,
    onRetry: @escaping () -> Void = {},
    onSelect: @escaping (String) -> Void = { _ in }
  ) {
    self.likes = likes
    self.strings = strings
    self.state = state
    self.onRetry = onRetry
    self.onSelect = onSelect
  }

  public var body: some View {
    ActorListScaffold(
      title: strings.likedByTitle,
      empty: strings.likedByEmpty,
      rows: likes.map { like in
        ActorRow(
          did: like.actor.did.rawValue,
          handle: like.actor.handle.rawValue,
          displayName: like.actor.displayName,
          description: like.actor.description,
          avatar: like.actor.avatar?.rawValue)
      },
      state: state,
      strings: strings,
      onRetry: onRetry,
      onSelect: onSelect)
  }
}

/// The reposted-by list.
public struct ThreadRepostsScreen: View {
  private let repostedBy: [Lexicons.App.Bsky.ActorDefs_ProfileView]
  private let strings: PostThreadStrings
  private let state: ListState
  private let onRetry: () -> Void
  private let onSelect: (String) -> Void

  public init(
    repostedBy: [Lexicons.App.Bsky.ActorDefs_ProfileView],
    strings: PostThreadStrings = .defaults,
    state: ListState = .content,
    onRetry: @escaping () -> Void = {},
    onSelect: @escaping (String) -> Void = { _ in }
  ) {
    self.repostedBy = repostedBy
    self.strings = strings
    self.state = state
    self.onRetry = onRetry
    self.onSelect = onSelect
  }

  public var body: some View {
    ActorListScaffold(
      title: strings.repostedByTitle,
      empty: strings.repostedByEmpty,
      rows: repostedBy.map { profile in
        ActorRow(
          did: profile.did.rawValue,
          handle: profile.handle.rawValue,
          displayName: profile.displayName,
          description: profile.description,
          avatar: profile.avatar?.rawValue)
      },
      state: state,
      strings: strings,
      onRetry: onRetry,
      onSelect: onSelect)
  }
}

/// The quotes list: posts that quote the anchor.
public struct ThreadQuotesScreen: View {
  private let quotes: [PostQuote]
  private let strings: PostThreadStrings
  private let state: ListState
  private let now: Date
  private let locale: Locale
  private let onRetry: () -> Void
  private let onOpen: (RichTextTarget) -> Void

  public init(
    quotes: [PostQuote],
    strings: PostThreadStrings = .defaults,
    state: ListState = .content,
    now: Date = Date(),
    locale: Locale = Locale(identifier: "en_US"),
    onRetry: @escaping () -> Void = {},
    onOpen: @escaping (RichTextTarget) -> Void = { _ in }
  ) {
    self.quotes = quotes
    self.strings = strings
    self.state = state
    self.now = now
    self.locale = locale
    self.onRetry = onRetry
    self.onOpen = onOpen
  }

  public var body: some View {
    PostListScaffold(
      title: strings.quotesTitle,
      empty: strings.quotesEmpty,
      posts: quotes.map(\.post),
      state: state,
      now: now,
      locale: locale,
      strings: strings,
      onRetry: onRetry,
      onOpen: onOpen)
  }
}

// MARK: - Shared list chrome

/// One row of an actor list: avatar, name, handle, and the bio line.
struct ActorRow: View {
  let did: String
  let handle: String
  let displayName: String?
  let description: String?
  let avatar: String?

  @Environment(\.alfTheme) private var theme

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      Avatar(avatar: avatar, handle: handle, displayName: displayName, size: .md)
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(name)
          .font(TypeScale.sm.font(weight: Scales.FontWeight.semiBold))
          .foregroundStyle(theme.atomColors.text)
          .lineLimit(1)
        Text("@\(handle)")
          .font(TypeScale.xs.font())
          .foregroundStyle(theme.atomColors.textContrastMedium)
          .lineLimit(1)
        if let description, !description.isEmpty {
          Text(description)
            .font(TypeScale.sm.font())
            .foregroundStyle(theme.atomColors.textContrastMedium)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("actor-\(did)")
  }

  private var name: String {
    guard let displayName, !displayName.isEmpty else { return handle }
    return displayName
  }
}

/// The chrome an actor list shares: title, state switch, rows.
struct ActorListScaffold: View {
  let title: String
  let empty: String
  let rows: [ActorRow]
  let state: ListState
  let strings: PostThreadStrings
  let onRetry: () -> Void
  let onSelect: (String) -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    ScrollView {
      switch state {
      case .loading:
        ListSkeleton(rowCount: 4)
      case .empty:
        EmptyStateView(icon: "person.2", title: empty, message: "", actionLabel: nil, action: nil)
          .padding(.top, Spacing.xxl)
      case .error(let error):
        ErrorStateView(error: error, retry: onRetry)
          .padding(.top, Spacing.xxl)
      case .content, .loadingMore:
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(rows, id: \.did) { row in
            Button {
              onSelect(row.did)
            } label: {
              row
            }
            .buttonStyle(.plain)
            Divider().foregroundStyle(theme.atomColors.borderContrastLow)
          }
          if case .loadingMore = state {
            LoadMoreSpinner()
          }
        }
      }
    }
    .background(theme.atomColors.bg)
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// The chrome a post list shares.
struct PostListScaffold: View {
  let title: String
  let empty: String
  let posts: [Lexicons.App.Bsky.FeedDefs_PostView]
  let state: ListState
  let now: Date
  let locale: Locale
  let strings: PostThreadStrings
  let onRetry: () -> Void
  let onOpen: (RichTextTarget) -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    ScrollView {
      switch state {
      case .loading:
        ListSkeleton(rowCount: 4)
      case .empty:
        EmptyStateView(icon: "quote.bubble", title: empty, message: "", actionLabel: nil, action: nil)
          .padding(.top, Spacing.xxl)
      case .error(let error):
        ErrorStateView(error: error, retry: onRetry)
          .padding(.top, Spacing.xxl)
      case .content, .loadingMore:
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(posts, id: \.uri.rawValue) { post in
            PostFeedItem(data: postRowData(post), onOpen: onOpen)
              .frame(maxWidth: .infinity, alignment: .leading)
            Divider().foregroundStyle(theme.atomColors.borderContrastLow)
          }
          if case .loadingMore = state {
            LoadMoreSpinner()
          }
        }
      }
    }
    .background(theme.atomColors.bg)
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }

  private func postRowData(_ post: Lexicons.App.Bsky.FeedDefs_PostView) -> FeedItemViewData {
    let counts = FeedItemCounts(
      replyCount: post.replyCount,
      repostCount: post.repostCount,
      likeCount: post.likeCount)
    return feedItemViewData(
      PostModerationAdapter.subject(post),
      counts: counts,
      options: FeedItemRenderOptions(now: now, locale: locale))
  }
}

import Foundation
import Lexicons
import MessagesLogic
import Observation
import QueryStore
import UIComponentsCore

/// The SwiftUI-facing adapter over ``InboxQuery``.
///
/// `InboxQuery` is a `Sendable` value over a `QueryStore` actor, not an
/// `Observable`; this type is the bridge. It owns the list the view renders,
/// drives the first page and pagination, and keeps the `ListState` the screen
/// switches on. Every decision - the direct-convo filter, the page cursor, the
/// unread sum - still belongs to ``InboxQuery``.
@MainActor
@Observable
public final class InboxViewModel {
  /// The conversations, in server order.
  public private(set) var convos: [Chat.Bsky.ConvoDefs_ConvoView] = []
  /// The full-surface list state.
  public private(set) var state: ListState = .loading
  /// True while a next page is in flight.
  public private(set) var isLoadingMore = false
  /// True when a next page is available.
  public private(set) var hasMore = true

  /// The query this adapter reads.
  public let inbox: InboxQuery
  /// The signed-in DID, used to pick the conversation partner out of a row.
  public let currentAccountDid: String?

  private var hasLoaded = false

  /// Creates an adapter over an inbox query.
  ///
  /// - Parameters:
  ///   - inbox: the query to read and page.
  ///   - currentAccountDid: the signed-in DID, or `nil` to render every member.
  public init(inbox: InboxQuery, currentAccountDid: String?) {
    self.inbox = inbox
    self.currentAccountDid = currentAccountDid
  }

  /// Loads the first page if it has not been loaded yet.
  public func loadIfNeeded() async {
    guard !hasLoaded else { return }
    hasLoaded = true
    await load()
  }

  /// Loads the first page, replacing the rendered list.
  public func load() async {
    if convos.isEmpty { state = .loading }
    do {
      let loaded = try await inbox.loadFirstPage()
      convos = loaded
      state = .resolve(itemCount: loaded.count, isInitialLoading: false)
      hasMore = await inbox.paginationState().hasNextPage
    } catch {
      state = .error(
        ListState.ListErrorState(
          title: MessagesCopy.inboxErrorTitle,
          message: MessagesCopy.inboxErrorMessage,
          hasContent: !convos.isEmpty))
    }
  }

  /// Refreshes page one, dropping the rest.
  public func refresh() async {
    do {
      convos = try await inbox.refresh()
      state = .resolve(itemCount: convos.count, isInitialLoading: false)
      hasMore = await inbox.paginationState().hasNextPage
    } catch {
      if convos.isEmpty {
        state = .error(
          ListState.ListErrorState(
            title: MessagesCopy.inboxErrorTitle,
            message: MessagesCopy.inboxErrorMessage))
      }
    }
  }

  /// Appends the next page when one is available.
  public func loadMoreIfNeeded() async {
    guard hasMore, !isLoadingMore, case .content = state else { return }
    isLoadingMore = true
    state = .loadingMore
    defer { isLoadingMore = false }
    do {
      convos = try await inbox.loadMore()
      state = .resolve(itemCount: convos.count, isInitialLoading: false)
      hasMore = await inbox.paginationState().hasNextPage
    } catch {
      state = .error(
        ListState.ListErrorState(
          title: MessagesCopy.inboxErrorTitle,
          message: MessagesCopy.inboxErrorMessage,
          hasContent: true))
    }
  }

  /// Re-reads the list from the store without a request.
  ///
  /// Used after a log batch has been applied through ``InboxReducer``: the
  /// reducer writes the cache, and this republishes it.
  public func reloadFromCache() async {
    let cached = await inbox.convos()
    if !cached.isEmpty || convos.isEmpty {
      convos = cached
      state = .resolve(itemCount: cached.count, isInitialLoading: false)
      hasMore = await inbox.paginationState().hasNextPage
    }
  }
}

/// The value a conversation row renders.
///
/// Projected from a `ConvoView` so the row view holds no unwrapping logic and a
/// preview can build one directly. The 1:1 scope reads the single non-self
/// member; group rows are not rendered (the inbox query drops them).
public struct InboxRow: Sendable, Identifiable, Equatable {
  /// The conversation id.
  public let id: String
  /// The other member's display name, resolved the way the RN row does.
  public let name: String
  /// The other member's handle.
  public let handle: String
  /// The other member's avatar URL, if any.
  public let avatarURL: String?
  /// The last-message preview line.
  public let preview: String
  /// The unread count.
  public let unreadCount: Int
  /// Whether the conversation is muted.
  public let muted: Bool
  /// The last message's timestamp, for the relative time in the row.
  public let timestamp: Date?

  /// Projects a convo view into a row.
  ///
  /// - Parameters:
  ///   - convo: the conversation.
  ///   - currentAccountDid: the signed-in DID, so the partner is the other
  ///     member. When it is `nil` or matches nobody, the first member is used.
  public static func make(
    _ convo: Chat.Bsky.ConvoDefs_ConvoView, currentAccountDid: String?
  ) -> InboxRow {
    let partner =
      convo.members.first { $0.did.rawValue != currentAccountDid }
        ?? convo.members.first
    let name = partner?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let handle = partner?.handle.rawValue ?? ""
    return InboxRow(
      id: convo.id,
      name: (name?.isEmpty == false ? name! : handle).isEmpty
        ? MessagesCopy.conversationFallbackTitle : (name?.isEmpty == false ? name! : handle),
      handle: handle,
      avatarURL: partner?.avatar?.rawValue,
      preview: preview(convo.lastMessage, currentAccountDid: currentAccountDid),
      unreadCount: convo.unreadCount,
      muted: convo.muted,
      timestamp: timestamp(convo.lastMessage))
  }

  /// The preview line for a last-message union.
  private static func preview(
    _ lastMessage: Chat.Bsky.ConvoDefs_ConvoView_LastMessage?, currentAccountDid: String?
  ) -> String {
    switch lastMessage {
    case .convoDefsMessageView(let view):
      let prefix = view.sender.did.rawValue == currentAccountDid ? "You: " : ""
      let text = view.text.trimmingCharacters(in: .whitespacesAndNewlines)
      return text.isEmpty ? MessagesCopy.noMessagesYet : prefix + text
    case .convoDefsDeletedMessageView:
      return MessagesCopy.deletedMessage
    case .convoDefsSystemMessageView, ._other, nil:
      return MessagesCopy.noMessagesYet
    }
  }

  /// The timestamp a last-message union carries, when it has one.
  private static func timestamp(
    _ lastMessage: Chat.Bsky.ConvoDefs_ConvoView_LastMessage?
  ) -> Date? {
    switch lastMessage {
    case .convoDefsMessageView(let view): MessagesDate.date(from: view.sentAt.rawValue)
    case .convoDefsDeletedMessageView(let view): MessagesDate.date(from: view.sentAt.rawValue)
    case .convoDefsSystemMessageView, ._other, nil: nil
    }
  }
}

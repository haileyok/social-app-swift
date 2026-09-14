import Foundation
import Lexicons
import QueryStore

/// The inbox: a paged, rev-ordered list of conversations.
///
/// Port of `useListConvosQuery` in
/// `src/state/queries/messages/list-conversations.tsx`: an infinite query keyed
/// by `status`/`readState`/`kind`/`limit` whose `getNextPageParam` is the page
/// cursor.
///
/// ## Group convos
///
/// The server may return group convos in a `direct`-filtered or unfiltered page.
/// This is the 1:1 scope, so every page is filtered to direct convos inside the
/// page fetcher: group data never enters the store, and nothing downstream has
/// to re-check. The wire shape decodes fine either way.
public struct InboxQuery: Sendable {
  /// The store this inbox lives in.
  public let store: QueryStore
  /// The chat transport.
  public let client: any ChatXrpc
  /// This inbox's key.
  public let key: QueryKey
  /// Page size.
  public let limit: Int

  private let status: ConvoStatusFilter?
  private let readState: ConvoReadStateFilter?
  private let kind: ConvoKindFilter?

  /// Creates an inbox query.
  ///
  /// - Parameters:
  ///   - store: the store to read and write.
  ///   - client: the chat transport.
  ///   - status: `request` / `accepted` filter, or `nil` for both.
  ///   - readState: `unread` filter, or `nil`.
  ///   - kind: `direct` / `group` filter, or `nil`.
  ///   - limit: page size.
  ///   - scope: account scope (the signed-in DID).
  public init(
    store: QueryStore, client: any ChatXrpc,
    status: ConvoStatusFilter? = nil, readState: ConvoReadStateFilter? = nil,
    kind: ConvoKindFilter? = nil, limit: Int = MessagesConstants.inboxLimit,
    scope: String? = nil
  ) {
    self.store = store
    self.client = client
    self.status = status
    self.readState = readState
    self.kind = kind
    self.limit = limit
    self.key = MessagesKeys.convoList(
      status: status, readState: readState, kind: kind, limit: limit, scope: scope)
  }

  /// The infinite query over the store. Cheap to build; built on demand.
  private var query: InfiniteQuery<Chat.Bsky.ConvoDefs_ConvoView> {
    let client = client
    let status = status
    let readState = readState
    let kind = kind
    let limit = limit
    return InfiniteQuery(
      store: store,
      key: key,
      // Convos are identified by convoId: a convo arriving in two pages collapses.
      identity: { $0.id },
      page: { cursor in
        let page = try await client.listConvos(
          status: status, readState: readState, kind: kind, limit: limit, cursor: cursor)
        return QueryPage(
          items: page.convos.filter(Self.isDirectConvo), cursor: page.cursor)
      })
  }

  /// True for a convo the 1:1 scope keeps: a direct convo, or one whose `kind`
  /// is absent (older services) or unrecognized.
  ///
  /// A `groupConvo` is dropped. An unknown kind is *kept*, because "not known to
  /// be a group" is the safe reading for a 1:1 client: the convo has two members
  /// or it does not, and the member list is what the UI reads.
  public static func isDirectConvo(_ convo: Chat.Bsky.ConvoDefs_ConvoView) -> Bool {
    switch convo.kind {
    case .convoDefsGroupConvo: false
    case .convoDefsDirectConvo, ._other, nil: true
    }
  }

  // MARK: - Reading

  /// The held data.
  public func data() async -> InfiniteQueryData<Chat.Bsky.ConvoDefs_ConvoView> {
    await query.data()
  }

  /// The typed entry, for status/error rendering.
  public func entry() async -> QueryEntry<InfiniteQueryData<Chat.Bsky.ConvoDefs_ConvoView>> {
    await query.entry()
  }

  /// Every convo across every page, in order.
  public func convos() async -> [Chat.Bsky.ConvoDefs_ConvoView] {
    await data().items
  }

  /// The number of unread convos held, summed across pages.
  public func unreadCount() async -> Int {
    await convos().reduce(0) { $0 + $1.unreadCount }
  }

  /// Pagination state.
  public func paginationState() async -> PaginationState {
    await store.paginationState(for: key)
  }

  // MARK: - Fetching

  /// Loads the first page, replacing whatever was held.
  @discardableResult
  public func loadFirstPage(force: Bool = false) async throws -> [Chat.Bsky.ConvoDefs_ConvoView] {
    _ = try await query.loadFirstPage(force: force)
    return await convos()
  }

  /// Appends the next page, returning the whole merged list.
  @discardableResult
  public func loadMore() async throws -> [Chat.Bsky.ConvoDefs_ConvoView] {
    _ = try await query.loadMore()
    return await convos()
  }

  /// Refetches page one and drops the rest.
  @discardableResult
  public func refresh() async throws -> [Chat.Bsky.ConvoDefs_ConvoView] {
    _ = try await query.refresh()
    return await convos()
  }

  // MARK: - Observation

  /// Registers a closure invoked with the convo list whenever it changes.
  @discardableResult
  public func subscribe(
    onChange: @escaping @Sendable ([Chat.Bsky.ConvoDefs_ConvoView]) -> Void
  ) async -> QuerySubscription {
    await query.subscribeItems(onChange: onChange)
  }
}

/// The unread badge counts.
///
/// Port of `useUnreadCountsQuery` in `get-unread-counts.ts`: a plain query with
/// a 15-second stale time, whose counts are sentinel-capped at 100 (see
/// ``UnreadCounts/cap``).
public struct UnreadCountsQuery: Sendable {
  /// The store this query lives in.
  public let store: QueryStore
  /// The chat transport.
  public let client: any ChatXrpc
  /// This query's key.
  public let key: QueryKey
  /// Whether group convos are included in the server's counts.
  public let includeGroupChats: Bool

  public init(
    store: QueryStore, client: any ChatXrpc,
    includeGroupChats: Bool = true, scope: String? = nil
  ) {
    self.store = store
    self.client = client
    self.includeGroupChats = includeGroupChats
    self.key = MessagesKeys.unreadCounts(
      includeGroupChats: includeGroupChats, scope: scope)
  }

  /// The held counts, or zeros.
  public func data() async -> UnreadCounts {
    (try? await store.payload(key, as: UnreadCounts.self))
      ?? UnreadCounts(
        unreadAcceptedConvos: 0, unreadRequestConvos: 0)
  }

  /// Fetches the counts when stale.
  @discardableResult
  public func load(force: Bool = false) async throws -> UnreadCounts {
    let client = client
    let includeGroupChats = includeGroupChats
    return try await store.fetch(
      key, staleTime: MessagesConstants.unreadCountsStale, force: force
    ) {
      try await client.getUnreadCounts(includeGroupChats: includeGroupChats)
    }
  }

  /// Marks the entry stale and refetches. Port of the `invalidateQueries` the
  /// RN log handler runs on every batch.
  @discardableResult
  public func invalidate() async -> UnreadCounts {
    _ = await store.invalidate(key)
    return await data()
  }
}

/// A single conversation view.
///
/// Port of `useConvoQuery` in `conversation.ts`: an infinite-stale query whose
/// value is refreshed by log events and explicit invalidation rather than by
/// time.
public struct ConvoQuery: Sendable {
  /// The store this query lives in.
  public let store: QueryStore
  /// The chat transport.
  public let client: any ChatXrpc
  /// The conversation id.
  public let convoId: String
  /// This query's key.
  public let key: QueryKey

  public init(
    store: QueryStore, client: any ChatXrpc, convoId: String, scope: String? = nil
  ) {
    self.store = store
    self.client = client
    self.convoId = convoId
    self.key = MessagesKeys.convo(convoId, scope: scope)
  }

  /// The held convo, if any.
  public func data() async -> Chat.Bsky.ConvoDefs_ConvoView? {
    try? await store.payload(key, as: Chat.Bsky.ConvoDefs_ConvoView.self)
  }

  /// Fetches the convo when stale.
  @discardableResult
  public func load(force: Bool = false) async throws -> Chat.Bsky.ConvoDefs_ConvoView {
    let client = client
    let convoId = convoId
    return try await store.fetch(
      key, staleTime: STALE.INFINITY, force: force
    ) {
      try await client.getConvo(convoId: convoId)
    }
  }

  /// Writes a convo into the cache without a request. Port of `precacheConvoQuery`.
  public func precache(_ convo: Chat.Bsky.ConvoDefs_ConvoView) async {
    await store.setQueryData(convo, for: key)
  }
}

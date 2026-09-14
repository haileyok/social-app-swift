import Foundation
import Lexicons
import QueryStore

/// One pack view's query, plus the actor and search list queries.
///
/// Ports `useStarterPackQuery`, `useActorStarterPacksQuery`,
/// `useActorStarterPacksWithMembershipsQuery` and `useStarterPackSearch`.
public struct StarterPackQuery: Sendable {
  /// The store this query lives in.
  public let store: QueryStore
  /// The XRPC surface to read through.
  public let xrpc: any StarterPackXrpc
  /// This query's key.
  public let key: QueryKey
  /// The record the read resolves.
  public let target: Target

  /// What a pack read is addressed by.
  public enum Target: Sendable, Equatable {
    /// An `at://` or `https://` URI.
    case uri(String)
    /// A DID (or handle) plus a record key.
    case didAndRkey(did: String, rkey: String)

    /// The `at://` URI this target resolves to, when it can be derived.
    public var atURI: String? {
      switch self {
      case .uri(let uri):
        return StarterPackURI.httpToAtURI(uri)
      case .didAndRkey(let did, let rkey):
        return StarterPackURI.makeURI(did: did, rkey: rkey)
      }
    }
  }

  /// Creates a pack query.
  ///
  /// - Parameters:
  ///   - store: the store to read and write.
  ///   - xrpc: the read surface.
  ///   - target: what the read resolves.
  ///   - scope: account scope (the signed-in DID), or nil for logged out.
  public init(
    store: QueryStore, xrpc: any StarterPackXrpc, target: Target, scope: String? = nil
  ) {
    self.store = store
    self.xrpc = xrpc
    self.target = target
    switch target {
    case .uri(let uri):
      self.key = StarterPackKeys.pack(uri: uri, scope: scope)
    case .didAndRkey(let did, let rkey):
      self.key = StarterPackKeys.pack(name: did, rkey: rkey, scope: scope)
    }
  }

  /// Reads the pack view into the store.
  ///
  /// The read is enabled only when the target resolves to an `at://` URI, which
  /// is RN's `enabled: Boolean(uri) || Boolean(did && rkey)`.
  @discardableResult
  public func load(force: Bool = false) async throws -> App.Bsky.GraphDefs_StarterPackView? {
    guard let atURI = target.atURI else { return nil }
    let xrpc = self.xrpc
    return try await store.fetch(
      key, staleTime: StarterPackStale.packView, force: force, persist: true
    ) {
      try await xrpc.getStarterPack(uri: atURI)
    }
  }

  /// The held view, without fetching.
  public func data() async -> App.Bsky.GraphDefs_StarterPackView? {
    try? await store.payload(key, as: App.Bsky.GraphDefs_StarterPackView.self)
  }

  /// The presentation detail for the held view, when there is one.
  public func detail(viewerDID: String? = nil) async -> StarterPackDetail? {
    guard let view = await data() else { return nil }
    return StarterPackViewBuilder.detail(view, viewerDID: viewerDID)
  }

  /// The typed entry, for status rendering.
  public func entry() async -> QueryEntry<App.Bsky.GraphDefs_StarterPackView> {
    await store.entry(key, as: App.Bsky.GraphDefs_StarterPackView.self)
  }

  /// Writes a view into the cache without a request (`precacheStarterPack`).
  public func precache(_ view: App.Bsky.GraphDefs_StarterPackView) async {
    await store.setQueryData(view, for: key, persist: true)
  }

  /// Removes this query from the store.
  public func remove() async {
    await store.remove(key)
  }
}

/// A user's starter packs, paged.
///
/// Port of `useActorStarterPacksQuery`, which pages
/// `app.bsky.graph.getActorStarterPacks` at `limit: 10`.
public struct ActorStarterPacksQuery: Sendable {
  /// The store this query lives in.
  public let store: QueryStore
  /// The XRPC surface to read through.
  public let xrpc: any StarterPackXrpc
  /// The actor's DID.
  public let actor: String
  /// This query's key.
  public let key: QueryKey
  /// Items per page.
  public let limit: Int
  /// The cursors this walk has already requested.
  private let walk: CursorWalkGuard

  /// Creates the query.
  public init(
    store: QueryStore, xrpc: any StarterPackXrpc, actor: String, scope: String? = nil,
    limit: Int = StarterPackConstants.actorStarterPacksPageSize
  ) {
    self.store = store
    self.xrpc = xrpc
    self.actor = actor
    self.key = StarterPackKeys.actorStarterPacks(actor: actor, scope: scope)
    self.limit = limit
    self.walk = CursorWalkGuard()
  }

  private var query: InfiniteQuery<App.Bsky.GraphDefs_StarterPackViewBasic> {
    let xrpc = self.xrpc
    let actor = self.actor
    let limit = self.limit
    return InfiniteQuery(
      store: store,
      key: key,
      identity: { $0.uri.rawValue },
      page: { cursor in
        let page = try await xrpc.getActorStarterPacks(actor: actor, cursor: cursor, limit: limit)
        return QueryPage(items: page.starterPacks, cursor: page.cursor)
      })
  }

  /// Every pack across every loaded page.
  public func items() async -> [App.Bsky.GraphDefs_StarterPackViewBasic] {
    await query.items()
  }

  /// Loads the first page.
  @discardableResult
  public func loadFirstPage(force: Bool = false) async throws
    -> [App.Bsky.GraphDefs_StarterPackViewBasic] {
    walk.reset()
    _ = try await query.loadFirstPage(staleTime: StarterPackStale.actorStarterPacks, force: force)
    return await query.items()
  }

  /// Appends the next page, for the reason documented on ``CursorWalkGuard``.
  @discardableResult
  public func loadMore() async throws -> [App.Bsky.GraphDefs_StarterPackViewBasic] {
    let state = await query.paginationState()
    guard let cursor = state.nextCursor, walk.admit(cursor) else { return await query.items() }
    _ = try await query.fetchPage(at: cursor)
    return await query.items()
  }

  /// Pagination state.
  public func paginationState() async -> PaginationState {
    await query.paginationState()
  }
}

/// A user's packs with the viewer's membership, paged.
///
/// Port of `useActorStarterPacksWithMembershipsQuery`. Each row carries the list
/// item that makes the actor a member of the pack, which is what the profile
/// dialog's add/remove control reads.
public struct ActorStarterPacksWithMembershipQuery: Sendable {
  /// The store this query lives in.
  public let store: QueryStore
  /// The XRPC surface to read through.
  public let xrpc: any StarterPackXrpc
  /// The actor's DID.
  public let actor: String
  /// This query's key.
  public let key: QueryKey
  /// Items per page.
  public let limit: Int
  /// The cursors this walk has already requested.
  private let walk: CursorWalkGuard

  /// Creates the query.
  public init(
    store: QueryStore, xrpc: any StarterPackXrpc, actor: String, scope: String? = nil,
    limit: Int = StarterPackConstants.actorStarterPacksPageSize
  ) {
    self.store = store
    self.xrpc = xrpc
    self.actor = actor
    self.key = StarterPackKeys.actorStarterPacksWithMembership(actor: actor, scope: scope)
    self.limit = limit
    self.walk = CursorWalkGuard()
  }

  /// The row type, named so callers do not spell out the nested generic.
  public typealias Row =
    App.Bsky.GraphGetStarterPacksWithMembership_StarterPackWithMembership

  private var query: InfiniteQuery<Row> {
    let xrpc = self.xrpc
    let actor = self.actor
    let limit = self.limit
    return InfiniteQuery(
      store: store,
      key: key,
      identity: { $0.starterPack.uri.rawValue },
      page: { cursor in
        let page = try await xrpc.getStarterPacksWithMembership(
          actor: actor, cursor: cursor, limit: limit)
        return QueryPage(items: page.packs, cursor: page.cursor)
      })
  }

  /// Every row across every loaded page.
  public func items() async -> [Row] { await query.items() }

  /// Loads the first page.
  @discardableResult
  public func loadFirstPage(force: Bool = false) async throws -> [Row] {
    walk.reset()
    _ = try await query.loadFirstPage(staleTime: StarterPackStale.actorStarterPacks, force: force)
    return await query.items()
  }

  /// Appends the next page, for the reason documented on ``CursorWalkGuard``.
  @discardableResult
  public func loadMore() async throws -> [Row] {
    let state = await query.paginationState()
    guard let cursor = state.nextCursor, walk.admit(cursor) else { return await query.items() }
    _ = try await query.fetchPage(at: cursor)
    return await query.items()
  }

  /// Pagination state.
  public func paginationState() async -> PaginationState {
    await query.paginationState()
  }

  /// The packs the actor is already in.
  ///
  /// Port of the `isInPack` check in `StarterPackDialog`'s item renderer: a row
  /// with a `listItem` means the actor is a member.
  public static func membershipPacks(_ rows: [Row]) -> [String] {
    rows.filter { $0.listItem != nil }.map { $0.starterPack.uri.rawValue }
  }

  /// Whether the actor is a member of the pack at `uri`.
  public static func isMember(_ rows: [Row], packURI: String) -> Bool {
    rows.first { $0.starterPack.uri.rawValue == packURI }?.listItem != nil
  }
}

/// Pack search, paged.
///
/// Port of `useStarterPackSearch`: `searchStarterPacksV2` with the results
/// de-duplicated across pages by URI. The dedupe is applied here rather than in
/// a `select`, because QueryStore has no `select`; it runs inside the page
/// fetcher with the seen-set in scope of the whole query.
public struct StarterPackSearchQuery: Sendable {
  /// The store this query lives in.
  public let store: QueryStore
  /// The XRPC surface to read through.
  public let xrpc: any StarterPackXrpc
  /// The search query.
  public let query: String
  /// This query's key.
  public let key: QueryKey
  /// Items per page.
  public let limit: Int
  /// Cross-page de-duplication state, one set per query.
  private let seen: SeenURISet
  /// The cursors this walk has already requested.
  private let walk: CursorWalkGuard

  /// Creates the query.
  public init(
    store: QueryStore, xrpc: any StarterPackXrpc, query: String, scope: String? = nil,
    limit: Int = StarterPackConstants.searchPageSize
  ) {
    self.store = store
    self.xrpc = xrpc
    self.query = query
    self.key = StarterPackKeys.search(query: query, limit: limit, scope: scope)
    self.limit = limit
    self.seen = SeenURISet()
    self.walk = CursorWalkGuard()
  }

  private var infinite: InfiniteQuery<App.Bsky.GraphDefs_StarterPackView> {
    let xrpc = self.xrpc
    let query = self.query
    let limit = self.limit
    let seen = self.seen
    return InfiniteQuery(
      store: store,
      key: key,
      identity: { $0.uri.rawValue },
      page: { cursor in
        let page = try await xrpc.searchStarterPacks(query: query, cursor: cursor, limit: limit)
        let unique = page.starterPacks.filter { seen.insert($0.uri.rawValue) }
        return QueryPage(items: unique, cursor: page.cursor)
      })
  }

  /// Every result across every loaded page, de-duplicated.
  public func items() async -> [App.Bsky.GraphDefs_StarterPackView] {
    await infinite.items()
  }

  /// Loads the first page, resetting the seen set the way a fresh search does.
  @discardableResult
  public func loadFirstPage(force: Bool = false) async throws
    -> [App.Bsky.GraphDefs_StarterPackView] {
    seen.reset()
    walk.reset()
    _ = try await infinite.loadFirstPage(staleTime: StarterPackStale.search, force: force)
    return await infinite.items()
  }

  /// Appends the next page, for the reason documented on ``CursorWalkGuard``.
  @discardableResult
  public func loadMore() async throws -> [App.Bsky.GraphDefs_StarterPackView] {
    let state = await infinite.paginationState()
    guard let cursor = state.nextCursor, walk.admit(cursor) else { return await infinite.items() }
    _ = try await infinite.fetchPage(at: cursor)
    return await infinite.items()
  }

  /// Pagination state.
  public func paginationState() async -> PaginationState {
    await infinite.paginationState()
  }
}

/// A set of URIs behind a lock, for cross-page de-duplication.
///
/// ``StarterPackSearchQuery`` is a `Sendable` value whose page fetcher runs
/// concurrently, so the seen set is confined rather than shared bare.
final class SeenURISet: @unchecked Sendable {
  private let lock = NSLock()
  private var seen: Set<String> = []

  /// Records `uri`, returning true when it was not already present.
  func insert(_ uri: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return seen.insert(uri).inserted
  }

  /// Clears the set.
  func reset() {
    lock.lock()
    defer { lock.unlock() }
    seen.removeAll()
  }
}

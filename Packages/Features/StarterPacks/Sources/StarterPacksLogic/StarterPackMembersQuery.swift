import Foundation
import Lexicons
import QueryStore

/// A pack's member list, as a paged and an exhaustive read.
///
/// Port of `src/state/queries/list-members.ts`: `useListMembersQuery` (a paged
/// `useInfiniteQuery`) and `useAllListMembersQuery` (which walks
/// `getAllListMembers` to exhaustion).
///
/// The paged read is an ``InfiniteQuery`` over ``StarterPackKeys/listMembers(uri:scope:)``;
/// the exhaustive read is a plain function because RN caches its result as a
/// single value, not as pages.
public struct StarterPackMembersQuery: Sendable {
  /// The store this query lives in.
  public let store: QueryStore
  /// The XRPC surface to read through.
  public let xrpc: any StarterPackXrpc
  /// The list URI.
  public let listURI: String
  /// This query's key.
  public let key: QueryKey
  /// Items per page for the paged read.
  public let limit: Int
  /// The cursors this walk has already requested.
  private let walk: CursorWalkGuard

  /// Creates a members query.
  ///
  /// - Parameters:
  ///   - store: the store to read and write.
  ///   - xrpc: the read surface.
  ///   - listURI: the backing list's URI.
  ///   - scope: account scope (the signed-in DID), or nil for logged out.
  ///   - limit: items per page.
  public init(
    store: QueryStore,
    xrpc: any StarterPackXrpc,
    listURI: String,
    scope: String? = nil,
    limit: Int = StarterPackConstants.listMembersPageSize
  ) {
    self.store = store
    self.xrpc = xrpc
    self.listURI = listURI
    self.key = StarterPackKeys.listMembers(uri: listURI, scope: scope)
    self.limit = limit
    self.walk = CursorWalkGuard()
  }

  /// The infinite query over the store. Cheap to build; built on demand.
  private var query: InfiniteQuery<App.Bsky.GraphDefs_ListItemView> {
    let xrpc = self.xrpc
    let listURI = self.listURI
    let limit = self.limit
    return InfiniteQuery(
      store: store,
      key: key,
      // Items are identified by their membership URI, which is what
      // `useListMembersQuery`'s consumers key on.
      identity: { $0.uri.rawValue },
      page: { cursor in
        let page = try await xrpc.getList(list: listURI, cursor: cursor, limit: limit)
        return QueryPage(items: page.items, cursor: page.cursor)
      })
  }

  /// Every member across every loaded page.
  public func items() async -> [App.Bsky.GraphDefs_ListItemView] {
    await query.items()
  }

  /// The paged entry, for status rendering.
  public func entry() async -> QueryEntry<InfiniteQueryData<App.Bsky.GraphDefs_ListItemView>> {
    await query.entry()
  }

  /// Pagination state for this list.
  public func paginationState() async -> PaginationState {
    await query.paginationState()
  }

  /// Loads the first page, replacing whatever was held.
  @discardableResult
  public func loadFirstPage(force: Bool = false) async throws
    -> [App.Bsky.GraphDefs_ListItemView] {
    walk.reset()
    _ = try await query.loadFirstPage(staleTime: StarterPackStale.listMembers, force: force)
    return await query.items()
  }

  /// Appends the next page, returning the whole merged list.
  ///
  /// Walks via ``InfiniteQuery/fetchPage(at:isAppending:)`` with an explicit
  /// cursor guard, for the reason documented on ``CursorWalkGuard``.
  @discardableResult
  public func loadMore() async throws -> [App.Bsky.GraphDefs_ListItemView] {
    let state = await query.paginationState()
    guard let cursor = state.nextCursor, walk.admit(cursor) else { return await query.items() }
    _ = try await query.fetchPage(at: cursor)
    return await query.items()
  }

  /// Removes this query from the store.
  public func remove() async {
    await query.remove()
  }

  // MARK: - Exhaustive read

  /// Walks the list to exhaustion, capped the way RN caps it.
  ///
  /// Port of `getAllListMembers`: pages of 50, at most six pages. The cap is
  /// RN's own safety valve ("just for anything weird happening with the api"),
  /// so it is preserved rather than replaced with an unbounded walk.
  ///
  /// - Returns: every item the walk collected, in wire order.
  public static func allMembers(
    xrpc: any StarterPackXrpc,
    listURI: String,
    pageSize: Int = StarterPackConstants.listMembersAllPageSize,
    pageCap: Int = StarterPackConstants.listMembersAllPageCap
  ) async throws -> [App.Bsky.GraphDefs_ListItemView] {
    var items: [App.Bsky.GraphDefs_ListItemView] = []
    var cursor: String?
    var page = 0
    while page < pageCap {
      let result = try await xrpc.getList(list: listURI, cursor: cursor, limit: pageSize)
      items.append(contentsOf: result.items)
      guard let next = result.cursor else { break }
      cursor = next
      page += 1
    }
    return items
  }

  /// The DIDs a "follow all" would target, in list order.
  ///
  /// Port of the `onFollowAll` filter in `StarterPackScreen`:
  ///
  /// ```ts
  /// li.subject.did !== currentAccount?.did
  ///   && !isBlockedOrBlocking(li.subject)
  ///   && !isMuted(li.subject)
  ///   && !li.subject.viewer?.following
  /// ```
  ///
  /// Blocked/blocking and muted are read straight off the viewer state, which is
  /// all `lib/moderation/blocked-and-muted.ts` does.
  public static func followAllTargets(
    items: [App.Bsky.GraphDefs_ListItemView], viewerDID: String?
  ) -> [String] {
    items.filter { item in
      let profile = item.subject
      if let viewerDID, profile.did.rawValue == viewerDID { return false }
      if profile.viewer?.blockedBy == true { return false }
      if profile.viewer?.blocking != nil { return false }
      if profile.viewer?.blockingByList != nil { return false }
      if profile.viewer?.muted == true { return false }
      if profile.viewer?.mutedByList != nil { return false }
      if profile.viewer?.following != nil { return false }
      return true
    }.map { $0.subject.did.rawValue }
  }
}

/// The members of a pack, split into the shapes the wizard needs.
///
/// Port of the split in `screens/StarterPack/Wizard/index.tsx`: the edit wizard
/// seeds its people list from the list items, and the "opted out" set drives the
/// badge on each row.
public enum StarterPackMemberSelection {
  /// The members a wizard seeds from, excluding anyone who opted out.
  ///
  /// Port of `listItems?.filter(i => !i.subjectOptedOut).map(i => i.subject)`.
  public static func seedableMembers(
    _ items: [App.Bsky.GraphDefs_ListItemView]
  ) -> [App.Bsky.ActorDefs_ProfileView] {
    items.filter { $0.subjectOptedOut != true }.map(\.subject)
  }

  /// The DIDs of members who opted out of the reference list, which the wizard
  /// marks with a badge.
  ///
  /// Port of `new Set(currentListItems?.filter(item => item.subjectOptedOut)
  /// .map(item => item.subject.did))`.
  public static func optedOutDIDs(_ items: [App.Bsky.GraphDefs_ListItemView]) -> Set<String> {
    Set(items.filter { $0.subjectOptedOut == true }.map { $0.subject.did.rawValue })
  }
}

import Foundation
import Lexicons
import Preferences
import QueryStore
import SwiftAtproto

/// Resolves the pinned feeds: reads saved-feeds v2, batches generator views
/// through `getFeedGenerators`, resolves lists individually, and preserves
/// stored pin order.
///
/// Port of `usePinnedFeedsInfos` in `src/state/queries/feed.ts`. The XRPC
/// sequence is what the RN code does:
///
/// ```
/// logged out                      -> [Discover stub]
/// pinned generator feeds present  -> getFeedGenerators(feeds: [...])
/// pinned lists present            -> getList(list:) per list
/// ```
///
/// Behavioural notes carried over from RN:
/// - A failing `getFeedGenerators` fails the whole query.
/// - A failing individual list read is ignored (`allSettled`).
/// - Order follows the stored saved-feed order, not the wire order.
/// - An entry whose view did not resolve is dropped, except the timeline, which
///   needs no resolution.
public struct PinnedFeedsResolver: Sendable {
  public let store: QueryStore
  public let xrpc: any FeedXrpc
  /// Account scope for the key, or `nil` when logged out.
  public let scope: String?
  /// Whether a session is active. RN short-circuits to the Discover stub when
  /// there is none.
  public let isAuthenticated: Bool

  public init(
    store: QueryStore,
    xrpc: any FeedXrpc,
    scope: String? = nil,
    isAuthenticated: Bool = true
  ) {
    self.store = store
    self.xrpc = xrpc
    self.scope = scope
    self.isAuthenticated = isAuthenticated
  }

  /// The Discover stub RN returns for a logged-out reader.
  public static let discoverStub = PinnedFeed(
    config: SavedFeedEntry(
      id: "pwi-discover", type: .feed, value: FeedURIs.discover, pinned: true),
    displayName: "Discover")

  /// The query key for the pinned list, derived from the saved values.
  public static func key(savedItems: [SavedFeedEntry], scope: String? = nil) -> QueryKey {
    HomeFeedKeys.feedInfo(
      kind: .pinned, feedUris: savedItems.map(\.value), scope: scope)
  }

  /// Resolves the pinned feeds, reading through the store so a fresh entry is
  /// not refetched (`STALE.MINUTES.FIFTEEN`).
  @discardableResult
  public func resolve(savedItems: [SavedFeedEntry]) async throws -> [PinnedFeed] {
    let key = Self.key(savedItems: savedItems, scope: scope)
    let payload: ResolvedFeedInfo = try await store.fetch(
      key,
      staleTime: HomeFeedStale.pinnedFeeds,
      persist: true
    ) { [self] in
      ResolvedFeedInfo(from: try await resolveUncached(savedItems: savedItems))
    }
    return payload.feeds.map(\.pinnedFeed)
  }

  /// Performs the resolution without touching the store, so tests can assert
  /// the exact request sequence.
  func resolveUncached(savedItems: [SavedFeedEntry]) async throws -> [PinnedFeed] {
    guard isAuthenticated else { return [Self.discoverStub] }

    let pinnedItems = savedItems.filter(\.pinned)
    let pinnedFeeds = pinnedItems.filter { $0.type == .feed }
    let pinnedLists = pinnedItems.filter { $0.type == .list }

    var resolved: [String: PinnedFeed] = [:]
    if !pinnedFeeds.isEmpty {
      // Fail the whole query when the batch read fails (RN awaits it directly).
      let views = try await xrpc.getFeedGenerators(feeds: pinnedFeeds.map(\.value))
      for view in views {
        guard let config = pinnedFeeds.first(where: { $0.value == view.uri.rawValue })
        else { continue }
        resolved[view.uri.rawValue] = PinnedFeed.generator(view, config: config)
      }
    }

    // Lists are resolved individually and failures are ignored.
    for list in pinnedLists {
      guard let view = try? await xrpc.getList(list: list.value) else { continue }
      resolved[list.value] = PinnedFeed(
        config: list,
        displayName: view.name,
        avatar: nil,
        creatorHandle: view.creatorHandle,
        creatorDid: view.creatorDid)
    }

    // Order by stored pin order; the timeline needs no resolution.
    return pinnedItems.compactMap { item in
      if let feed = resolved[item.value] { return feed }
      if item.type == .timeline { return PinnedFeed.timeline(item) }
      return nil
    }
  }
}

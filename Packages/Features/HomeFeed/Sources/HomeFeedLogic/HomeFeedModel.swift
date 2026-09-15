import ATProtoClient
import Domain
import Foundation
import Lexicons
import Preferences
import QueryStore

/// The high-level state a Home screen needs, derived from pinned feeds and a
/// selected descriptor.
///
/// Port of the `hasSession` / `pinnedFeedInfos.length` branching in
/// `src/view/screens/Home.tsx` plus the per-feed `isEmpty` / `isError` render
/// selection in `src/view/com/posts/PostFeed.tsx`.
public enum HomeFeedPresentation: Sendable, Equatable {
  /// No session: RN renders the logged-out pager (Discover only).
  case loggedOut
  /// A session, but every saved feed is unpinned: RN renders `NoFeedsPinned`,
  /// with "Add recommended feeds" and "Browse other feeds" actions.
  case noFeedsPinned
  /// The saved feeds are still loading (or preferences have not hydrated).
  case loading
  /// There is at least one pinned feed; render it.
  case feeds

  /// True when the caller should offer the "add your first feed" affordance.
  public var showsAddFeeds: Bool { self == .noFeedsPinned }
}

/// Error classification for a feed page, mirroring `PostFeedErrorMessage`'s
/// `KnownError` branches plus the network case.
public enum HomeFeedError: Sendable, Equatable {
  /// A connectivity failure. RN: `isNetworkError`.
  case network
  /// The appview rejected the read (feedgen offline, misconfigured, rate
  /// limited). RN: any XRPC error.
  case service(message: String?)
  /// A logged-out reader received only content that fails moderation.
  /// RN: `KnownError.FeedSignedInOnly`.
  case signedInOnly
  /// Anything else.
  case unknown(message: String?)

  /// Classifies a thrown error for the UI.
  ///
  /// Uses the ported RN `isNetworkError` classifier in ``Domain/ErrorStrings``,
  /// which is what `PostFeed.tsx` uses to decide between the offline branch and
  /// the feed-error branch.
  ///
  /// `ATProtoClient.XrpcError` is not `CustomStringConvertible`, so the
  /// classifier - which stringifies its input - cannot read an XRPC error's
  /// message directly. The message and raw code are therefore rendered into the
  /// same text shape RN's `String(e)` produces (`"[code] message"`) before
  /// classifying, so network and service failures separate correctly.
  public static func classify(_ error: any Error) -> HomeFeedError {
    if let xrpc = error as? XrpcError {
      let text = [xrpc.rawCode, xrpc.message].compactMap { $0 }.joined(separator: " ")
      if ErrorStrings.isNetworkError(text) { return .network }
      return .service(message: xrpc.message ?? xrpc.rawCode)
    }
    if ErrorStrings.isNetworkError(error) { return .network }
    return .unknown(message: String(describing: error))
  }
}

/// The lifecycle of one feed page, the render decision `PostFeed.tsx` makes.
public enum FeedPageState: Sendable, Equatable {
  /// No data and a fetch in flight.
  case loading
  /// Data with at least one slice.
  case content
  /// A completed load that produced no slices. RN renders the empty-state
  /// (following vs custom feed).
  case empty
  /// A failure with no data to fall back on.
  case error(HomeFeedError)

  /// Derives the page state from a query entry, exactly as `PostFeed.tsx`
  /// orders its branches: error with no data first, then loading, then empty,
  /// then content.
  public static func derive(
    hasData: Bool, isFetching: Bool, isEmpty: Bool, error: HomeFeedError?
  ) -> FeedPageState {
    if !hasData, let error { return .error(error) }
    if isFetching, !hasData { return .loading }
    if isEmpty { return .empty }
    if hasData { return .content }
    return .loading
  }
}

/// The feed-switch state: which pinned feed is selected, and one query per feed.
///
/// Port of the selected-feed shell state plus the per-page `usePostFeedQuery`
/// instantiation in `src/view/screens/Home.tsx`. RN keys its pager on
/// `allFeeds.join(',')`, so a change in the pinned set remounts every page; this
/// model keeps a query per descriptor and rebuilds the map on the same signal.
public struct HomeFeedModel: Sendable {
  /// The store shared by every feed query.
  public let store: QueryStore
  /// The pinned feeds, in stored order.
  public var pinnedFeeds: [PinnedFeed]
  /// One query per pinned descriptor, keyed by descriptor string.
  public var queries: [String: HomeFeedQuery]
  /// The selected descriptor, or `nil` before the first selection.
  public var selectedDescriptor: FeedDescriptor?

  /// Creates the model for a set of pinned feeds.
  ///
  /// - Parameters:
  ///   - store: the shared store.
  ///   - pinnedFeeds: resolved pinned feeds, in order.
  ///   - fetchersByDescriptor: a fetcher per descriptor, supplied by the caller
  ///     so the model does not need to know the session or language context.
  ///   - tunerOptionsByDescriptor: the tuner options per descriptor.
  ///   - scope: the account scope for every key.
  public init(
    store: QueryStore,
    pinnedFeeds: [PinnedFeed],
    fetchersByDescriptor: [String: any FeedPageFetcher],
    tunerOptionsByDescriptor: [String: FeedTunerOptions],
    scope: String? = nil
  ) {
    self.store = store
    self.pinnedFeeds = pinnedFeeds
    var queries: [String: HomeFeedQuery] = [:]
    for feed in pinnedFeeds {
      let descriptor = feed.descriptor
      let key = descriptor.description
      guard let fetcher = fetchersByDescriptor[key] else { continue }
      queries[key] = HomeFeedQuery(
        store: store,
        descriptor: descriptor,
        fetcher: fetcher,
        tunerOptions: tunerOptionsByDescriptor[key] ?? FeedTunerOptions(),
        scope: scope)
    }
    self.queries = queries
    self.selectedDescriptor = pinnedFeeds.first?.descriptor
  }

  /// The descriptor strings in tab order. RN: `allFeeds`.
  public var allDescriptors: [FeedDescriptor] { pinnedFeeds.map(\.descriptor) }

  /// The query for the selected feed, or `nil` when there is none.
  public var selectedQuery: HomeFeedQuery? {
    guard let selectedDescriptor else { return nil }
    return queries[selectedDescriptor.description]
  }

  /// Selects a feed by descriptor. Unknown descriptors leave the selection
  /// alone, mirroring RN's clamped `selectedIndex`.
  public mutating func select(_ descriptor: FeedDescriptor) {
    guard queries[descriptor.description] != nil else { return }
    selectedDescriptor = descriptor
  }

  /// The presentation for the given session/preferences state.
  ///
  /// - Parameters:
  ///   - hasSession: whether an account is signed in.
  ///   - isLoadingPreferences: whether saved feeds are still hydrating.
  public static func presentation(
    hasSession: Bool, isLoadingPreferences: Bool, pinnedFeeds: [PinnedFeed]
  ) -> HomeFeedPresentation {
    if !hasSession { return .loggedOut }
    if isLoadingPreferences { return .loading }
    return pinnedFeeds.isEmpty ? .noFeedsPinned : .feeds
  }

  /// Derives the page state for the selected feed.
  public func pageState() async -> FeedPageState {
    guard let query = selectedQuery else { return .empty }
    let entry = await query.entry()
    let hasData = entry.data?.items.isEmpty == false
    let isEmpty = entry.data?.isEmptyFeed ?? true
    let error = entry.error.map(HomeFeedError.classify)
    return FeedPageState.derive(
      hasData: hasData,
      isFetching: entry.isFetching,
      isEmpty: isEmpty,
      error: error)
  }
}

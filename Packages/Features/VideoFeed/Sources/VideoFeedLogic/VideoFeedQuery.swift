import Domain
import Foundation
import Lexicons
import Moderation
import QueryStore
import SwiftAtproto

/// The preference inputs the video feed's tuner stack depends on.
///
/// Mirrors ``HomeFeedLogic/FeedTunerOptions``. Feature Logic packages in this
/// repo do not depend on one another, so the shape is restated here rather than
/// imported: the video feed only reads the content-language list, because both
/// of its descriptors get the feedgen tuner stack.
public struct VideoTunerOptions: Sendable, Equatable {
  /// `contentLanguages`, the language filter applied to generator feeds.
  public var contentLanguages: [String]

  public init(contentLanguages: [String] = []) {
    self.contentLanguages = contentLanguages
  }

  /// The options for a video feed source.
  ///
  /// RN's `useFeedTuners` reads `langPrefs.contentLanguages` for feedgens and no
  /// preferences at all for an author feed, so the author branch ignores this.
  public static func forSource(
    _ source: VideoFeedSource, contentLanguages: [String]
  ) -> VideoTunerOptions {
    switch source {
    case .feedgen: return VideoTunerOptions(contentLanguages: contentLanguages)
    case .author: return VideoTunerOptions()
    }
  }
}

/// One video feed's query: an infinite query whose pages are tuned through a
/// ``Domain/FeedTuner`` and then filtered down to playable video items.
///
/// This is the Swift counterpart of `usePostFeedQuery(feedDesc, …)` as the
/// immersive screen uses it. The store holds the tuned ``VideoFeedSlice`` list
/// per page (so a second consumer can read the same cache entry the Home feed
/// writes) and this type derives the pager's ``VideoItem`` list on demand.
///
/// Differences from RN, both structural:
/// - RN derives `videos` in a `useMemo` over `data.pages` on every render. The
///   Logic layer has no render, so ``items()`` recomputes on demand and
///   ``subscribeItems(onChange:)`` pushes updates.
/// - The tuner stack is supplied by the caller rather than read from
///   `useFeedTuners`, because the stack depends on preferences the store does not
///   own. ``VideoFeedQuery/tunerOptions(for:contentLanguages:userDid:)`` derives
///   the defaults RN would pick.
public struct VideoFeedQuery: Sendable {
  /// The store this feed lives in.
  public let store: QueryStore
  /// The resolved feed source.
  public let source: VideoFeedSource
  /// The page fetcher.
  public let fetcher: any VideoPageFetcher
  /// This feed's query key.
  public let key: QueryKey
  /// Items per request.
  public let limit: Int
  /// Resolves a moderation decision per post, or `nil` to carry none.
  public let moderation: VideoModerationResolver?

  /// Cross-page de-duplication state, one instance per query.
  private let tuner: VideoTunerBox

  /// Creates a video-feed query.
  ///
  /// - Parameters:
  ///   - store: the store to read and write.
  ///   - source: the feed identity, which forms the key.
  ///   - fetcher: the per-source page fetcher.
  ///   - tunerOptions: the preference inputs that select the tuner stack.
  ///   - feedCacheKey: the interstitial that opened the feed, part of the key.
  ///   - moderation: resolves a decision per post.
  ///   - scope: account scope (the signed-in DID).
  ///   - limit: items per request.
  public init(
    store: QueryStore,
    source: VideoFeedSource,
    fetcher: any VideoPageFetcher,
    tunerOptions: VideoTunerOptions = VideoTunerOptions(),
    feedCacheKey: VideoFeedInterstitial? = nil,
    moderation: VideoModerationResolver? = nil,
    scope: String? = nil,
    limit: Int = VideoFeedConstants.fetchLimit
  ) {
    self.store = store
    self.source = source
    self.fetcher = fetcher
    self.key = VideoFeedKeys.feed(source, feedCacheKey: feedCacheKey, scope: scope)
    self.limit = limit
    self.moderation = moderation
    self.tuner = VideoTunerBox(
      FeedTuner(tunerFns: VideoFeedTunerFactory.tuners(for: source, options: tunerOptions)))
  }

  /// The infinite query over the store. Cheap to build; built on demand.
  private var query: InfiniteQuery<VideoFeedSlice> {
    let fetcher = self.fetcher
    let tuner = self.tuner
    let limit = self.limit
    return InfiniteQuery(
      store: store,
      key: key,
      // Slices are identified by their react key, RN's `_reactKey`.
      identity: { $0.reactKey },
      fetchPage: { request in
        let raw = try await fetcher.fetch(cursor: request.cursor, limit: limit)
        let slices = Self.tune(raw, tuner: tuner)
        return InfiniteQueryData(pages: [
          QueryPage(items: slices, cursor: raw.cursor, requestCursor: request.cursor)
        ])
      })
  }

  /// Tunes a raw page into slices with the query's tuner. Port of
  /// `tuner.tune(page.feed)` in the RN `select`.
  static func tune(_ raw: VideoFeedPageOutput, tuner: VideoTunerBox) -> [VideoFeedSlice] {
    let feed = raw.feed.map(FeedViewPost.init)
    return tuner.tune(feed).map(makeVideoFeedSlice(from:))
  }

  // MARK: - Reading

  /// Every tuned slice across every page.
  public func slices() async -> [VideoFeedSlice] {
    await query.data().items
  }

  /// The pager's playable items across every page, in order.
  ///
  /// This is the port of RN's `videos` `useMemo`.
  public func items() async -> [VideoItem] {
    makeVideoItems(from: await slices(), moderation: moderation)
  }

  /// The pager's items with the `initialPostUri` offset applied.
  public func pagerItems(initialPostURI: String?) async -> [VideoItem] {
    videoPagerItems(await items(), initialPostURI: initialPostURI)
  }

  /// The typed entry, for status and error rendering.
  public func entry() async -> QueryEntry<InfiniteQueryData<VideoFeedSlice>> {
    await query.entry()
  }

  /// The number of playable videos across every page.
  public func itemCount() async -> Int {
    await items().count
  }

  /// True when no page has yielded a playable video.
  public func isEmpty() async -> Bool {
    await items().isEmpty
  }

  /// Pagination state for this feed.
  public func paginationState() async -> PaginationState {
    await store.paginationState(for: key)
  }

  // MARK: - Fetching

  /// Loads the first page, replacing whatever was held.
  @discardableResult
  public func loadFirstPage(force: Bool = false) async throws -> [VideoItem] {
    _ = try await query.loadFirstPage(staleTime: VideoFeedStale.feedPage, force: force)
    return await items()
  }

  /// Appends the next page, returning the merged playable list.
  @discardableResult
  public func loadMore() async throws -> [VideoItem] {
    _ = try await query.loadMore()
    return await items()
  }

  /// Requests `cursor` as an appended page, returning the merged playable list.
  @discardableResult
  public func fetchPage(at cursor: String?) async throws -> [VideoItem] {
    _ = try await query.fetchPage(at: cursor, isAppending: true)
    return await items()
  }

  /// Refetches page one and drops the rest. Port of `truncateAndInvalidate`.
  @discardableResult
  public func refresh() async throws -> [VideoItem] {
    _ = await store.truncateAndInvalidate(key)
    return await items()
  }

  /// Keeps fetching until the playable list reaches `target` or the walk ends.
  ///
  /// The threshold counts *playable videos*, not slices, because the video feed
  /// drops every non-video post the tuner lets through - so a page of thirty
  /// image posts contributes nothing to the pager.
  @discardableResult
  public func autoPaginate(target: Int = VideoFeedConstants.fetchLimit) async -> Int {
    await store.autoPaginate(
      key, itemCount: await itemCount(), pageSize: limit,
      maxAttempts: QueryStore.autoPaginationMaxAttempts)
  }

  // MARK: - Writing

  /// Replaces the whole page list. The optimistic-update primitive.
  public func setData(_ slices: [VideoFeedSlice], cursor: String? = nil) async {
    await query.setData(
      InfiniteQueryData(pages: [QueryPage(items: slices, cursor: cursor)]))
  }

  /// Removes this feed's entry from the store.
  public func remove() async {
    await store.remove(key)
  }

  // MARK: - Observation

  /// Registers a closure invoked with the playable items whenever the feed
  /// changes. Called once immediately with the current items.
  @discardableResult
  public func subscribeItems(
    onChange: @escaping @Sendable ([VideoItem]) -> Void
  ) async -> QuerySubscription {
    let moderation = self.moderation
    return await query.subscribeItems { slices in
      onChange(makeVideoItems(from: slices, moderation: moderation))
    }
  }
}

/// A reference box around a ``Domain/FeedTuner``.
///
/// `FeedTuner` is a class with mutable cross-page state and ``VideoFeedQuery`` is
/// a `Sendable` value whose methods run concurrently, so the tuner is confined
/// behind a lock: page fetches for one feed must not interleave their tuning.
final class VideoTunerBox: @unchecked Sendable {
  private let lock = NSLock()
  private let tuner: FeedTuner

  init(_ tuner: FeedTuner) {
    self.tuner = tuner
  }

  /// Tunes `feed`, serialized against other tuning on the same box.
  func tune(_ feed: [FeedViewPost], dryRun: Bool = false) -> [FeedViewPostsSlice] {
    lock.lock()
    defer { lock.unlock() }
    return tuner.tune(feed, dryRun: dryRun)
  }
}

/// Builds the tuner stack for a video feed source.
///
/// Port of `useFeedTuners` in `src/state/preferences/feed-tuners.tsx` for the two
/// descriptors the immersive screen produces. The ordering is load-bearing and
/// copied verbatim:
///
/// ```
/// feedgen:  preferredLangOnly(contentLanguages), removeMutedThreads
/// author:   (no tuners; RN only adds removeReposts for posts_with_replies)
/// ```
public enum VideoFeedTunerFactory {
  /// The tuner functions for `source`, in application order.
  public static func tuners(
    for source: VideoFeedSource, options: VideoTunerOptions
  ) -> [FeedTunerFn] {
    switch source {
    case .feedgen:
      return [
        FeedTuner.preferredLangOnly(options.contentLanguages),
        FeedTuner.removeMutedThreads,
      ]
    case .author(_, let filter):
      // RN adds a tuner only for `posts_with_replies`; the video filter gets none.
      if filter == .postsWithReplies {
        return [FeedTuner.removeReposts]
      }
      return []
    }
  }
}

/// Turns a ``Domain/FeedViewPostsSlice`` into a ``VideoFeedSlice``.
///
/// The slice key and item keys come from the tuner, matching the Home feed's
/// conversion so a shared cache entry renders identically in both screens.
public func makeVideoFeedSlice(from slice: FeedViewPostsSlice) -> VideoFeedSlice {
  let items = slice.items.enumerated().map { index, item in
    VideoFeedSliceItem(
      reactKey: "\(slice.reactKey)-\(index)-\(item.post.uri.rawValue)",
      uri: item.post.uri.rawValue,
      post: item.post)
  }
  return VideoFeedSlice(
    reactKey: slice.reactKey,
    feedPostUri: slice.feedPostUri,
    items: items,
    feedContext: slice.feedContext,
    reqId: slice.reqId,
    isReply: slice.isReply,
    isRepost: slice.isRepost)
}

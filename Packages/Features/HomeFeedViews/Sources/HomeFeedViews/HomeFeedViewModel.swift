import Foundation
import HomeFeedLogic
import Moderation
import Observation
import QueryStore

/**
 The Home feed's view state: the selected pinned feed, its rows, and the
 lifecycle flags the screen renders.

 This is the SwiftUI-facing half of `HomeFeedLogic.HomeFeedModel`. The logic
 package owns *what* the feed is - which slices survive tuning, whether a poll
 found anything, how a cursor walk proceeds - and stays platform-free. This type
 owns *when to ask*: subscribing to the store, driving auto-pagination as content
 arrives, and holding the flags a `View` can observe.

 `@Observable` (not `ObservableObject`) so a view that reads one flag is
 invalidated by that flag only, which matters on a list that re-renders rows.
 */
@Observable
@MainActor
public final class HomeFeedViewModel {
  /// Which surface to render when there is nothing to show.
  public private(set) var presentation: HomeFeedPresentation
  /// The lifecycle of the selected feed's page.
  public private(set) var pageState: FeedPageState = .loading
  /// The flattened rows of the selected feed.
  public private(set) var rows: [HomeFeedRow] = []
  /// True while a pull-to-refresh is in flight.
  public private(set) var isRefreshing = false
  /// True when a poll found content the feed has not shown yet.
  public private(set) var hasNewPosts = false
  /// True when the selected feed has another page to walk to.
  public private(set) var hasNextPage = false

  /// The pinned feeds, in switcher order.
  public private(set) var pinnedFeeds: [PinnedFeed]
  /// The selected descriptor.
  public private(set) var selectedDescriptor: FeedDescriptor?

  private let model: HomeFeedModel
  private let moderationOpts: ModerationOpts?
  private let viewerDid: String?
  private let now: () -> Date
  private var subscription: QuerySubscription?
  private var poller: NewPostsPoller?
  private var isPolling = false
  private var hasLoaded = false

  /// Creates the view model.
  ///
  /// - Parameters:
  ///   - model: the logic model holding one query per pinned feed.
  ///   - presentation: the surface to render (logged out, no feeds, or feeds).
  ///   - moderationOpts: engine options for the overlay decisions, or `nil` to
  ///     render everything unmasked (logged out and demo paths).
  ///   - viewerDid: the signed-in DID, for the `Reposted by you` copy.
  ///   - now: the clock used for relative timestamps, injectable for previews.
  public init(
    model: HomeFeedModel,
    presentation: HomeFeedPresentation,
    moderationOpts: ModerationOpts? = nil,
    viewerDid: String? = nil,
    now: @escaping () -> Date = { Date() }
  ) {
    self.model = model
    self.presentation = presentation
    self.moderationOpts = moderationOpts
    self.viewerDid = viewerDid
    self.now = now
    self.pinnedFeeds = model.pinnedFeeds
    self.selectedDescriptor = model.selectedDescriptor
  }

  /// True when the screen should draw the trailing pagination spinner.
  public var showsLoadMore: Bool {
    pageState == .content && hasNextPage
  }

  // MARK: - Lifecycle

  /// Starts observing the selected feed and loads it if it has no pages yet.
  ///
  /// RN runs `usePostFeedQuery` on mount and auto-paginates until `MIN_POSTS`
  /// posts are on screen; both happen here, once, on appear.
  public func onAppear() async {
    guard !hasLoaded else { return }
    hasLoaded = true
    guard presentation == .feeds, let query = model.selectedQuery else {
      presentation = model.pinnedFeeds.isEmpty ? .noFeedsPinned : presentation
      return
    }
    await subscribe(to: query)
    let entry = await query.entry()
    if entry.data?.pages.isEmpty != false {
      try? await query.loadFirstPage()
      await autoPaginateIfNeeded(query)
    }
    await refreshState()
  }

  /// Stops observing. A subscription outliving its view would keep refetching a
  /// feed the user has left and leak the closure's owner.
  public func onDisappear() async {
    await subscription?.cancel()
    subscription = nil
  }

  // MARK: - Selection

  /// Switches to another pinned feed.
  public func select(_ descriptor: FeedDescriptor) async {
    guard descriptor != selectedDescriptor else { return }
    guard let query = model.queries[descriptor.description] else { return }
    await subscription?.cancel()
    subscription = nil
    selectedDescriptor = descriptor
    hasNewPosts = false
    rows = []
    hasNextPage = false
    pageState = .loading
    await subscribe(to: query)
    let entry = await query.entry()
    if entry.data == nil {
      try? await query.loadFirstPage()
      await autoPaginateIfNeeded(query)
    }
    await refreshState()
  }

  private func subscribe(to query: HomeFeedQuery) async {
    // The poller wants a clock; `QueryStore` keeps its own instance private, so
    // the view model supplies the wall clock the store defaults to.
    poller = NewPostsPoller(query: query, clock: SystemQueryClock())
    subscription = await query.subscribeSlices { [weak self] slices in
      Task { @MainActor in
        self?.apply(slices)
      }
    }
  }

  // MARK: - Loading

  /// Pull-to-refresh: refetches page one and drops the rest, clearing the pill.
  ///
  /// Port of `onRefresh` in `src/view/com/posts/PostFeed.tsx`, which calls
  /// `truncateAndInvalidate` under an `isPTRing` flag.
  public func refresh() async {
    guard let query = model.selectedQuery else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    try? await query.refresh()
    await autoPaginateIfNeeded(query)
    hasNewPosts = false
    await refreshState()
  }

  /// Loads the next page. Called by the last row's `onAppear`, the native
  /// stand-in for RN's `onEndReached`.
  public func loadMore() async {
    guard let query = model.selectedQuery else { return }
    let pagination = await query.paginationState()
    guard pagination.hasNextPage else {
      hasNextPage = false
      return
    }
    try? await query.loadMore()
    await autoPaginateIfNeeded(query)
    await refreshState()
  }

  /// The new-posts pill's action: refetch the head and drop the pill.
  public func tapNewPosts() async {
    await refresh()
  }

  /// Runs one new-posts poll.
  ///
  /// Returns `true` when the caller should reveal the pill. RN runs this on
  /// focus (when the feed is stale or empty) and on a 60s timer; the screen owns
  /// the timer and calls in, exactly as the logic package's docs describe.
  @discardableResult
  public func pollForNewPosts() async -> Bool {
    guard let poller, !isPolling, presentation == .feeds else { return false }
    isPolling = true
    defer { isPolling = false }
    let entry = await poller.query.entry()
    let decision = await poller.check(isFetching: entry.isFetching)
    switch decision {
    case .idle:
      return false
    case .showPill:
      hasNewPosts = true
      return true
    case .refetch:
      await refresh()
      return false
    }
  }

  // MARK: - Internals

  /// Fills the first page up to `MIN_POSTS` when it came back short.
  ///
  /// RN's `useAutoPagination(query, itemCount, MIN_POSTS)`: a feed that filtered
  /// most of its page wants another page before it renders, so the user does not
  /// see a nearly-empty list with a spinner.
  private func autoPaginateIfNeeded(_ query: HomeFeedQuery) async {
    let count = await query.itemCount()
    guard count < HomeFeedConstants.minPosts else { return }
    await query.autoPaginate()
  }

  private func apply(_ slices: [HomeFeedSlice]) {
    rows = HomeFeedViewData.rows(
      slices,
      moderationOpts: moderationOpts,
      viewerDid: viewerDid,
      options: FeedItemRenderOptions(now: now()))
  }

  /// Re-reads the entry to recompute the page state, rows and pagination flag.
  private func refreshState() async {
    guard let query = model.selectedQuery else {
      pageState = .empty
      rows = []
      hasNextPage = false
      return
    }
    let entry = await query.entry()
    let data = entry.data
    let slices = data?.slices ?? []
    apply(slices)
    // A slice the viewer's moderation settings hide completely produces no row,
    // so the visible count - not the slice count - decides content vs empty.
    let visibleRows = rows.count
    hasNextPage = await query.paginationState().hasNextPage
    pageState = FeedPageState.derive(
      hasData: visibleRows > 0,
      isFetching: entry.isFetching,
      isEmpty: data?.isEmptyFeed ?? true,
      error: entry.error.map(HomeFeedError.classify))
    // Filtered-to-nothing is empty, not an error: there is content fetched, the
    // viewer's settings simply hide all of it.
    if case .error = pageState, !slices.isEmpty {
      pageState = visibleRows > 0 ? .content : .empty
    }
  }
}

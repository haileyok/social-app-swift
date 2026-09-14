import Domain
import Foundation
import Lexicons
import QueryStore
import Testing

@testable import HomeFeedLogic

/// The new-posts pill state machine, driven by a manual clock.
@Suite("New posts polling")
struct NewPostsPollerTests {
  /// A query whose feed has one page of `posts` items and a next cursor.
  func makeQuery(
    store: QueryStore, xrpc: RecordingFeedXrpc, options: FeedTunerOptions = FeedTunerOptions()
  ) -> HomeFeedQuery {
    HomeFeedQuery(
      store: store,
      descriptor: .following,
      fetcher: FollowingFeedFetcher(xrpc: xrpc),
      tunerOptions: options)
  }

  @Test("polling before any page has loaded does nothing")
  func idleWithoutData() async throws {
    let xrpc = RecordingFeedXrpc()
    let store = QueryStore()
    let query = makeQuery(store: store, xrpc: xrpc)
    let poller = NewPostsPoller(query: query, clock: ManualQueryClock())

    let decision = await poller.check()
    #expect(decision == .idle)
    // No peek was issued either, since there is no first page.
    #expect(xrpc.calls.isEmpty)
  }

  @Test("a disabled poll does nothing, even with fresh content available")
  func disabled() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(cursor: nil, feed: [Fixtures.item("a")])])
    let store = QueryStore()
    let query = makeQuery(store: store, xrpc: xrpc)
    _ = try await query.loadFirstPage()
    let poller = NewPostsPoller(query: query, clock: ManualQueryClock())

    let decision = await poller.check(isEnabled: false)
    #expect(decision == .idle)
    let disabled = await poller.check(disablePoll: true)
    #expect(disabled == .idle)
    let fetching = await poller.check(isFetching: true)
    #expect(fetching == .idle)
  }

  @Test("new content with a populated feed shows the pill")
  func showsPill() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(cursor: nil, feed: [Fixtures.item("a")])])
    let store = QueryStore()
    let query = makeQuery(store: store, xrpc: xrpc)
    _ = try await query.loadFirstPage()

    // The peek returns a post the tuner would admit.
    xrpc.setTimelinePages([FeedTimelinePage(feed: [Fixtures.item("newest")])])
    let poller = NewPostsPoller(query: query, clock: ManualQueryClock())

    let decision = await poller.check()
    #expect(decision == .showPill)
    // The peek requested exactly one item with no cursor, as `peekLatest` does.
    #expect(xrpc.calls.last == .timeline(cursor: nil, limit: 1))
  }

  @Test("no new content leaves the caller idle")
  func noNewContent() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(cursor: nil, feed: [Fixtures.item("a")])])
    let store = QueryStore()
    let query = makeQuery(store: store, xrpc: xrpc)
    _ = try await query.loadFirstPage()

    // The peek returns nothing, so there is no head item.
    xrpc.setTimelinePages([FeedTimelinePage(feed: [])])
    let poller = NewPostsPoller(query: query, clock: ManualQueryClock())

    let decision = await poller.check()
    #expect(decision == .idle)
  }

  @Test("new content on an empty feed asks for a refetch instead of a pill")
  func refetchWhenEmpty() async throws {
    let xrpc = RecordingFeedXrpc()
    // The first page tuned down to nothing (an all-filtered page).
    let root = Fixtures.post("root")
    let parent = Fixtures.reply("parent", parent: root)
    let stranger = Fixtures.feedViewPost(
      Fixtures.reply(
        "stranger", parent: parent, root: root,
        author: Fixtures.profile(did: "did:plc:stranger", handle: "stranger.test")),
      reply: Fixtures.replyRef(parent: parent, root: root))
    xrpc.setTimelinePages([FeedTimelinePage(cursor: nil, feed: [stranger])])

    let store = QueryStore()
    let query = makeQuery(
      store: store, xrpc: xrpc, options: FeedTunerOptions(userDid: "did:plc:alice"))
    let data = try await query.loadFirstPage()
    // The page is empty from the feed's point of view.
    #expect(data.isEmptyFeed)

    // Now the appview has a post the tuner would admit.
    xrpc.setTimelinePages([FeedTimelinePage(feed: [Fixtures.item("fresh")])])
    let poller = NewPostsPoller(query: query, clock: ManualQueryClock())

    let decision = await poller.check()
    #expect(decision == .refetch)
  }

  @Test("Discover always reports new content without asking the appview")
  func discoverAlwaysNew() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(cursor: nil, feed: [Fixtures.item("a")])])
    let store = QueryStore()
    let query = makeQuery(store: store, xrpc: xrpc)
    _ = try await query.loadFirstPage()
    let poller = NewPostsPoller(query: query, clock: ManualQueryClock())

    let before = xrpc.calls.count
    let decision = await poller.check(isDiscover: true)
    #expect(decision == .showPill)
    // RN returns before calling `peekLatest` for Discover.
    #expect(xrpc.calls.count == before)
  }

  @Test("a network failure during the peek is swallowed, leaving the caller idle")
  func networkFailureSwallowed() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(cursor: nil, feed: [Fixtures.item("a")])])
    let store = QueryStore()
    let query = makeQuery(store: store, xrpc: xrpc)
    _ = try await query.loadFirstPage()

    xrpc.fail("timeline")
    let poller = NewPostsPoller(query: query, clock: ManualQueryClock())
    let reported = Box<any Error>()
    let decision = await poller.check(onFailure: { error in reported.set(error) })

    #expect(decision == .idle)
    // The failure is surfaced to the caller's handler; RN decides there whether
    // it is a network error worth logging.
    #expect(reported.value != nil)
  }

  @Test("a dry-run peek does not consume the tuner's seen state")
  func dryRunDoesNotMutateTuner() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(cursor: nil, feed: [Fixtures.item("a")])])
    let store = QueryStore()
    let query = makeQuery(store: store, xrpc: xrpc)
    _ = try await query.loadFirstPage()

    xrpc.setTimelinePages([FeedTimelinePage(feed: [Fixtures.item("newest")])])
    let poller = NewPostsPoller(query: query, clock: ManualQueryClock())
    _ = await poller.check()

    // After the poll, a real load of that same item must still be admitted -
    // the dry run must not have recorded it as seen.
    xrpc.setTimelinePages([FeedTimelinePage(cursor: nil, feed: [Fixtures.item("newest")])])
    let refreshed = try await query.refresh()
    let uris = refreshed.slices.flatMap { $0.items.map(\.uri) }
    #expect(uris.contains(Fixtures.uri("newest")))
  }

  // MARK: - Focus gate

  @Test("an empty feed always checks on focus")
  func emptyChecksOnFocus() async throws {
    let xrpc = RecordingFeedXrpc()
    let store = QueryStore()
    let query = makeQuery(store: store, xrpc: xrpc)
    let clock = ManualQueryClock()
    let poller = NewPostsPoller(query: query, clock: clock)

    #expect(await poller.shouldCheckOnFocus(isEnabled: true))
  }

  @Test("a feed fetched less than thirty seconds ago does not check on focus")
  func freshFeedSkipsFocusCheck() async throws {
    let clock = ManualQueryClock()
    let store = QueryStore(clock: clock)
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(cursor: nil, feed: [Fixtures.item("a")])])
    let query = makeQuery(store: store, xrpc: xrpc)
    _ = try await query.loadFirstPage()

    let poller = NewPostsPoller(query: query, clock: clock)
    // Immediately after the fetch: inside the 30s window.
    clock.advance(by: 10)
    #expect(!(await poller.shouldCheckOnFocus(isEnabled: true)))

    // Past CHECK_LATEST_AFTER: the check runs.
    clock.advance(by: HomeFeedConstants.checkLatestAfter)
    #expect(await poller.shouldCheckOnFocus(isEnabled: true))
  }

  @Test("the focus check is gated on enabled")
  func focusCheckDisabled() async throws {
    let xrpc = RecordingFeedXrpc()
    let store = QueryStore()
    let query = makeQuery(store: store, xrpc: xrpc)
    let poller = NewPostsPoller(query: query, clock: ManualQueryClock())

    #expect(!(await poller.shouldCheckOnFocus(isEnabled: false)))
  }

  @Test("the timer constants are the ones RN passes")
  func pollConstants() {
    #expect(HomeFeedConstants.checkLatestAfter == 30)
    #expect(HomeFeedConstants.defaultPollInterval == 60)
  }
}

/// A tiny lock-guarded box so a `@Sendable` closure can hand a value back.
final class Box<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: T?

  var value: T? { lock.withLock { stored } }

  func set(_ value: T) { lock.withLock { stored = value } }
}

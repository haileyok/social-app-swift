import Foundation
import QueryStore

/// The new-posts poll state machine.
///
/// Port of the `checkForNew` callback plus its two effect triggers in
/// `src/view/com/posts/PostFeed.tsx`. The RN component owns the timer and the
/// app-state listener; this type owns only the decision logic, so it is
/// testable against a ``QueryStore/ManualQueryClock`` instead of a real timer.
///
/// The rules, in RN's order:
///
/// ```
/// checkForNew:
///   no first page, already fetching, disabled, or no onHasNew  -> do nothing
///   Discover feed                                              -> hasNew = true
///   pollLatest() true and the feed is empty                    -> refetch
///   pollLatest() true and the feed has content                 -> hasNew = true
///   pollLatest() false                                         -> do nothing
/// ```
///
/// Two triggers, both gated on `enabled && !disablePoll`:
/// - on enable (focus): only when the feed is empty, or more than
///   `CHECK_LATEST_AFTER` (30s) has passed since the first page was fetched.
/// - on a timer, every `pollInterval` (60s on the feed screens), and whenever
///   the app returns to the foreground.
public struct NewPostsPoller: Sendable {
  /// What a poll decided the caller should do.
  public enum Decision: Sendable, Equatable {
    /// Nothing to do.
    case idle
    /// The feed has unseen content; show the new-posts pill.
    case showPill
    /// The feed is empty and has content now; refetch instead of showing a pill.
    case refetch
  }

  /// The feed being polled.
  public let query: HomeFeedQuery
  /// The store clock, used for the `CHECK_LATEST_AFTER` gate.
  public let clock: any QueryClock

  public init(query: HomeFeedQuery, clock: any QueryClock) {
    self.query = query
    self.clock = clock
  }

  /// The default poll interval in seconds. RN passes `60e3` ms.
  public var pollInterval: TimeInterval { HomeFeedConstants.defaultPollInterval }

  /// True when the on-focus check should run: the feed is empty, or the first
  /// page is older than `CHECK_LATEST_AFTER`.
  ///
  /// Port of the `useEffect` gated on `[enabled, isEmpty, disablePoll,
  /// checkForNew]`:
  /// ```
  /// if (isEmpty || Date.now() - lastFetchRef.current > CHECK_LATEST_AFTER) checkForNew()
  /// ```
  /// `lastFetchRef` tracks `data.pages[0].fetchedAt`, i.e. the first page's fetch
  /// time, not the newest page's.
  public func shouldCheckOnFocus(isEnabled: Bool) async -> Bool {
    guard isEnabled else { return false }
    let entry = await query.entry()
    guard let fetchedAt = entry.fetchedAt else { return true }
    let elapsedSeconds = Double(clock.nowMicroseconds() - fetchedAt) / 1_000_000
    if await query.isEmpty() { return true }
    return elapsedSeconds > HomeFeedConstants.checkLatestAfter
  }

  /// Runs one poll check.
  ///
  /// - Parameters:
  ///   - isEnabled: the view's `enabled` gate.
  ///   - isFetching: whether a fetch is in flight, from the query entry.
  ///   - disablePoll: the view's `disablePoll` gate.
  ///   - isDiscover: whether this is the Discover feed, which always has fresh
  ///     content, so RN reports "new" without asking.
  ///   - onFailure: invoked with a non-network error. RN swallows network
  ///     errors and warns on everything else.
  /// - Returns: what the caller should do.
  public func check(
    isEnabled: Bool = true,
    isFetching: Bool = false,
    disablePoll: Bool = false,
    isDiscover: Bool = false,
    onFailure: (@Sendable (any Error) -> Void)? = nil
  ) async -> Decision {
    guard isEnabled, !disablePoll, !isFetching else { return .idle }

    let entry = await query.entry()
    // RN bails when there is no first page: nothing has loaded yet, so there is
    // no "new" to report. The page may legitimately hold zero slices - an
    // all-filtered page is exactly the case that wants a refetch.
    guard entry.data?.pages.isEmpty == false else { return .idle }

    if isDiscover { return .showPill }

    do {
      guard try await query.pollLatest() else { return .idle }
    } catch {
      onFailure?(error)
      return .idle
    }

    return await query.isEmpty() ? .refetch : .showPill
  }
}

import Foundation

/// Lifecycle state of a cache entry, mirroring the TanStack Query status set the
/// RN app switches on.
public enum QueryStatus: String, Sendable, Hashable, Codable {
  /// No fetch has run yet and no data has been placed in the entry.
  case idle
  /// A first fetch is in flight; the entry has no data yet.
  case loading
  /// The entry holds data. A background refetch may still be in flight.
  case success
  /// The most recent attempt failed. Data from an earlier success is preserved
  /// when there is any, which is what lets a failed refresh keep showing stale
  /// content.
  case error
}

/// Why a fetch was started.
public enum QueryFetchReason: String, Sendable, Hashable {
  /// No entry existed, or the entry had no data.
  case initial
  /// The entry existed and its data was older than its stale time.
  case stale
  /// ``QueryStore/invalidate(_:refetch:)`` asked for this key.
  case invalidated
  /// ``QueryStore/loadMore(_:options:as:)`` asked for the next page.
  case nextPage
  /// ``QueryStore/restorePersisted()`` produced this entry.
  case restored
}

/// Observable transitions emitted by the store.
public enum QueryEvent: Sendable {
  /// A fetch started and is in flight until the matching completion event.
  case fetchStarted(key: QueryKey, reason: QueryFetchReason)
  /// A fetch succeeded.
  case fetchSucceeded(key: QueryKey, payload: any Sendable)
  /// A fetch failed. `hadData` is true when an earlier payload was preserved.
  case fetchFailed(key: QueryKey, error: any Error, hadData: Bool)
  /// Data was replaced directly, by ``QueryStore/setQueryData(_:for:)``, by
  /// ``QueryStore/updateQueryData(_:as:_:)``, or by a restore. `payload` is
  /// `nil` when the entry's data was cleared.
  case dataSet(key: QueryKey, payload: (any Sendable)?)
  /// The entry was removed or reset.
  case removed(key: QueryKey)
  /// Every entry was removed, e.g. on sign-out.
  case removedAll
  /// Entries were restored from a persisted snapshot. `count` is the number of
  /// entries read before per-key version filtering.
  case restored(count: Int)
}

/// A fetch request handed to a fetcher closure.
///
/// Infinite queries read `cursor` and return the page it names; single-shot
/// queries ignore the parameter entirely.
public struct QueryFetchRequest: Sendable {
  /// Cursor to request, or `nil` for the first page.
  public let cursor: String?
  /// True when this request appends a page to an existing list rather than
  /// loading the first page.
  public let isAppending: Bool
  /// Number of pages the entry already holds.
  public let pageIndex: Int

  public init(cursor: String? = nil, isAppending: Bool = false, pageIndex: Int = 0) {
    self.cursor = cursor
    self.isAppending = isAppending
    self.pageIndex = pageIndex
  }

  /// The first-page request.
  public static let firstPage = QueryFetchRequest()
}

/// Options controlling a single fetch.
public struct FetchOptions: Sendable {
  /// Overrides the store's default stale time for this key.
  public var staleTime: TimeInterval?
  /// When true, fetch even if the entry is fresh.
  public var force: Bool
  /// Cursor to request. Infinite queries pass this; `nil` means "first page".
  public var cursor: String?
  /// True when this fetch appends a page rather than (re)loading the first one.
  public var appendingPage: Bool
  /// Reason to report to observers. Inferred when not supplied.
  public var reason: QueryFetchReason?
  /// When false, a successful fetch is not offered to the persistence sink.
  public var persist: Bool

  public init(
    staleTime: TimeInterval? = nil,
    force: Bool = false,
    cursor: String? = nil,
    appendingPage: Bool = false,
    reason: QueryFetchReason? = nil,
    persist: Bool = true
  ) {
    self.staleTime = staleTime
    self.force = force
    self.cursor = cursor
    self.appendingPage = appendingPage
    self.reason = reason
    self.persist = persist
  }
}

/// Thrown when a stored payload cannot be handed back as the type the caller
/// asked for, which means one key was reused with two payload types.
public struct QueryTypeMismatchError: Error, CustomStringConvertible {
  public let key: QueryKey
  public let expected: String

  public init(key: QueryKey, expected: String) {
    self.key = key
    self.expected = expected
  }

  public var description: String {
    "QueryStore payload for \(key) is not \(expected)"
  }
}

/// Thrown when an infinite query is asked for a page it cannot request.
public struct QueryPaginationError: Error, CustomStringConvertible {
  /// Why the store refused to paginate.
  public enum Reason: String, Sendable {
    /// The last page reported no next cursor.
    case exhausted
    /// The cursor for the next page repeats the cursor of an earlier page, so
    /// the server is looping.
    case repeatedCursor
    /// No entry exists for the key yet.
    case noData
  }

  public let key: QueryKey
  public let reason: Reason

  public init(key: QueryKey, reason: Reason) {
    self.key = key
    self.reason = reason
  }

  public var description: String {
    "QueryStore cannot paginate \(key): \(reason.rawValue)"
  }
}

/// A handle that detaches a subscriber or observer when it is cancelled.
public struct QuerySubscription: Sendable {
  private let cancelAction: @Sendable () async -> Void

  init(cancelAction: @escaping @Sendable () async -> Void) {
    self.cancelAction = cancelAction
  }

  /// Detaches the subscription. Safe to call more than once.
  public func cancel() async {
    await cancelAction()
  }

  /// A subscription that does nothing.
  public static let inactive = QuerySubscription(cancelAction: {})
}

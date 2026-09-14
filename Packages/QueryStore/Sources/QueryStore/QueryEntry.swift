import Foundation

/// One cache entry, the analogue of a TanStack Query `Query` object.
public struct QueryEntry<Data: Sendable>: Sendable {
  /// Current lifecycle state.
  public var status: QueryStatus
  /// Payload, present whenever a fetch has succeeded.
  public var data: Data?
  /// Most recent error. Preserved across successful refetches only until the
  /// refetch succeeds, at which point it is cleared.
  public var error: (any Error)?
  /// Wall-clock microseconds at which `data` was produced.
  public var fetchedAt: Int64?
  /// Wall-clock microseconds at which the most recent fetch attempt started.
  public var fetchStartedAt: Int64?
  /// Staleness budget in effect for this entry, in seconds. A per-key override
  /// passed to ``QueryStore/fetch(_:options:fetcher:)`` wins over the store
  /// default and is remembered here so `isStale` agrees on later reads.
  public var staleTime: TimeInterval
  /// True while a fetch is in flight.
  public var isFetching: Bool
  /// True when the entry has data but no fetch has ever completed for it since
  /// the last invalidation.
  public var isInvalidated: Bool
  /// True when this entry holds an ``InfiniteQueryData`` payload.
  public var isInfinite: Bool
  /// Fetch attempts that have failed since the last success.
  public var failureCount: Int

  /// A brand-new entry.
  public static func empty(staleTime: TimeInterval) -> QueryEntry<Data> {
    QueryEntry(
      status: .idle,
      data: nil,
      error: nil,
      fetchedAt: nil,
      fetchStartedAt: nil,
      staleTime: staleTime,
      isFetching: false,
      isInvalidated: false,
      isInfinite: false,
      failureCount: 0
    )
  }

  /// True when the entry has no payload yet.
  public var isEmpty: Bool { data == nil }

  /// True when the entry has data to show.
  public var hasData: Bool { data != nil }

  /// True when the entry's data is older than its staleness budget.
  ///
  /// - Parameter now: current wall-clock microseconds.
  public func isStale(now: Int64) -> Bool {
    guard let fetchedAt else { return true }
    guard !isInvalidated else { return true }
    if staleTime.isInfinite { return false }
    let age = TimeInterval(now - fetchedAt) / 1_000_000
    return age >= staleTime
  }

  /// True when a fetch should be started for this entry.
  ///
  /// - Parameters:
  ///   - now: current wall-clock microseconds.
  ///   - force: when true, ignore freshness.
  ///   - appendingPage: when true, freshness of the head page is irrelevant.
  public func needsFetch(now: Int64, force: Bool, appendingPage: Bool) -> Bool {
    if force { return true }
    if data == nil { return true }
    if appendingPage { return false }
    return isStale(now: now)
  }

  /// A type-erased description of this entry, for public reads and logging.
  public var snapshot: QueryEntrySnapshot {
    QueryEntrySnapshot(
      status: status,
      error: error,
      fetchedAt: fetchedAt,
      fetchStartedAt: fetchStartedAt,
      staleTime: staleTime,
      isFetching: isFetching,
      isInvalidated: isInvalidated,
      isInfinite: isInfinite,
      failureCount: failureCount,
      hasData: data != nil
    )
  }
}

/// A type-erased read of an entry, including entries whose payload type is not
/// known at the call site.
public struct QueryEntrySnapshot: Sendable {
  public let status: QueryStatus
  public let error: (any Error)?
  public let fetchedAt: Int64?
  public let fetchStartedAt: Int64?
  public let staleTime: TimeInterval
  public let isFetching: Bool
  public let isInvalidated: Bool
  public let isInfinite: Bool
  public let failureCount: Int
  public let hasData: Bool

  public init(
    status: QueryStatus,
    error: (any Error)?,
    fetchedAt: Int64?,
    fetchStartedAt: Int64?,
    staleTime: TimeInterval,
    isFetching: Bool,
    isInvalidated: Bool,
    isInfinite: Bool,
    failureCount: Int,
    hasData: Bool
  ) {
    self.status = status
    self.error = error
    self.fetchedAt = fetchedAt
    self.fetchStartedAt = fetchStartedAt
    self.staleTime = staleTime
    self.isFetching = isFetching
    self.isInvalidated = isInvalidated
    self.isInfinite = isInfinite
    self.failureCount = failureCount
    self.hasData = hasData
  }
}

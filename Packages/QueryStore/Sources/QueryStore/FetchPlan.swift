import Foundation

/// The typed logic the store needs for one key, erased so it can live in the
/// store's plain dictionaries.
///
/// This is the seam that lets ``QueryStore`` stay type-agnostic while
/// `InfiniteQuery` and the `fetch` overloads stay strongly typed: the caller
/// knows the payload type, so it supplies the two things the store cannot derive
/// for itself - how to merge a page, and what metadata a page has.
struct FetchPlan: Sendable {
  /// Reason to report to observers. Inferred when `nil`.
  var reason: QueryFetchReason?
  /// Per-fetch staleness override. Remembered on the entry.
  var staleTime: TimeInterval?
  /// Fetch even when the entry is fresh.
  var force: Bool
  /// Mark the entry as an infinite query.
  var isInfinite: Bool
  /// Record the entry as persisted, so a successful fetch reaches the sink.
  var persist: Bool
  /// True when this fetch produces the first page and must replace the page list.
  var resetsPages: Bool
  /// Merges an incoming page into the stored list.
  var merge: MergeClosure?
  /// Describes a returned page, so the store can paginate without decoding it.
  var describe: DescribeClosure?

  /// Merges `incoming` into the payload held by `existing`, in light of the page
  /// descriptors already recorded.
  ///
  /// Returning `nil` means "refuse this page": the payload is left untouched and
  /// the page descriptor is dropped, so pagination state cannot outrun the data.
  typealias MergeClosure = @Sendable (StoredPayload, any Sendable, [PageDescriptor]) -> StoredPayload?

  /// Builds the page metadata for a returned payload.
  typealias DescribeClosure = @Sendable (any Sendable, QueryFetchRequest) -> PageDescriptor?

  init(
    reason: QueryFetchReason? = nil,
    staleTime: TimeInterval? = nil,
    force: Bool = false,
    isInfinite: Bool = false,
    persist: Bool = false,
    resetsPages: Bool = false,
    merge: MergeClosure? = nil,
    describe: DescribeClosure? = nil
  ) {
    self.reason = reason
    self.staleTime = staleTime
    self.force = force
    self.isInfinite = isInfinite
    self.persist = persist
    self.resetsPages = resetsPages
    self.merge = merge
    self.describe = describe
  }

  /// Returns a copy of this plan marked as appending a page.
  func markingAppend(cursor: String?) -> FetchPlan {
    var plan = self
    plan.reason = .nextPage
    plan.force = false
    plan.resetsPages = false
    _ = cursor
    return plan
  }
}

/// Cursor metadata for one held page, kept alongside the entry so the store can
/// paginate without decoding the payload.
struct PageDescriptor: Sendable, Hashable {
  /// Cursor that produced the page.
  var requestCursor: String?
  /// Cursor the page returned.
  var cursor: String?
  /// Items across every page up to and including this one.
  ///
  /// Cumulative rather than per-page, because a de-duplicating merge can drop
  /// items from an incoming page. The count describes the list, not the response.
  var totalItemCount: Int

  init(requestCursor: String? = nil, cursor: String? = nil, totalItemCount: Int = 0) {
    self.requestCursor = requestCursor
    self.cursor = cursor
    self.totalItemCount = totalItemCount
  }
}

/// Runtime state for one key: its typed logic and the fetcher to run.
struct KeyRuntime: Sendable {
  var plan: FetchPlan
  var fetcher: @Sendable (QueryFetchRequest) async throws -> any Sendable

  /// True when this key's payload is paged.
  var isInfinite: Bool { plan.isInfinite }
}

/// The cursor chain held for one infinite query.
///
/// Kept separate from ``KeyRuntime`` because an infinite payload can be written
/// directly through ``QueryStore/setQueryData(_:for:persist:descriptors:)``
/// before any fetch has registered a runtime, and pagination must still work.
struct PageChain: Sendable {
  var pages: [PageDescriptor] = []

  /// Total items across every page, as reported by the newest descriptor.
  var itemCount: Int { pages.last?.totalItemCount ?? 0 }

  /// Cursor for the next request, or `nil` when the list is exhausted.
  var nextCursor: String? { pages.last?.cursor }

  /// True while another page can be requested.
  var hasNextPage: Bool { nextCursor != nil }

  /// Number of pages held.
  var pageCount: Int { pages.count }

  /// True when the most recent request repeated a cursor used before it.
  ///
  /// This is the RN hook's `repeatedCursor` guard, which compares the cursor of
  /// the last page param against the earlier ones. A server that echoes its own
  /// cursor makes the walk loop; this catches it one request after it starts.
  var hasRepeatedCursor: Bool {
    guard let last = pages.last?.requestCursor else { return false }
    return pages.dropLast().contains { $0.requestCursor == last }
  }

  /// The public, payload-free view of this chain.
  var state: PaginationState {
    PaginationState(
      pageCount: pageCount,
      itemCount: itemCount,
      nextCursor: nextCursor,
      hasNextPage: hasNextPage
    )
  }
}

/// Public, payload-free view of an infinite query's pagination state.
public struct PaginationState: Sendable, Hashable {
  /// Number of pages held.
  public let pageCount: Int
  /// Number of items across every page.
  public let itemCount: Int
  /// Cursor for the next request, or `nil` when exhausted.
  public let nextCursor: String?
  /// True while another page can be requested.
  public let hasNextPage: Bool

  public init(pageCount: Int, itemCount: Int, nextCursor: String?, hasNextPage: Bool) {
    self.pageCount = pageCount
    self.itemCount = itemCount
    self.nextCursor = nextCursor
    self.hasNextPage = hasNextPage
  }

  /// A state for a key that is not an infinite query.
  public static let none = PaginationState(pageCount: 0, itemCount: 0, nextCursor: nil, hasNextPage: false)
}

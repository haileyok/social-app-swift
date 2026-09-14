import Foundation

/// A single page of an infinite query.
///
/// `Codable` and `QueryPayload` conformance is conditional on the item type, so a
/// page of `Codable` items can be persisted and a page of arbitrary `Sendable`
/// items still works in memory.
public struct QueryPage<Item: Sendable>: Sendable {
  /// Items returned by this page, already deduped against earlier pages when a
  /// ``PageMergePolicy/deduplicate(by:)`` policy was used.
  public let items: [Item]
  /// Cursor returned by the page, or `nil` when the list is exhausted. This is
  /// the Swift form of `getNextPageParam: lastPage => lastPage.cursor`.
  public let cursor: String?
  /// The cursor that produced this page, used to detect a server repeating
  /// itself. `nil` for the first page.
  public let requestCursor: String?

  public init(items: [Item], cursor: String?, requestCursor: String? = nil) {
    self.items = items
    self.cursor = cursor
    self.requestCursor = requestCursor
  }

  /// True when the page reported no next cursor.
  public var isTerminal: Bool { cursor == nil }
}

/// The ordered page list plus cursor of an infinite query, the Swift analogue of
/// TanStack's `InfiniteData`: `{pages, pageParams}`.
public struct InfiniteQueryData<Item: Sendable>: Sendable {
  /// Pages in request order.
  public var pages: [QueryPage<Item>]

  public init(pages: [QueryPage<Item>] = []) {
    self.pages = pages
  }

  /// Every item across every page, in order. This is the flattened accessor the
  /// views iterate.
  public var items: [Item] { pages.flatMap(\.items) }

  /// Number of items across every page.
  public var itemCount: Int { pages.reduce(0) { $0 + $1.items.count } }

  /// Cursor for the next request, or `nil` when the list is exhausted.
  public var nextCursor: String? { pages.last?.cursor }

  /// True while another page can be requested.
  public var hasNextPage: Bool { nextCursor != nil }

  /// The cursor that produced the most recently appended page.
  public var lastRequestCursor: String? { pages.last?.requestCursor }

  /// Returns a copy with `page` appended.
  public func appending(_ page: QueryPage<Item>) -> InfiniteQueryData<Item> {
    InfiniteQueryData(pages: pages + [page])
  }

  /// Keeps only the first `count` pages. The Swift analogue of the RN
  /// `truncateAndInvalidate` helper, which slices `pages` and `pageParams` to 1.
  public mutating func truncate(to count: Int) {
    if pages.count > count { pages = Array(pages.prefix(count)) }
  }

  /// True when `cursor` already produced an earlier page, which means a request
  /// for it would loop.
  public func repeatsCursor(_ cursor: String?) -> Bool {
    guard let cursor else { return false }
    return pages.dropLast().contains { $0.requestCursor == cursor }
  }
}

/// How to reconcile an incoming page with the pages already held.
public enum PageMergePolicy<Item: Sendable>: Sendable {
  /// Concatenate. The incoming page is taken as-is.
  case append
  /// Concatenate, dropping incoming items whose identity already appears in an
  /// earlier page. `identity` is the dedupe-on-merge hook; pass the item's
  /// identity (`uri`, `did`, ...).
  case deduplicate(by: @Sendable (Item) -> String)
}

extension InfiniteQueryData {
  /// Merges `page` into the list according to `policy`.
  ///
  /// Under ``PageMergePolicy/deduplicate(by:)`` the incoming page keeps only the
  /// items whose identity has not been seen in an earlier page. Overlap between
  /// pages is normal in cursor-paginated feeds: a post can move position between
  /// requests, so a naive append would render duplicates.
  ///
  /// - Parameters:
  ///   - page: page returned by the fetcher, with `requestCursor` set.
  ///   - policy: how to reconcile it with the existing pages.
  /// - Returns: the merged page list.
  public func merging(_ page: QueryPage<Item>, policy: PageMergePolicy<Item>) -> InfiniteQueryData<Item> {
    switch policy {
    case .append:
      return appending(page)
    case .deduplicate(let identity):
      var seen = Set(items.map(identity))
      var kept: [Item] = []
      kept.reserveCapacity(page.items.count)
      for item in page.items where seen.insert(identity(item)).inserted {
        kept.append(item)
      }
      return appending(QueryPage(items: kept, cursor: page.cursor, requestCursor: page.requestCursor))
    }
  }
}

// MARK: - Persistence

extension QueryPage: Codable where Item: Codable {}
extension QueryPage: Persistable where Item: Codable {}
extension QueryPage: QueryPayload where Item: Codable {}

extension InfiniteQueryData: Codable where Item: Codable {}
extension InfiniteQueryData: Persistable where Item: Codable {}
extension InfiniteQueryData: QueryPayload where Item: Codable {}

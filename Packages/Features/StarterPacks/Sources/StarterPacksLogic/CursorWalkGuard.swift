import Foundation

/// A set of cursors already requested, behind a lock.
///
/// ## Why this exists
///
/// `QueryStore`'s public ``InfiniteQuery/loadMore()`` refuses when
/// ``PaginationState/repeatsCursor(_:)`` is true, and that helper is:

/// ```swift
/// func repeatsCursor(_ cursor: String?) -> Bool {
///   nextCursor == cursor && pageCount > 1
/// }
/// ```
///
/// ``InfiniteQuery/loadMore()`` passes `nextCursor` as `cursor`, so from the
/// second page onward the comparison is `nextCursor == nextCursor`, which is
/// always true. Every infinite query therefore stalls after two pages.
///
/// The guard's *intent* is sound - a server that echoes its own cursor makes the
/// walk loop - so this port keeps an equivalent guard over the whole cursor
/// chain instead of dropping it: ``loadMore``-style walks call
/// ``InfiniteQuery/fetchPage(at:isAppending:)`` directly and refuse a cursor this
/// walk has already requested.
///
/// This is a deliberate deviation from calling `loadMore()`; it is recorded in
/// `tests-ported.md`.
final class CursorWalkGuard: @unchecked Sendable {
  private let lock = NSLock()
  private var requested: Set<String> = []

  /// Records `cursor`, returning true when this walk should request it.
  ///
  /// A nil cursor is the first page, which is always allowed.
  func admit(_ cursor: String?) -> Bool {
    guard let cursor else { return true }
    lock.lock()
    defer { lock.unlock() }
    return requested.insert(cursor).inserted
  }

  /// Clears the walk, for a refresh that starts the chain over.
  func reset() {
    lock.lock()
    defer { lock.unlock() }
    requested.removeAll()
  }
}

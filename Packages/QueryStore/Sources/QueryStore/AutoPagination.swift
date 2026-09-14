import Foundation

/// Schedules the RN `useAutoPagination` behaviour: keep requesting the next page
/// while the visible list is short of the threshold.
extension QueryStore {
  /// The page count cap from the RN hook: `MAX_ATTEMPTS = 5`.
  public static let autoPaginationMaxAttempts = 5

  /// Keeps fetching pages until the list holds at least `wantedItemCount` items,
  /// the list is exhausted, a cursor repeats, or `maxAttempts` pages have been
  /// requested.
  ///
  /// This is the Swift port of `useAutoPagination` in
  /// `src/state/queries/util.ts`. The hook reacts to a rendered item count and
  /// stops once the items on screen would fill the viewport, without ever asking
  /// the appview for more than five extra pages:
  ///
  /// ```
  /// wantedItemCount = pageSize
  /// while hasNextPage && itemCount < wantedItemCount && attempts < MAX_ATTEMPTS:
  ///   fetchNextPage()
  /// ```
  ///
  /// - Parameters:
  ///   - key: infinite query to extend.
  ///   - itemCount: items currently rendered.
  ///   - pageSize: items one page is expected to provide.
  ///   - maxAttempts: request cap. Defaults to
  ///     ``QueryStore/autoPaginationMaxAttempts``.
  /// - Returns: the number of pages requested.
  @discardableResult
  public func autoPaginate(
    _ key: QueryKey,
    itemCount: Int,
    pageSize: Int,
    maxAttempts: Int = QueryStore.autoPaginationMaxAttempts
  ) async -> Int {
    guard maxAttempts > 0 else { return 0 }
    var wanted = max(itemCount, pageSize)
    var attempts = 0
    while attempts < maxAttempts {
      let state = paginationState(for: key)
      guard state.hasNextPage, let cursor = state.nextCursor else { break }
      if state.itemCount >= wanted { break }
      if hasRepeatedCursor(key) { break }
      guard (try? await refetch(key, cursor: cursor, reason: .nextPage)) != nil else { break }
      attempts += 1
      // The threshold only grows once the list has gone past it, which is when
      // the reader has actually scrolled into the newly loaded pages.
      let updated = paginationState(for: key)
      if updated.itemCount > wanted {
        wanted = updated.itemCount + pageSize
      }
    }
    return attempts
  }

  /// Runs ``autoPaginate(_:itemCount:pageSize:maxAttempts:)`` in the background,
  /// cancelling any run already in flight for `key`.
  ///
  /// - Returns: the task, so a caller (or test) can await it.
  @discardableResult
  public func startAutoPagination(
    _ key: QueryKey,
    itemCount: Int,
    pageSize: Int,
    maxAttempts: Int = QueryStore.autoPaginationMaxAttempts
  ) -> Task<Void, Never> {
    cancelAutoPagination(key)
    let task = Task { [weak self] in
      guard let self else { return }
      await self.autoPaginate(
        key,
        itemCount: itemCount,
        pageSize: pageSize,
        maxAttempts: maxAttempts
      )
    }
    autoPaginationTasks[key] = task
    return task
  }

  /// Cancels a background auto-pagination run for `key`.
  public func cancelAutoPagination(_ key: QueryKey) {
    autoPaginationTasks[key]?.cancel()
    autoPaginationTasks[key] = nil
  }
}

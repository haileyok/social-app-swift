import Foundation

/// Fetch scheduling, notification and the store's internal bookkeeping.
///
/// Split out of `QueryStore.swift` to keep each file readable; the members are
/// internal rather than private so the extension can live in its own file.
extension QueryStore {

  // MARK: - Internals: fetch scheduling

  func register<Data: Sendable>(
    _ key: QueryKey,
    plan: FetchPlan,
    fetcher: @escaping @Sendable (QueryFetchRequest) async throws -> Data
  ) {
    let runtime = KeyRuntime(plan: plan, fetcher: { request in try await fetcher(request) })
    runtimes[key] = runtime

    var entry = entries[key] ?? QueryEntry<StoredPayload>.empty(staleTime: plan.staleTime ?? defaultStaleTime)
    if let staleTime = plan.staleTime { entry.staleTime = staleTime }
    entry.isInfinite = entry.isInfinite || plan.isInfinite
    entries[key] = entry
  }

  func shouldStartFetch(key: QueryKey, plan: FetchPlan, request: QueryFetchRequest) -> Bool {
    // A page request is a decision the caller has already made: `loadMore` only
    // runs when the query reported a next cursor. Only first-page fetches are
    // gated on staleness.
    if request.isAppending { return true }
    guard let entry = entries[key] else { return true }
    return entry.needsFetch(
      now: clock.nowMicroseconds(),
      force: plan.force,
      appendingPage: false
    )
  }

  func resolveReason(
    key: QueryKey,
    plan: FetchPlan,
    request: QueryFetchRequest
  ) -> QueryFetchReason {
    if let reason = plan.reason { return reason }
    if request.isAppending { return .nextPage }
    guard let entry = entries[key], entry.hasData else { return .initial }
    return entry.isInvalidated ? .invalidated : .stale
  }

  @discardableResult
  func startFetch(
    key: QueryKey,
    plan: FetchPlan,
    request: QueryFetchRequest,
    reason: QueryFetchReason
  ) async throws -> any Sendable {
    if let existing = inFlight[key] { return try await existing.value }
    guard let runtime = runtimes[key] else {
      throw QueryTypeMismatchError(key: key, expected: "a registered fetcher")
    }

    var entry = entries[key] ?? QueryEntry<StoredPayload>.empty(staleTime: defaultStaleTime)
    entry.staleTime = plan.staleTime ?? entry.staleTime
    entry.isFetching = true
    entry.fetchStartedAt = clock.nowMicroseconds()
    entry.isInfinite = entry.isInfinite || plan.isInfinite
    entry.status = entry.hasData ? .success : .loading
    entries[key] = entry
    notify(event: .fetchStarted(key: key, reason: reason))

    let fetcher = runtime.fetcher
    let work = Task<any Sendable, any Error> { [weak self] in
      do {
        let payload = try await fetcher(request)
        await self?.completeFetch(key: key, payload: payload, plan: plan, request: request)
        return payload
      } catch {
        await self?.failFetch(key: key, error: error)
        throw error
      }
    }
    inFlight[key] = work
    return try await work.value
  }

  func completeFetch(
    key: QueryKey,
    payload: any Sendable,
    plan: FetchPlan,
    request: QueryFetchRequest
  ) {
    inFlight[key] = nil
    guard var entry = entries[key] else { return }
    entry.status = .success
    entry.error = nil
    entry.failureCount = 0
    entry.fetchedAt = clock.nowMicroseconds()
    entry.isFetching = false
    entry.isInvalidated = false
    entry.isInfinite = entry.isInfinite || plan.isInfinite

    var stored = StoredPayload.decoded(payload)
    var refused = false
    if request.isAppending, let existing = entry.data, let merge = plan.merge {
      // A nil result means the reducer refused the page; the descriptor is
      // dropped with it so pagination state cannot outrun the payload.
      if let merged = merge(existing, payload, pageChains[key]?.pages ?? []) {
        stored = merged
      } else {
        refused = true
      }
    }
    entry.data = stored
    entries[key] = entry

    // A page merge can drop items, so the descriptor is derived from the payload
    // actually stored rather than from the response.
    let finalPayload = stored.erasedValue ?? payload
    let descriptor = refused ? nil : plan.describe?(finalPayload, request)

    if let descriptor {
      applyDescriptor(key: key, descriptor: descriptor, request: request)
    }
    // Subscribers and observers see the merged payload, not the bare response:
    // an infinite query's listeners want the whole list.
    notify(event: .fetchSucceeded(key: key, payload: finalPayload))
    notifySubscribers(key: key, payload: finalPayload)
    if plan.persist { schedulePersist() }
  }

  func applyDescriptor(
    key: QueryKey,
    descriptor: PageDescriptor,
    request: QueryFetchRequest
  ) {
    var chain = pageChains[key] ?? PageChain()
    // A non-appending request loads page one, so the chain restarts there.
    // Otherwise the payload has been replaced by a single page while the chain
    // still describes the old walk.
    if request.isAppending && !chain.pages.isEmpty {
      chain.pages.append(descriptor)
    } else {
      chain.pages = [descriptor]
    }
    pageChains[key] = chain
  }

  func failFetch(key: QueryKey, error: any Error) {
    inFlight[key] = nil
    guard var entry = entries[key] else { return }
    entry.isFetching = false
    entry.error = error
    entry.failureCount += 1
    entry.status = .error
    entries[key] = entry
    notify(event: .fetchFailed(key: key, error: error, hadData: entry.hasData))
  }

  // MARK: - Internals: subscribers and events

  func notify(event: QueryEvent) {
    for observer in eventObservers.values { observer(event) }
  }

  func notifySubscribers(key: QueryKey, payload: (any Sendable)?) {
    guard let subscribers = keySubscribers[key], let payload else { return }
    for subscriber in subscribers.values { subscriber(payload) }
  }

  func removeSubscriber(key: QueryKey, id: UUID) {
    keySubscribers[key]?[id] = nil
    if keySubscribers[key]?.isEmpty == true { keySubscribers[key] = nil }
  }

  func removeObserver(id: UUID) {
    eventObservers[id] = nil
  }
}

# QueryStore

A typed, Linux-clean data layer for the Swift Bluesky app, replicating the
semantics of the RN app's TanStack Query usage (`~/bluesky/social-app/src/state/queries`).

No SwiftUI, no UIKit, no Observation. Everything is an actor plus closure
subscribers, so the package stays inside the Linux-verifiable boundary defined in
`AGENTS.md`.

## Shape

```swift
let store = QueryStore()                       // one per account, as the RN app does per DID

// A single-shot query.
let key = QueryKey("profile", ProfileArgs(did: "did:plc:alice"))
let profile = try await store.fetch(key) {
  try await client.getProfile(did: "did:plc:alice")
}

// A paginated query.
let feed = InfiniteQuery(
  store: store,
  key: QueryKey("feed", FeedArgs(feed: "discover", limit: 30)),
  identity: { $0.uri },
  page: { cursor in
    let page = try await client.discoverFeed(cursor: cursor, limit: 30)
    return QueryPage(items: page.posts, cursor: page.cursor)
  })

_ = try await feed.loadFirstPage()
_ = try await feed.loadMore()
await feed.autoPaginate(itemCount: 12, pageSize: 30)   // fills a short viewport, capped at 5 pages
await feed.subscribeItems { items in render(items) }   // closure subscriber, no Observation
```

## Files

| File | Contents |
|---|---|
| `QueryKey.swift` | `QueryArgs`, `QueryOptions`, `QueryKey` (description-based identity) |
| `Stale.swift` | `STALE`, `GCTIME` ported from `src/state/queries/index.ts` |
| `QueryTypes.swift` | `QueryStatus`, `QueryEvent`, `QueryFetchRequest`, `QuerySubscription`, errors |
| `QueryEntry.swift` | `QueryEntry<Data>`, `QueryEntrySnapshot`, `QueryClock` |
| `QueryPayload.swift` | `StoredPayload` erasure, `Persistable`, `QueryPayload` |
| `InfiniteQueryData.swift` | `QueryPage`, `InfiniteQueryData`, `PageMergePolicy` |
| `FetchPlan.swift` | `FetchPlan`, `PageDescriptor`, `KeyRuntime`, `PageChain`, `PaginationState` |
| `QueryStore.swift` | the actor's storage, reads, fetch, writes, invalidation, persistence, observation |
| `QueryStoreInternals.swift` | fetch scheduling, notification, subscriber bookkeeping |
| `QueryStorePersistence.swift` | snapshot composition and restore |
| `InfiniteQuery.swift` | the typed infinite-query wrapper |
| `AutoPagination.swift` | `useAutoPagination` semantics |
| `Persistence.swift` | `PersistedSnapshot`, `PersistedQuery`, `QueryPersistSink` |

## Two design notes

**Key identity is description-based.** `QueryKey` hashes the rendered description
of its args rather than an erased `AnyHashable`. That is what lets a key be
rebuilt from a persisted snapshot and still compare equal to the live, strongly
typed key. The tradeoff is that two argument types rendering identical text would
collide, so `QueryArgs` conformers should render distinctly - the compiler's
synthesised `String(describing:)` does.

**The store never decodes its own payloads.** Entries hold an erased
`StoredPayload`, and the typed logic the store needs (page merge, page
description) is supplied by the caller as a `FetchPlan`. That is what allows a
restored entry to be decoded lazily, on the first read that asks for a type.

## Tests

`swift test` runs 76 tests across five suites. `tests-ported.md` maps each RN
semantic and source location to the Swift test that pins it.

```bash
swift build && swift test
```

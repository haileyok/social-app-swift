# tests-ported.md - QueryStore

`QueryStore` is a port of the RN app's TanStack Query usage rather than of a single
TS test file, so this manifest maps **RN semantics** (and their source) to named
Swift tests. Every entry names the file and test that pins the behaviour.

## Query keys and staleness

| RN source | Semantics | Swift test |
|---|---|---|
| `src/state/queries/util.ts` `createQueryKey` | root + args object forms a key; different args are different entries | `QueryKeyTests.identityFromRootAndArgs` |
| `src/state/queries/util.ts` `createQueryKey` options | `persistedVersion` participates in identity, so bumping it busts the entry | `QueryKeyTests.persistedVersionIsPartOfIdentity` |
| `src/lib/react-query.tsx` `QueryProvider currentDid` | cache is scoped per account; scope is part of the key | `QueryKeyTests.scopeIsPartOfIdentity`, `QueryStoreTests.perScopeIsolation`, `PersistenceTests.restoreIsScoped` |
| `src/state/queries/util.ts` `StructuredQueryKey` | `[root, args, options]` renders a stable debug identity | `QueryKeyTests.debugDescription` |
| `src/state/queries/index.ts` `STALE` | `SECONDS.FIFTEEN` through `INFINITY` | `QueryKeyTests.staleConstants` |
| `src/state/queries/index.ts` `GCTIME` | `GCTIME.INFINITY` is non-finite | `QueryKeyTests.gctimeInfinity` |
| TanStack `staleTime: Infinity` | an `INFINITY` entry never stales on its own | `QueryKeyTests.infinityNeverStales` |

## Store fetch semantics

| RN source | Semantics | Swift test |
|---|---|---|
| TanStack `useQuery` | first fetch populates and stamps `fetchedAt` | `QueryStoreTests.firstFetch` |
| TanStack `staleTime` | a fresh entry is served from cache without a request | `QueryStoreTests.freshEntryIsNotRefetched` |
| TanStack refetch-on-stale | stale data refetches, and the old value stays readable meanwhile | `QueryStoreTests.staleRefetch` |
| TanStack `refetch` | `force` refetches inside the stale window | `QueryStoreTests.forceRefetch` |
| per-query `staleTime` option (as in `feed.ts`) | a per-key override beats the store default and is remembered | `QueryStoreTests.perKeyStaleTimeOverride` |
| TanStack in-flight dedupe | concurrent fetches for one key share a single request | `QueryStoreTests.inFlightDedupe`, `dedupeIsPerKey`, `joinsInFlightInsteadOfQueueing` |
| `queryClient.invalidateQueries` | invalidation keeps data and refetches in the background | `QueryStoreTests.invalidationPreservesData` |
| `queryClient.invalidateQueries({refetchType: 'none'})` | invalidation without refetch only marks stale | `QueryStoreTests.invalidateWithoutRefetch` |
| `invalidateQueries` with a key root | root invalidation covers matching keys only | `QueryStoreTests.invalidateByRoot` |
| TanStack `setQueryData` | direct writes are marked fresh and notify | `QueryStoreTests.setQueryData`, `updateQueryData` |
| RN onError rollback | optimistic write + snapshot rollback on failure | `QueryStoreTests.optimisticUpdateAndRollback` |
| TanStack error state | an error is kept until a successful refetch clears it | `QueryStoreTests.errorPreservedUntilSuccess`, `failureEventReportsPreservedData`, `failedFirstFetch` |
| `src/state/queries/util.ts` `truncateAndInvalidate` | drop back to one page, then invalidate | `QueryStoreTests.truncateAndInvalidate` |
| TanStack observer model | subscribers get the current value then each change; cancel detaches | `QueryStoreTests.subscribeReceivesPayloads`, `subscribersSeeFetchCompletion` |
| `queryClient.clear()` on sign-out | `removeAll` / `remove` clear entries | `QueryStoreTests.removeAll`, `removeKey` |

## Infinite queries

| RN source | Semantics | Swift test |
|---|---|---|
| `useInfiniteQuery` `initialPageParam` | the first page is requested with no cursor | `InfiniteQueryTests.loadFirstPage` |
| `getNextPageParam: lastPage => lastPage.cursor` | `loadMore` walks the reported cursor | `InfiniteQueryTests.loadMoreUsesReportedCursor` |
| `InfiniteData.pages` | pages concatenate in request order | `InfiniteQueryTests.loadMoreAppendsInOrder`, `flattenedItemsAccessor` |
| `InfiniteData` end of list | a terminal page makes `loadMore` a no-op, not an error | `InfiniteQueryTests.loadMoreOnExhaustedList` |
| dedupe-on-merge (feed overlap) | duplicate items across pages collapse to the earlier copy | `InfiniteQueryTests.dedupeOnMerge`, `fullyDuplicatePageAdvancesCursor` |
| page reducer refusal | a refused merge drops the descriptor with the payload | `InfiniteQueryTests.refusedPageDoesNotCorruptPagination` |
| `truncateAndInvalidate` + reload | `refresh` restarts from a single fresh head | `InfiniteQueryTests.refreshTruncatesAndReloads` |
| `select`-style list rewrite | `updateItems` rewrites the flattened list | `InfiniteQueryTests.updateItems` |
| `useInfiniteQuery` observer | subscribers receive flattened items | `InfiniteQueryTests.subscribeItems` |
| `InfiniteData.pageParams` | cursor bookkeeping (repeat detection, truncation) | `InfiniteQueryTests.infiniteDataHelpers` |

## Auto-pagination

| RN source | Semantics | Swift test |
|---|---|---|
| `src/state/queries/util.ts` `MAX_ATTEMPTS = 5` | the constant is five | `AutoPaginationTests.maxAttemptsConstant` |
| `useAutoPagination` effect | keep fetching until the threshold is met, capped at `MAX_ATTEMPTS` | `AutoPaginationTests.stopsAtBound`, `stopsWhenSatisfied` |
| `useAutoPagination` early exit | nothing happens when the list already satisfies the threshold | `AutoPaginationTests.noOpWhenSatisfied` |
| `useAutoPagination` `hasNextPage` | the walk ends at the end of a finite list | `AutoPaginationTests.stopsAtEndOfList` |
| `useAutoPagination` `repeatedCursor` guard | a cursor that repeats stops the walk | `AutoPaginationTests.stopsOnRepeatedCursor` |
| `useAutoPagination` scope | non-infinite queries are untouched | `AutoPaginationTests.noOpForSingleShotKey` |
| `useAutoPagination` async form | the background variant performs the same walk | `AutoPaginationTests.backgroundVariation`, `zeroAttempts` |
| error during the walk | a failed page ends the walk and preserves prior pages | `AutoPaginationTests.failingPageEndsWalk` |
| overlap during the walk | de-duplication still applies on auto-paginated pages | `AutoPaginationTests.dedupeStillApplies` |

## Persistence

| RN source | Semantics | Swift test |
|---|---|---|
| `src/lib/react-query.tsx` `dehydrateOptions` | only persisted-versioned successful queries are written | `PersistenceTests.persistWritesSnapshot`, `unversionedEntriesAreNotPersisted`, `failedEntriesAreNotPersisted` |
| `createPersistedQueryStorage` | one snapshot per scope, defaulting to `logged-out` | `PersistenceTests.perScopeSnapshots`, `loggedOutScopeName` |
| persister round trip | a snapshot restores into a fresh store as typed data | `PersistenceTests.roundTrip`, `restoredEntryKeepsTimestamp` |
| restored staleness | a restored entry is still subject to its stale time and refetches | `PersistenceTests.restoredEntryRefetchesWhenStale`, `restoredEntryKeepsStaleTime` |
| `buster: env.APP_VERSION` | a buster mismatch discards the whole snapshot | `PersistenceTests.busterMismatchDiscardsSnapshot` |
| per-key `persistedVersion` | an entry written at another version is dropped for the live key | `PersistenceTests.persistedVersionBust` |
| snapshot keying | snapshots match on root, scope, version and args, so args cannot collide | `PersistenceTests.restoreMatchesOnArgs` |
| restore notification | restoring emits a `restored` event | `PersistenceTests.restoreEmitsEvent` |
| sign-out | `signOut` clears memory and persisted state | `PersistenceTests.signOutClearsPersistedState` |
| no persister | a store with no sink still caches | `PersistenceTests.noSinkIsNoOp` |

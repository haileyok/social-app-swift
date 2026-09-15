# Search — ported test manifest

Maps the RN source this package ports to the Swift tests that cover it.
Source repo: `~/bluesky/social-app` (read-only reference); paths below are
relative to its `src/`. Swift tests use Swift Testing (`import Testing`).

This package is `SearchLogic` in `Packages/Features/Search` (product
`SearchLogic`, Linux-verified). It is logic-only: no SwiftUI/UIKit/Observation,
`defaultIsolation: nonisolated`.

## Directly ported unit tests

| RN test file | Ports | Swift suite / tests |
|---|---|---|
| `state/queries/__tests__/search-posts-params.test.ts` (21 cases) | `extractSearchPostsParams` token/operator table (incl. CJK rows, `from:me`, quoted phrases, OR groups, hashtags) | `SearchQueryParamsExtractTests.extractTable` (21 table rows) |
| same | `extractFromMe` / `appendFromMe` | `SearchQueryParamsFromMeTests.*` (6 tests) |
| same | `buildSearchPostsV2Filters` merging, dedupe, scalar preference, timestamp normalization, exclude pass-through | `SearchPostsV2FiltersTests.*` (9 tests) |
| `screens/Search/__tests__/searchParams.test.ts` (21 cases) | `readSearchFilters`, `hasPostOnlyFilters`, `hasActiveFilters`, `definedFilterParams`, `withoutFilterParams`, `filtersToApiParams`, `countActiveFilters` | `SearchFiltersTests.*` (11 tests) |
| same | `serializeHistoryEntry` / `parseHistoryEntry` (plain string, JSON, legacy, malformed, JSON-without-`q`) | `SearchHistoryCodingTests.*` (7 tests) |

## Behaviors ported from hooks/screens (no RN unit test existed)

The RN counterparts live in `useMemo`/`useEffect`/hook bodies, so there is no TS
test to port 1:1. These Swift tests encode the same semantics.

| RN source | Behavior | Swift suite / tests |
|---|---|---|
| `state/queries/actor-search.ts` | `searchActors{RQKEY, limit 25, STALE.MINUTES.FIVE}`, DID de-dupe across pages | `SearchEndpointsTests.actorSearch`, `SearchFetchersTests.actorSearch*`, `SearchQueriesIntegrationTests.actorSearchPagination` |
| `state/queries/actor-autocomplete.ts` | lowercase+trim+strip trailing dot; empty prefix never fetches; handle de-dupe; exact-match/hideable-offense/mute inclusion rule | `ActorAutocompleteTests.*` (8 tests) |
| `state/queries/search-posts-v2.ts` | v2 param set incl. `allTime: true`, `latest -> recent`, `appendFromMe`, 25 limit | `SearchFetchersTests.postSearchV2*`, `SearchEndpointsTests.postSearchV2`, `SearchQueriesIntegrationTests.postSearchPagination` |
| `state/queries/starter-pack-search.ts` | `searchStarterPacksV2` params + URI de-dupe | `SearchFetchersTests.starterPackSearch`, `SearchEndpointsTests.starterPackSearch` |
| `state/queries/trending/useGetTrendsQuery.ts` | `getTrends` fetchLimit 20, dedupe by `link`, muted-word filter on `topic + displayName + category`, slice to display limit (5) | `TrendingTests.*` (4 tests), `SearchEndpointsTests.trends`, `SearchFetchersTests.trends` |
| `state/queries/trending/useGetSuggestedUsersForExploreQuery.ts` | `getSuggestedUsersForExplore` params (category, limit 10), `recIdStr -> recId` | `SearchEndpointsTests.suggestedUsers`, `SearchFetchersTests.suggestedUsers*`, `ExploreAssemblyTests.recIdOnPage` |
| `state/queries/trending/useGetSuggestedFeedsQuery.ts` | `getSuggestedFeeds` limit 15, drop already-saved feeds (delegated to caller), headers | `SearchEndpointsTests.suggestedFeeds`, `SearchFetchersTests.suggestedFeeds` |
| `state/queries/useSuggestedStarterPacksQuery.ts` | `getSuggestedStarterPacks` (no params; `interests` in the key) | `SearchEndpointsTests.suggestedStarterPacks`, `SearchFetchersTests.suggestedStarterPacks`, `SearchQueryKeysTests.suggestedStarterPacksKey` |
| `state/queries/feed.ts` (`getPopularFeedGenerators`) | popular feeds params (limit 10, cursor), key `['getPopularFeeds', limit]` | `SearchEndpointsTests.popularFeeds`, `SearchFetchersTests.popularFeeds`, `ExploreAssemblyTests.popularFeedsFallback` |
| `screens/Search/Explore.tsx` (module `useMemo` blocks) | section order; suggested-accounts dedupe/follow-drop/For-You-5; feeds 6 + load-more; starter-pack section dropped on error; reduced-experience ordering | `ExploreAssemblyTests.*` (17 tests) |
| `screens/Search/Shell.tsx` (history callbacks) | MRU prepend, dedupe on serialized form, term cap 6, account cap 10, remove/clear | `SearchHistoryTests.*` (13 tests) |
| `screens/Search/Shell.tsx` (`useStorage` wiring) | account-scoped persistence of `searchTermHistory` / `searchAccountHistory` | `PersistedSearchHistorySinkTests.*` (2 tests) |
| `state/queries/pds-detection.ts` / handle-availability `useDebouncedValue` (500 ms) | debounce-before-fetch, keystroke cancels pending request, stale response discarded, submit/reset cancellation | `SearchStateMachineTests.*` (12 tests) |

## Swift-only tests (no RN analogue)

- `SearchEndpointsTests.uniqueness` / `forRoot` — the endpoint table's own invariants.
- `SearchQueryKeysTests.*` — key roots, scoping, `persistedVersion`, sort translation.
- `SearchFetchersTests.encodeV2NoDuplicateParams` — regression: `encodeV2` must
  emit each param name once (a duplicate `since` crashed the suite before the fix).
- `SearchQueriesIntegrationTests.cachingDedupes` / `scopingSeparatesAccounts` —
  `QueryStore` cache behavior over the search keys.
- `CleanErrorTests.*` — `cleanError` fallback copy.

## Deviations recorded

1. **`recIdStr` is not merged into the payload.** The RN hooks use TanStack's
   `select` to return `{...data, recId}`. This port keeps the lexicon output
   intact (so it stays `Codable`-round-trippable for persistence) and surfaces
   the id as ``ExploreRecommendedProfile/recId`` / ``ExplorePageData/recId`` /
   ``Trending/Trends/recId`` at the assembly layer.
2. **Moderation is injected, not computed.** `ActorAutocomplete` takes a
   `ModerationVerdict` closure rather than depending on `Moderation`; the
   inclusion logic itself is ported verbatim.
3. **Explore assembly covers data-bearing rows only.** The RN `ExploreScreenItems`
   union also contains purely presentational rows (borders, banners,
   placeholders, the interests card) that have no data dependency; those stay in
   the Views package.
4. **Network call surface.** The RN `AppView`/`useAppviewClient` layer is
   represented by the `SearchXRPCCalling` protocol (`XrpcClient` conforms). The
   param encoding is asserted through `FakeSearchClient` rather than a live
   transport.
5. **In-package test fakes over `TestSupport`.** `TestSupport` is a placeholder
   in this repo, so the fakes (`FakeSearchClient`, `InMemorySearchHistorySink`)
   live in the test target.

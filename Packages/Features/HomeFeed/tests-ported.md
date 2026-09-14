# HomeFeed — tests-ported.md

Manifest mapping the RN reference material this package ports to the Swift tests
that pin the behaviour, per the repo convention (`AGENTS.md`, "Testing
philosophy": each feature package keeps a manifest mapping TS test cases to named
Swift tests).

Reference repo: `~/bluesky/social-app` (read-only), at commit `ff10dbd35`.

There is no upstream `*.test.ts` for the feed pipeline, so this is a
*behaviour* manifest: each row names the RN source of a behaviour and the Swift
tests that assert it. Where a behaviour has no upstream test, the row is marked
`—`.

## XRPC surface

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `src/state/queries/post-feed.ts` (`FollowingFeedAPI` / `lib/api/feed/following.ts`) | following feed reads `app.bsky.feed.getTimeline` with `cursor` + `limit` | `FeedXrpcCallTests.timelineParams`, `.timelineRouting` |
| `src/lib/api/feed/custom.ts` (`CustomFeedAPI.fetch`) | custom feed reads `app.bsky.feed.getFeed` with `feed`, `cursor`, `limit` | `FeedXrpcCallTests.customFeedParams` |
| `src/lib/api/feed/custom.ts` | `Accept-Language` always; `X-Bsky-Topics` only for Bluesky-owned feeds and only when authenticated | `FeedXrpcCallTests.customFeedHeaders`, `FeedRequestHeaderTests.blueskyOwnedGetsTopics`, `.thirdPartyHasNoTopics`, `.loggedOutHasNoTopics`, `.contentLanguagesJoin`, `.ownerList` |
| `src/lib/api/feed/custom.ts` (`-prf` note) | some generators ignore the limit, so the page is truncated to `limit` | `CustomFeedFetcherTests.truncatesOverlongPage` |
| `src/lib/api/feed/custom.ts` (`peekLatest`) | peeking asks for `limit: 1` and no cursor | `CustomFeedFetcherTests.peekLatestSingle` |
| `app.bsky.feed.getFeedSkeleton` (feed-generator protocol) | skeleton read precedes hydration | `CustomFeedFetcherTests.skeletonThenHydrate` |
| `app.bsky.feed.getPosts` | hydration preserves skeleton order, carries `feedContext`/`reqId`, drops unresolvable posts, batches | `CustomFeedFetcherTests.skeletonOrderAndDrops`, `.skeletonContextCarried`, `.hydrationBatching`, `.batchSplitting` |
| `src/lib/api/feed/list.ts` (`ListFeedAPI`) | list feed reads `app.bsky.feed.getListFeed` | `ListFeedFetcherTests.listFeedParams` |
| `src/state/queries/feed.ts` (`usePinnedFeedsInfos`) | batch `getFeedGenerators`; per-list `getList` with `limit: 1` | `PinnedFeedsTests.generatorBatch`, `.listReadsIndividual`, `FeedXrpcCallTests.listLimit`, `.generatorsBatchParam` |
| `src/state/queries/feed.ts` (`useFeedInfo`) | `app.bsky.feed.getFeedGenerator` read | `FeedXrpcCallTests.generatorAndActorFeeds` |
| `src/state/queries/profile-feedgens.ts` | `app.bsky.feed.getActorFeeds` read | `FeedXrpcCallTests.generatorAndActorFeeds` |
| `app.bsky.unspecced.getConfig` (feed config/gating) | config read | `FeedXrpcCallTests.configEndpoint` |
| `src/state/session` client bundle | proxy routing + labelers + auth are emitted by the shared appview client | `FeedXrpcCallTests.timelineRouting`, `.customFeedHeaders`, `.loggedOutClientHasNoProxy` |

## Query keys

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `post-feed.ts` (`RQKEY_ROOT = 'post-feed'`, `RQKEY`) | feed key root and descriptor identity | `HomeFeedKeyTests.feedKeyRoot`, `.descriptorDistinctness`, `.mergeFlagParticipates` |
| `feed.ts` (`createPinnedFeedInfosQueryKey`) | `feed-info` root, `persistedVersion: 1`, `kind` + `feedUris` identity | `HomeFeedKeyTests.feedInfoPersistedVersion`, `.feedInfoIdentity` |
| `feed.ts` (`feedSourceInfoQueryKey`, `feedInfoQueryKeyRoot`) | source-info and generator key roots | `HomeFeedKeyTests.roots` |
| post-feed provider re-keying on `currentDid` | account scope separates entries | `HomeFeedKeyTests.scopeSeparatesAccounts` |
| `post-feed.ts` (`FeedDescriptor`) | descriptor string round-trip | `FeedDescriptorTests.rendering`, `.parsing`, `.foreignDescriptors` |

## Feed pipeline (fetch → tune → slice)

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `src/lib/api/feed-manip.ts` (`createFeedViewPostsSlices`) | a plain page yields one slice per post | `HomeFeedPipelineTests.plainPageSlices` |
| `src/lib/api/feed-manip.ts` | a reply slice carries root, parent, then the selected post | `HomeFeedPipelineTests.replyChainOrdering` |
| `src/state/queries/post-feed.ts` (`feedContext`, `reqId`, `reason` on `FeedPostSlice`) | feed metadata survives tuning | `HomeFeedPipelineTests.feedContextPreserved`, `.reasonPreserved` |
| `src/state/preferences/feed-tuners.tsx` (`useFeedTuners`) | following/list stack composition and preference gates | `HomeFeedPipelineTests.followingTunerStack`, `.followingPreferenceFilters`, `.hideRepliesReplacesFollowedReplies`, `.feedgenTunerStack` |
| `feed-manip.ts` (`FeedTuner.preferredLangOnly`) | language filter drops non-matching slices but never empties a page | `HomeFeedPipelineTests.languageFilterDrops`, `.languageFilterKeepsSomething` |
| `feed-manip.ts` (`FeedTuner` seen-set dedupe) | cross-page de-duplication by URI | `HomeFeedPipelineTests.crossPageDeduplication` |
| `feed-manip.ts` (`FeedTuner.dedupThreads`, `followedRepliesOnly`) | thread-root dedupe for following; replies only from self/followed | `HomeFeedPipelineTests.dedupThreadsPerDescriptor`, `.followedRepliesOnlyDrops`, `.followedRepliesKept` |

## Pagination

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `post-feed.ts` (`getNextPageParam: lastPage => lastPage.cursor`) | cursor walk and terminal page | `HomeFeedPaginationTests.firstPageRequest`, `.cursorWalk`, `.terminalPageStops`, `.pagesAccumulate` |
| `post-feed.ts` / `QueryStore` repeated-cursor guard | a repeated cursor is refused rather than looping | `HomeFeedPaginationTests.repeatedCursorRefused` |
| `src/state/queries/util.ts` (`truncateAndInvalidate`) | refresh returns to a single fresh head with one request | `HomeFeedPaginationTests.refreshTruncates` |
| `src/state/queries/util.ts` (`useAutoPagination`, `MAX_ATTEMPTS = 5`) | auto-pagination fills to the threshold, capped at five extra pages, stops early when full | `HomeFeedPaginationTests.autoPagination`, `.autoPaginationStopsWhenFull` |
| `post-feed.ts` (`MIN_POSTS = 30`, `fetchLimit`) | page size and threshold constants | `HomeFeedPipelineTests.plainPageSlices` (limit asserted in `HomeFeedPaginationTests.firstPageRequest`), `NewPostsPollerTests.pollConstants` |

## New-posts / poll

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `view/com/posts/PostFeed.tsx` (`checkForNew`) | no first page / disabled / fetching / disablePoll -> no-op | `NewPostsPollerTests.idleWithoutData`, `.disabled` |
| `PostFeed.tsx` (`checkForNew`) | new content on a populated feed -> pill | `NewPostsPollerTests.showsPill` |
| `PostFeed.tsx` (`checkForNew` + `isEmpty`) | new content on an empty feed -> refetch | `NewPostsPollerTests.refetchWhenEmpty` |
| `PostFeed.tsx` | Discover always reports new without polling | `NewPostsPollerTests.discoverAlwaysNew` |
| `post-feed.ts` (`pollLatest`) | peek failure is swallowed and surfaced to the caller's handler | `NewPostsPollerTests.networkFailureSwallowed` |
| `post-feed.ts` (`pollLatest` dry-run) | the dry run does not consume tuner seen-state | `NewPostsPollerTests.dryRunDoesNotMutateTuner` |
| `PostFeed.tsx` (`CHECK_LATEST_AFTER = STALE.SECONDS.THIRTY`) | on-focus check runs when empty or older than 30s | `NewPostsPollerTests.emptyChecksOnFocus`, `.freshFeedSkipsFocusCheck`, `.focusCheckDisabled`, `.pollConstants` |
| `screens/CustomFeed/index.tsx`, `screens/ProfileList/FeedSection.tsx` (`pollInterval={60e3}`) | 60s timer constant | `NewPostsPollerTests.pollConstants` |

## Pinned / saved feeds and state derivation

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `feed.ts` (`usePinnedFeedsInfos`) | stored order wins over wire order | `PinnedFeedsTests.storedOrderWins` |
| `feed.ts` (`usePinnedFeedsInfos`) | timeline needs no resolution and keeps its slot | `PinnedFeedsTests.timelinePosition` |
| `feed.ts` (`await feedsPromise`) | a failing generator batch fails the whole resolution | `PinnedFeedsTests.generatorFailureFailsAll` |
| `feed.ts` (`Promise.allSettled(listsPromises)`) | a failing list read is ignored | `PinnedFeedsTests.listFailureIgnored` |
| `feed.ts` (stale-time table) | pinned resolution is cached at `STALE.MINUTES.FIFTEEN` | `PinnedFeedsTests.resolutionCaching` |
| `feed.ts` (`usePinnedFeedsInfos`, aligned-out branch) | unresolvable generators are dropped, the rest survive | `PinnedFeedsTests.partialGeneratorResolution` |
| `feed.ts` (`PWI_DISCOVER_FEED_STUB`) | a logged-out reader receives the Discover stub with no requests | `PinnedFeedsTests.loggedOutStub` |
| `feed.ts` (`hydrateFeedGenerator` display-name fallback) | nameless generator -> `Feed by @handle` | `PinnedFeedsTests.displayNameFallback` |
| `state/queries/preferences` (savedFeeds v2 read) | entries keep stored order; pinned filter | `SavedFeedReaderTests.storedOrder`, `.pinnedFilter` |
| `state/queries/feed.ts` (`getFeedTypeFromUri`) | a missing `type` is inferred from the URI | `SavedFeedReaderTests.typeInferred` |
| `state/queries/preferences` (`validateSavedFeed`) | a saved feed without an id is rejected | `SavedFeedReaderTests.malformedDropped` |
| `view/screens/Home.tsx` (`hasSession` / `pinnedFeedInfos.length`) | logged-out / loading / add-first-feed / feeds presentation | `HomeFeedModelTests.loggedOut`, `.noFeedsPinned`, `.loadingPreferences`, `.feedsPresentation` |
| `view/screens/Home.tsx` (`useSelectedFeed`, clamped index) | first pinned feed selected; unknown selection ignored | `HomeFeedModelTests.defaultSelection`, `.selectionSwitch`, `.unknownSelectionIgnored` |
| `view/screens/Home.tsx` (`allFeeds` + per-page query) | one query instance per pinned descriptor | `HomeFeedModelTests.perFeedQueries` |
| `view/com/posts/PostFeed.tsx` (`isEmpty`, `isError`, `isFetching` branch order) | page-state derivation | `HomeFeedModelTests.pageStateDerivation`, `.pageStateContent`, `.pageStateEmpty`, `.pageStateError` |
| `view/com/posts/PostFeedErrorMessage.tsx` + `lib/strings/errors.ts` (`isNetworkError`, `KnownError`) | error classification (network / service / signed-in-only) | `HomeFeedModelTests.networkClassification`, `.serviceClassification` |

## Deliberate deviations

1. **Tuning location.** RN derives slices inside TanStack's `select` on every
   render; `QueryStore` has no `select`, so each page is tuned once inside the
   page fetcher, with the tuner's cross-page state in scope. Equivalent per page,
   and it is what RN's own `tuner.tune(page.feed)` does.
2. **Auto-pagination threshold.** RN sums `slice.items.length` (posts), while
   `QueryStore.autoPaginate` compares item count against the page size. The store
   payload is one slice per item, so the two agree except on thread-heavy pages,
   where this port fills slightly less per pass. Covered by
   `HomeFeedPaginationTests.autoPagination*`.
3. **Skeleton→hydrate.** The current RN snapshot reads custom feeds through
   `getFeed` (appview-side hydration) and has no client skeleton step. Both paths
   are provided: ``CustomFeedFetcher`` mirrors the snapshot exactly, and
   ``SkeletonHydratingFetcher`` implements the classic
   `getFeedSkeleton` → `getPosts` flow.
4. **Skeleton reasons.** A skeleton's `reason` carries only a repost record URI,
   while a hydrated `feedViewPost`'s `reasonRepost` needs `by` and `indexedAt`.
   No reason is fabricated on the skeleton path; attribution comes from the
   appview path.
5. **Moderation.** `post-feed.ts` filters slices through `moderatePost` and
   asserts logged-out content passes moderation. Neither is ported: moderation is
   a Views-layer concern and the Logic package has no moderation dependency. The
   `HomeFeedError.signedInOnly` case exists so the Views layer can still render
   RN's `KnownError.FeedSignedInOnly` branch.
6. **Merge feed.** `FeedParams.mergeFeedEnabled` participates in the query key
   (as RN's params do) but the `MergeFeedAPI` multi-source merger is not ported;
   only the timeline, generator and list fetchers exist.

# PostThread — ported test manifest

Maps the RN source this package ports to the Swift tests that cover it.
Source repo: `~/bluesky/social-app` (read-only reference); paths below are
relative to its `src/`. Swift tests use Swift Testing (`import Testing`).

## Scope note: two RN implementations

The RN app has had two post-thread implementations, and this package ports
both, deliberately:

1. **The tree query** — `state/queries/post-thread.ts`, removed from RN main in
   commit `0b50e9f10`. It called `app.bsky.feed.getPostThread` with
   `depth: REPLY_TREE_DEPTH` (10) and no `parentHeight`, parsed the
   `threadViewPost` tree into `ThreadNode`s, and flattened it in the screen
   (`view/com/post-thread/PostThread.tsx`) into `parents + highlightedPost +
   replies`. The task names this endpoint, and its `depth`/`parentHeight`
   params, so this is the package's primary path.
2. **The flat query** — `state/queries/usePostThread/*`, current RN main. It
   calls `app.bsky.unspecced.getPostThreadV2` (a flat `ThreadItem[]`) and
   annotates it in `sortAndAnnotateThreadItems`. Its *semantics* — connector
   state, moderation bucketing, read-more rows — are ported even where the wire
   shape differs, because that is the current product behaviour.

Where the two disagree the newer semantics win for the annotation rules, and the
older endpoint's params win for the request. Deviations are listed at the end.

## Ported behaviour

| RN source | RN behaviour / test | Swift test |
|---|---|---|
| `state/queries/post-thread.ts` (`usePostThreadQuery`) | `REPLY_TREE_DEPTH = 10`, no `parentHeight` | `ListTests.defaultParams` |
| `state/queries/post-thread.ts` (`usePostThreadQuery`) | the request carries `uri`, `depth`, `parentHeight` | `ListTests.threadFetchParams`, `ListTests.threadDecode` |
| `state/queries/post-thread.ts` (`responseToThreadNodes`) | a `threadViewPost` nests its `parent` chain and `replies` | `ThreadTreeBuildingTests.buildsTree` |
| `state/queries/post-thread.ts` (`responseToThreadNodes`) | missing `replyCount`/`likeCount`/`repostCount` are filled with `0` | `ThreadTreeBuildingTests.fillsCounters` |
| `state/queries/post-thread.ts` (`responseToThreadNodes`) | replies are filtered with `node.type !== 'blocked'` | `ThreadTreeBuildingTests.blockedReplyBuilding`, `FlatteningTests.blockedBranchDropped` |
| `state/queries/post-thread.ts` (`responseToThreadNodes`) | `threadContext.rootAuthorLike` becomes `hasOPLike` | `ThreadTreeBuildingTests.opLike` |
| `state/queries/post-thread.ts` (`annotateSelfThread`) | a same-author parent chain plus a same-author reply chain is a self-thread | `ThreadTreeBuildingTests.selfThreadAnnotated`, `ThreadTreeBuildingTests.notSelfThread` |
| `view/com/post-thread/PostThread.tsx` (`createThreadSkeleton`) | `parents + highlightedPost + replies` | `FlatteningTests.parentChainTopDown`, `FlatteningTests.depthFirstReplies`, `FlatteningTests.loneAnchor` |
| `view/com/post-thread/PostThread.tsx` (`flattenThreadParents`) | parents are emitted top-down before the anchor | `FlatteningTests.parentChainTopDown`, `FlatteningTests.deletedParent` |
| `view/com/post-thread/PostThread.tsx` (`flattenThreadReplies`) | replies are emitted depth-first, parent before child | `FlatteningTests.depthFirstReplies`, `FlatteningTests.deepChain` |
| `view/com/post-thread/PostThread.tsx` (`hasBranchingReplies`) | a level with >1 reply branches; one reply defers | `FlatteningTests.branchingShape`, `FlatteningTests.linearChainShape` |
| `view/com/post-thread/PostThread.tsx` (`hasPwiOptOut`) | `!no-unauthenticated` is honoured only logged out | `FlatteningTests` (skip path; see deviations 6) |
| `state/queries/usePostThread/types.ts` (`TraversalMetadata`) | depth, sibling index, last-child, last-sibling | `FlatteningTests.replyIndex`, `FlatteningTests.lastChild`, `FlatteningTests.onlyAnchorFlagged` |
| `state/queries/usePostThread/utils.ts` (`getThreadPostUI`) | `showParentReplyLine` excludes depth 0; `showChildReplyLine`; `indent` | `FlatteningTests.anchorConnectors`, `FlatteningTests.replyParentLine` |
| `state/queries/usePostThread/traversal.ts` | moderated posts are bucketed rather than rendered inline | `FlatteningTests.moderationAttached`, `PlaceholderTests.hiddenReplyBucketing` |
| `state/queries/usePostThread/traversal.ts` | a moderated non-top-level reply drops its whole subtree | `PlaceholderTests.hiddenDeepReplyDropped` |
| `state/queries/usePostThread/index.ts` | `skipModerationHandling` keeps every row inline | `FlatteningTests.skipModerationHandling` |
| `state/queries/usePostThread/traversal.ts` | `moreReplies` / `replyCount` unhydrated → a "read more" row | `FlatteningTests.readMoreRow`, `FlatteningTests.noReadMoreWhenHydrated` |
| `state/queries/post-thread.ts` (`responseToThreadNodes`) | `#notFoundPost` → a not-found node | `PlaceholderTests.notFoundMaps`, `PlaceholderTests.parentNotFound`, `PlaceholderTests.rootNotFound` |
| `state/queries/post-thread.ts` (`responseToThreadNodes`) | `#blockedPost` → a blocked node | `PlaceholderTests.blockedMaps`, `FlatteningTests.blockedAnchorKept` |
| `state/queries/usePostThread/utils.ts` (`getThreadPostUI`, `isBlurred`) | the decision's content-list blur hides a post | `PlaceholderTests.mutedDecisionHidden`, `PlaceholderTests.cleanDecisionVisible`, `PlaceholderTests.nilDecisionVisible` |
| `view/com/post-thread/PostThread.tsx` (`createThreadSkeleton`) | a tombstone anchor renders alone | `FlatteningTests.tombstoneOnlyAnchor` |
| `state/queries/post-thread.ts` (`sortThread`) — just-posted | a reply posted this session pins to the top | `SortingTests.justPostedPins`, `SortingTests.justPostedGating` |
| `state/queries/post-thread.ts` (`sortThread`) — OP | the OP's own replies sort first, oldest first | `SortingTests.opFirst`, `SortingTests.opOldestFirst` |
| `state/queries/post-thread.ts` (`sortThread`) — self | the viewer's own replies sort next, oldest first | `SortingTests.selfBeforeStrangers` |
| `state/queries/post-thread.ts` (`sortThread`) — threadgate | hidden replies sink unless the viewer wrote them | `SortingTests.threadgateHiddenSinks` |
| `state/queries/post-thread.ts` (`sortThread`) — blur | moderated replies sink | `SortingTests.moderatedSinks` |
| `state/queries/post-thread.ts` (`sortThread`) — pin | a bare `📌` reply sinks | `SortingTests.pinnedSinks`, `SortingTests.pinnedTrims` |
| `state/queries/post-thread.ts` (`sortThread`) — follows | `prioritizeFollowedUsers` lifts followed authors | `SortingTests.followedRise`, `SortingTests.followedIgnored` |
| `state/queries/post-thread.ts` (`sortThread`) — generations | older fetches always sort first | `SortingTests.fetchGenerations` |
| `state/queries/post-thread.ts` (`sortThread`) — order | `oldest` / `newest` compare `indexedAt` | `SortingTests.oldestOrder`, `SortingTests.newestOrder`, `SortingTests.equalReplies` |
| `state/queries/post-thread.ts` (`sortThread`) — order | `most-likes` sorts by count, ties newest-first | `SortingTests.mostLikesOrder`, `SortingTests.missingLikes` |
| `state/queries/post-thread.ts` (`sortThread`) — order | `random` uses a stable per-uri score | `SortingTests.randomOrder` |
| `state/queries/post-thread.ts` (`getHotness`) | recency + likes decay | `SortingTests.hotnessOrder`, `SortingTests.hotnessMonotonic`, `SortingTests.opLikeBoost` |
| `state/queries/post-thread.ts` (`sortThread`) | non-post nodes sort last | `SortingTests.tombstonesLast` |
| `state/queries/post-thread.ts` (`sortThread`) | the walk sorts every reply level | `SortingTests.sortsTree` |
| `view/com/post-thread/PostThread.tsx` (`PARENTS_CHUNK_SIZE`) | parents are revealed in chunks of 15 | `ShowMoreTests.defaults`, `ShowMoreTests.revealMoreParents` |
| `view/com/post-thread/PostThread.tsx` (`maxParents`) | only the last `maxParents` ancestors render | `ShowMoreTests.longChainWindowsTheTail`, `ShowMoreTests.shortChain` |
| `view/com/post-thread/PostThread.tsx` (`maxReplies`) | replies are capped at 100 with a `LOAD_MORE` row | `ShowMoreTests.replyCap`, `ShowMoreTests.shortReplies` |
| `view/com/post-thread/PostThread.tsx` (`LOAD_MORE`) | the cap doubles on reveal | `ShowMoreTests.revealMoreReplies` |
| `view/com/post-thread/PostThread.tsx` (`needsBumpMaxParents`) | more parents are available below the window | `ShowMoreTests.hasMoreParents`, `ShowMoreTests.windowState`, `ShowMoreTests.updateKeepsWindow` |
| `state/queries/post-liked-by.ts` | `PAGE_SIZE = 30`, `getNextPageParam: lastPage.cursor` | `ListTests.likedByPagination`, `ListTests.likedByParams`, `ListTests.pageSize` |
| `state/queries/post-liked-by.ts` (`RQKEY_ROOT = 'liked-by'`) | key rooted `liked-by` | `ListTests.listKeysScoped`, `ListTests.distinctKeys` |
| `state/queries/post-reposted-by.ts` | same contract, keyed `reposted-by` | `ListTests.repostedByPagination`, `ListTests.repostedByParams` |
| `state/queries/post-quotes.ts` | same contract, keyed `post-quotes` | `ListTests.quotesPagination`, `ListTests.quotesKeyRoot` |
| `state/queries/usePostThread/types.ts` (`createPostThreadQueryKey`) | the key carries the params | `ListTests.threadKey` |

### Not ported

- `findAllPostsInQueryData` / `findAllProfilesInQueryData` — these are cache
  scavengers for cross-query hydration, which is the `QueryStore`'s job here, not
  the feature package's.
- `getThreadgateRecord` and the `threadgate.record`-narrowing in
  `usePostThread/index.ts` — the threadgate *record* needs the lexicon
  `app.bsky.feed.threadgate` record type, which the package does not consume yet.
  The gate's *effect* on ordering (hidden replies) is ported through
  `ThreadSortInputs.threadgateHiddenReplies`.
- `createCacheMutator` (`queryCache.ts`) — optimistic reply insertion. It is a
  write path over a cache the Swift app does not expose yet.
- `getPostThreadOtherV2` — the server's "other replies" fetch. The package
  produces `otherItems` locally from moderation instead.

## Deviations from the RN implementation

1. **One flattening model, two wire shapes.** RN flattens the tree in the screen
   and traverses the flat list in the query hook, with two different sets of
   metadata. This package has one `ThreadFlattener` over a `ThreadNode` tree,
   which the `getPostThread` response parses into directly. The flat
   `getPostThreadV2` wire shape is not modelled; its semantics are.
2. **`parentHeight` is a parameter.** RN's tree query never sent one. It is
   modelled here because the endpoint accepts it and the "read more up"
   affordance needs to bound the chain.
3. **Connector state is data on the row.** RN stores it in a mutable `ui` object
   attached to each item during a second pass over a `Map` of metadata. This
   package computes it in the same two-pass shape but returns it on
   `ThreadItem.connector`, so the list is a value and can be diffed.
4. **The random score cache is an input.** RN's comparator reads
   `Math.random()` with a `randomCache` `Map` it mutates. Here the scores are
   supplied on `ThreadSortInputs.randomScores`, so `.random` is deterministic in
   tests and does not reshuffle on re-sort.
5. **The fetch-time cache is an input.** `fetchedAtCache` is a `Map` RN mutates
   inside the comparator; it is a field on `ThreadSortInputs` here, for the same
   reason.
6. **The unauthenticated skip is not directly tested.** `hasPWIOptOut` is
   implemented and wired to `ThreadFlattenOptions.hasSession`, but the fixture
   builders do not yet emit author labels, so there is no test case; the
   manifest maps the RN function to the flattening suite without naming a case.
7. **`isLastChild` follows RN's definition, not the intuitive one.** A childless
   reply is a last child (there is no next row at a deeper depth). Two tests
   assert this explicitly because it is easy to "fix" wrongly.
8. **A just-posted reply's tie-break is oldest-first.** RN sorts two
   just-posted replies by `indexedAt` ascending, which looks backwards but is
   what the code does; the Swift comparator matches.
9. **`indexedAt` compares as strings**, as RN's `localeCompare` does, rather
   than parsing to a `Date`. ISO-8601 with fixed precision orders correctly and
   matches RN for the odd records it also produces.
10. **Moderation is bridged, not shared.** `Moderation` does not depend on
    `Lexicons`, so `PostModerationAdapter` converts a lexicon `PostView` into
    the engine's subject type. Embed views and richtext facets are not bridged
    yet; neither affects a blur decision for a post.

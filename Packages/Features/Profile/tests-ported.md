# ProfileLogic - ported test manifest

Maps every behaviour in `Packages/Features/Profile` (product `ProfileLogic`) back
to the React Native source it was ported from, and to the Swift test that pins it.

- Reference app: `~/bluesky/social-app` (read-only)
- Swift tests: `Tests/ProfileLogicTests/`, 125 tests in 15 suites
- Run: `swift test --package-path Packages/Features/Profile`

The RN repo has no `*.test.ts` files for the profile feature, so this manifest
maps *behaviours* rather than 1:1 test cases. Each row names the RN expression or
function that defines the behaviour and the Swift test that asserts it.

## 1. Query keys and request shapes

| RN source | Behaviour | Swift test |
|---|---|---|
| `state/queries/profile.ts` `RQKEY = (did) => [root, did]` | one profile key per DID, scoped to the account | `ProfileQueryKeys.profile(did:scope:)` |
| `state/queries/profile.ts` `profilesQueryKey(handles)` | multi-profile key over a handle list | `ProfileRequestShapeTests.getProfilesJoinsActorsWithCommas` |
| `state/queries/post-feed.ts` `RQKEY(feedDesc)` | one feed key per descriptor | `ProfileRequestShapeTests.tabParametersMatchTheRnDescriptors` |
| `state/queries/post-feed.ts` `AuthorFilter` union | the five filter tokens | `ProfileRequestShapeTests.tabParametersMatchTheRnDescriptors` |
| `lib/api/feed/author.ts` `AuthorFeedAPI.params` | `includePins = filter === 'posts_and_author_threads'` | `ProfileRequestShapeTests.includePinsFollowsTheFilter`, `.postsPageSendsTheAuthorThreadsRequest` |
| `view/screens/Profile.tsx` posts tab | author-threads, *not* `posts_no_replies` | `ProfileRequestShapeTests.postsTabUsesAuthorThreadsNotNoReplies` |
| `view/screens/Profile.tsx` media tab | `posts_with_media` | `ProfileRequestShapeTests.mediaPageSendsTheMediaRequest` |
| `view/screens/Profile.tsx` videos tab | `posts_with_video` | `ProfileRequestShapeTests.videosPageSendsTheVideoRequest` |
| `view/screens/Profile.tsx` likes tab | `getActorLikes`, no filter, no pins | `ProfileRequestShapeTests.likesTabUsesGetActorLikes`, `.likesPageSendsTheActorLikesRequest` |
| `state/queries/post-feed.ts` `MIN_POSTS = 30` | every feed page requests 30 | `ProfileRequestShapeTests.everyTabRequestsThirtyItems` |
| `state/queries/profile-follows.ts` `RQKEY(did, sort)` | follows key carries actor + sort | `ProfileRequestShapeTests.followsPageSendsActorLimitAndSort` |
| `profile-follows.ts` conditional sort spread | sort omitted, never sent empty | `ProfileRequestShapeTests.followsPageOmitsSortWhenUnset` |
| `state/queries/profile-followers.ts` `RQKEY(did, sort)` | followers key + sort | `ProfileRequestShapeTests.followersPageSendsActorAndLimit` |
| `state/queries/known-followers.ts` `PAGE_SIZE = 50` | requests 50 | `ProfileRequestShapeTests.knownFollowersPageRequestsFifty` |
| `state/queries/labeler.ts` `useLabelerInfoQuery` | `getServices` with `detailed: true` | `ProfileRequestShapeTests.labelerServiceQueryAsksForDetail` |
| `state/queries/labeler.ts` `labelersInfoQueryKey(dids)` | DID list sorted before keying | `ProfileQueryKeys.LabelersArgs.init` |

## 2. Header derivation

| RN source | Behaviour | Swift test |
|---|---|---|
| `view/screens/Profile.tsx` `isMe` | self-detection | `ProfileHeaderDerivationTests.headerDerivationTable` |
| `viewer.following` | follow state | table row `following` |
| `state/cache/profile-shadow.ts` `mergeShadow` | shadow overrides viewer fields | `ProfileHeaderDerivationTests.shadowApplicationIsNonMutating`, `.shadowMergingKeepsEarlierFields` |
| `profile-shadow.ts` `'pending'` sentinel | an in-flight follow renders pending | `ProfileHeaderDerivationTests.headerDerivationTable` |
| `profile-shadow.ts` `isProfileShadowApplied` | field presence, not truthiness | `ProfileShadowStoreTests.clearedFieldsSurviveMerging` |
| `viewer.followedBy` | mutual-follow flag | `ProfileHeaderDerivationTests.headerDerivationTable` |
| mute handling | `viewer.muted` and `mutedByList` both mute | `ProfileHeaderDerivationTests.headerDerivationTable` |
| `viewer.mutedOnlyReposts` | reposts-only mute is distinct | `ProfileHeaderDerivationTests.headerDerivationTable` |
| `viewer.blocking` | blocked state | `ProfileHeaderDerivationTests.headerDerivationTable` |
| `viewer.blockedBy` | blocked-by banner | `ProfileHeaderDerivationTests.headerDerivationTable` |
| `screens/Profile/Header/Metrics.tsx` `formatCount(count \|\| 0)` | compact counts, zero fallback | `ProfileHeaderDerivationTests.basicProfileViewHasZeroCounts` |
| `view/screens/Profile.tsx` `hasDescription` | empty description renders nothing | `ProfileHeaderDerivationTests.headerDerivationTable` |
| `view/screens/Profile.tsx` `hasLabeler` | labeler variant selection | `ProfileHeaderDerivationTests.headerDerivationTable` |

## 3. Moderation

| RN source | Behaviour | Swift test |
|---|---|---|
| `moderateProfile(profile, moderationOpts)` | account + profile decisions merged | `ProfileHeaderModerationTests.cleanProfileIsUnblurred`, `.blockingProfileProducesABlockCause`, `.mutingProfileProducesAMuteCause` |
| `ui('profileView').blur` | header blur flag | `.hideLabelBlursTheHeader`, `.ignoreLabelLeavesTheHeaderClear` |
| `profile-shadow.ts` merge order | the *effective* (shadowed) profile is moderated | `.shadowMuteReachesTheModerationDecision` |
| `lib/moderation.ts` `isAppLabeler` | app labeler recognised by DID | `LabelerProfileTests.appLabelerHidesTheSubscribeButton` |
| `sdk/moderation` `resolveLabeler` | a label from an unsubscribed labeler is skipped | `ProfileHeaderModerationTests.hideLabelBlursTheHeader` |

## 4. Tabs and sections

| RN source | Behaviour | Swift test |
|---|---|---|
| `showPostsTab = true` | posts always shown | `ProfileTabVisibilityTests.defaultProfileShowsPostsAndReplies` |
| `showRepliesTab = hasSession` | replies need a session | `.signedOutHidesReplies` |
| `showMediaTab/showVideosTab = !hasLabeler` | labelers hide media and videos | `.labelerProfileShowsFiltersAndHidesMediaAndVideos` |
| `showLikesTab = isMe` | likes are the viewer's own | `.ownProfileShowsLikesFeedsAndStarterPacks` |
| `showFeedsTab = isMe \|\| feedGenCount > 0` | feeds rule | `.feedsTabAppearsForNonEmptyFeedgenCount` |
| `showStarterPacksTab = isMe \|\| starterPackCount > 0` | starter packs rule | `.starterPacksTabAppearsForNonEmptyCount` |
| `listCount = (lists \|\| 0) - starterPackCount` | starter packs not double-counted | `.listCountSubtractsStarterPacks` |
| `showListsTab = hasSession && (isMe \|\| listCount > 0)` | lists rule | `.signedOutHasNoListsTab` |
| `showFiltersTab = hasLabeler` | labels tab | `.labelerProfileShowsFiltersAndHidesMediaAndVideos` |
| `sectionTitles` positional order | section ordering | `.defaultProfileShowsPostsAndReplies`, `.ownProfileShowsLikesFeedsAndStarterPacks`, `.listsSectionMovesForLabelers` |

## 5. Follow / unfollow optimistic flow

| RN source | Behaviour | Swift test |
|---|---|---|
| `useProfileFollowMutation` | follow writes to the viewer's repo | `ProfileFollowFlowTests.followWritesTheRecordToTheViewersRepo` |
| `useProfileFollowMutationQueue` `queueFollow` | optimistic pending before the request | `.followWritesPendingBeforeTheRequestSettles` |
| `useToggleMutationQueue` `finally { onSuccess(...) }` | a failure rolls the optimistic write back | `.aFailedFollowRollsBack`, `.aFailedUnfollowRestoresThePreviousFollow` |
| `useProfileUnfollowMutation` | `deleteFollow` on the confirmed URI | `.unfollowDeletesTheFollowRecord` |
| `useToggleMutationQueue` `runMutation(confirmedState, …)` | a queued unfollow deletes the follow just created | `.queuedUnfollowDeletesTheJustCreatedFollow` |
| `useToggleMutationQueue` coalescing | a duplicate toggle sends nothing | `ToggleMutationQueueTests.aMatchingToggleIsCoalesced` |
| `useToggleMutationQueue` supersession | a replaced queued toggle is aborted | `ToggleMutationQueueTests.aSupersededToggleThrows` |
| `processQueue` ordering | mutations run in order, state fed forward | `ToggleMutationQueueTests.opposingTogglesRunInOrder` |
| `queue.activeTask` guard | one drain, one finalise | `ToggleMutationQueueTests.onSuccessRunsOncePerDrain` |
| `AbortError` | a failing mutation does not strand the queue | `ToggleMutationQueueTests.aFailureDoesNotStrandTheQueue` |
| `PROFILE_FOLLOWS_RQKEY(currentAccount.did)` splice | a confirmed follow is prepended to the viewer's follows cache | `ProfileFollowFlowTests.confirmedFollowIsPrependedToTheViewersFollowsCache` |
| same splice, unfollow branch | an unfollow is removed from every page | `.unfollowRemovesFromEveryPageOfTheCache` |
| `'Not signed in'` | writes without a session are refused | `.followWithoutASessionThrows` |
| `new AtUri(uri).rkeySafe` | follow/block URIs split into repo + rkey | `RecordKeyTests.splitsAWellFormedUri`, `.toleratesATrailingSlash`, `.rejectsAURiWithoutAnRkey` |
| `toDatetimeString(new Date())` | ISO-8601 `createdAt` | `RecordKeyTests.createdAtIsIso8601` |

## 6. Author-feed reply filter

| RN source | Behaviour | Swift test |
|---|---|---|
| `lib/api/feed/author.ts` `_filter` | only `posts_and_author_threads` filters | `AuthorFeedFilterTests.onlyThePostsTabFilters` |
| `_filter: if (!isReply) return true` | top-level posts kept | `.aTopLevelPostIsKept` |
| `_filter: if (isRepost \|\| isPin) return true` | reposts and pins kept | `.aRepostIsKept`, `.aPinIsKept` |
| `isAuthorReplyChain` author check | a reply to someone else is dropped | `.onlyThePostsTabFilters` |
| `isAuthorReplyChain` missing-parent branch | an unfetched parent means "show it" | `.aReplyWithAMissingParentIsKept` |
| `isAuthorReplyChain` recursion | multi-level author threads kept | `.anAuthorThreadReplyIsKept`, `.aDeepAuthorThreadIsKept` |

## 7. Edit profile

| RN source | Behaviour | Swift test |
|---|---|---|
| `lib/constants.ts` `MAX_DISPLAY_NAME = 64` | display-name limit | `ProfileEditValidationTests.displayNameBoundary` |
| `lib/constants.ts` `MAX_DESCRIPTION = 256` | description limit | `.descriptionBoundary` |
| `lib/strings/helpers.ts` `isOverMaxGraphemeCount` | counted in graphemes, not scalars | `.countsGraphemesNotScalars` |
| `EditProfileDialog.tsx` `trimEnd()` | trailing whitespace trimmed, leading kept | `.trailingWhitespaceIsTrimmed`, `.leadingWhitespaceIsPreserved` |
| `EditProfileDialog.tsx` `dirty` | dirty when any tracked field changed | `.dirtyDetection`, `.aProfileWithTrailingWhitespaceStartsClean` |
| lexicon `profile` blob size cap | 1,000,000 bytes per image | `.oversizedImageIsRejected`, `.imageAtTheCapIsAccepted` |
| `upsertProfile` merge | untouched fields survive, empty becomes `undefined` | `.recordUpsertKeepsUntouchedFields`, `.emptiedFieldsBecomeNil` |
| `newUserAvatar` null/undefined | unchanged / cleared / replaced image states | `.clearedImageDropsTheBlob`, `.unchangedImageKeepsTheExistingBlob`, `.replacedImageTakesTheUploadedBlob` |
| `state/queries/profile.ts` `uploadBlob` | image uploaded as multipart before the put | `ProfileEditWriteTests.uploadIsMultipartWithTheImageBytes` |
| `upsertProfile` orchestration | upload -> getRecord -> putRecord -> poll | `.writeUploadsReadsPutsAndPolls` |
| `upsertProfile` with an existing record | existing record read and merged | `.anExistingRecordIsMerged` |
| `whenAppViewReady` + `checkCommitted` avatar rules | unchanged URL means "not yet"; cleared means absent | `.commitPredicateImageRules` |
| `checkCommitted` text rules | name/description must match | `.commitPredicateTextRules`, `.commitPredicateTreatsEmptyAsNil` |
| `until(5, 1e3, fn, …)` budget exhausted | the last profile seen is returned, not an error | `.aStaleAppviewReturnsTheLastProfileSeen` |
| save disabled when invalid | validation precedes every request | `.validationRunsBeforeAnyRequest` |
| `useProfileUpdateMutation` `onSuccess` invalidations | profile + profiles caches invalidated | `.invalidatesCachesAfterAWrite` |

## 8. Labeler profile variant

| RN source | Behaviour | Swift test |
|---|---|---|
| `ProfileHeaderLabeler.tsx` `labeler.likeCount \|\| 0` | null count reads as zero | `LabelerProfileTests.nullLikeCountReadsAsZero` |
| `labeler.viewer?.like` | like URI drives the heart state | `.likeStateComesFromTheServiceView` |
| `preferences.moderationPrefs.labelers.find(...)` | subscribed state | `.subscribedStateComesFromPreferences` |
| `lib/moderation.ts` `isAppLabeler` gate | app labeler hides like and subscribe | `.appLabelerHidesTheSubscribeButton` |
| `HeaderLabelerButtons` `isMe` branch | own profile shows edit, not subscribe | `.ownProfileShowsEditNotSubscribe` |
| `HeaderLabelerButtons` message gate | needs session, non-self, unblocked | `.messageButtonRules` |
| signed-out disabling | like needs a session | `.likeButtonNeedsASession` |
| `labeler.creator.handle \|\| labeler.creator.did` | liked-by route identifier | `.creatorIdentifierPrefersTheHandle` |
| `useLabelerSubscriptionMutation` step 1 | a missing profile is an invalid labeler | `LabelerSubscriptionPlanningTests.aMissingProfileIsInvalid` |
| same, `associated && !associated.labeler` | a non-labeler profile is invalid | `.aNonLabelerProfileIsInvalid`, `.aProfileWithoutAssociationIsInvalid` |
| same, valid entries | valid labelers kept | `.aValidLabelerIsKept` |
| `labelerCount = labelerDids.length - invalidLabelers.length` | count checked *after* pruning | `.effectiveCountSubtractsInvalidLabelers`, `.pruningMakesRoomAtTheLimit` |
| `lib/constants.ts` `MAX_LABELERS = 20` | subscription limit | `.addingIsRefusedAtTheLimit`, `.theDefaultLimitIsTwenty` |
| `throw new Error('MAX_LABELERS')` | typed error carrying the counts | `.addingIsRefusedAtTheLimit` |
| re-subscribing | an existing subscription is a no-op | `.reAddingAnExistingLabelerIsAllowed` |
| app labeler is implicit | never pruned as invalid | `.theAppLabelerIsNeverInvalid` |

## 9. Shadows and known followers

| RN source | Behaviour | Swift test |
|---|---|---|
| `updateProfileShadow` merge | field-by-field merge, later wins | `ProfileShadowStoreTests.updatesMerge`, `.clearedFieldsSurviveMerging` |
| `useProfileShadow` subscription | current value on subscribe, then updates | `.subscribersSeeTheCurrentValueThenUpdates` |
| `emitter.addListener(profile.did, …)` | per-DID channel | `.subscribersAreScopedToTheirDid` |
| `listenProfileShadowUpdate` | all-DID channel | `.globalListenersSeeEveryDid` |
| sign-out / account change | shadows cleared | `.clearingOneDidLeavesOthers`, `.clearAllEmptiesTheStore` |
| `components/KnownFollowers.tsx` `shouldShowKnownFollowers` | non-empty preview list | `KnownFollowersTests.nonEmptyListShows`, `.emptyListHides` |
| `ProfileHeaderStandard.tsx` `!isMe && !isBlockedUser` | header gate | `.headerGateExcludesSelfAndBlocked` |
| `knownFollowers.count` vs `followers.length` | the label uses the server's total | `.countUsesTheLexiconTotalNotThePreviewCount` |

## Deviations from the RN behaviour

1. **Toggle-queue coalescing resolves instead of throwing.** RN rejects the
   second caller of a duplicate toggle with an `AbortError`. Resolving with the
   already-confirmed state is the same outcome for an idempotent toggle and keeps
   the caller from having to distinguish "superseded" from "failed".
   Supersession (two *different* targets queued while one runs) still throws
   `ToggleAbortError`, as RN does.

2. **The queue reads its initial state lazily.** RN captures `initialState` from
   the render that created the queue. `ToggleMutationQueue` reads it through a
   closure when a drain starts. The follow queue additionally *captures* its
   initial URI on the first toggle, because `unfollow()` clears the shadow before
   queueing and a later re-read would lose the URI the delete needs.

3. **Reply-chain walk is depth-bounded.** `isAuthorReplyChain` recurses without a
   bound in RN, relying on the parent lookup terminating. The Swift port caps the
   walk at 32 levels so a malformed page cannot cycle; a deeper chain is treated
   as intact, i.e. shown.

4. **Record bodies are hand-built.** `ProfileClient`'s follow and block paths, and
   `ProfileManager`'s profile put, encode their own JSON bodies rather than using
   the generated `GraphFollow` / `GraphBlock` / `ActorProfile` records. Two
   reasons, both found by this package's tests: the generated record encoders omit
   `$type`, which the PDS requires; and their `LexBlob`/`LexLink` fields encode as
   CBOR byte strings rather than the `{"$link": "..."}` JSON shape a JSON record
   body needs. The field sets match the lexicons. When the codegen is fixed these
   can revert to the typed records.

5. **The blob upload is done with a raw POST.** `ProfileManager.uploadBlob` builds
   the multipart body and reads `$link` from the response directly, because
   `XrpcClient.BlobRefLink` decodes that field as `link`. Same class of issue as
   (4); the workaround is local to this package.

6. **`ModerationPreferences` is not constructed here.** The labeler variant takes
   the subscribed labeler DIDs as a plain list rather than the preferences value,
   because `ModerationPreferences` exposes no public initialiser and the
   `Preferences` module and type share a name, which makes a qualified reference
   ambiguous from this package.

7. **No analytics.** RN emits `profile:follow`, `profile:unfollow`,
   `profile:block`, `moderation:subscribedToLabeler` and similar metrics
   throughout. The data they would use is exposed on the models
   (`ProfileHeaderViewData`, `LabelerProfileViewData`) and emission is left to the
   app layer, as in `LoginLogic`.

8. **No `userActionHistory`.** RN records follows and unfollows into
   `state/userActionHistory` for the suggested-follows funnel. That store is
   outside this feature's scope, so the queue exposes its finalised state instead.

## Not ported

- `state/queries/profile-feedgens.ts`, `profile-lists.ts`,
  `actor-starter-packs.ts` - the Feeds, Lists and Starter Packs tabs. The tab
  *visibility* rules are ported (section 4), but the tabs' own queries are
  separate features.
- `unstable-profile-cache.ts` - `precacheProfile` and the unstable cache used for
  placeholder data. Placeholder data is a view concern here: the header derivation
  takes whatever profile it is given.
- `verification/useUpdateProfileVerificationCache` - verification is not ported
  yet, so `invalidateProfileCaches` covers only the profile caches.
- `screens/Profile/ProfileLabelerLikedBy.tsx`, `ProfileSearch.tsx`,
  `Sections/Labels.tsx` - screens over other queries.

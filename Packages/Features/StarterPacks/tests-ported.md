# StarterPacks — tests-ported.md

Manifest mapping the RN reference material this package ports to the Swift tests
that pin the behaviour, per the repo convention (`AGENTS.md`, "Testing
philosophy": each feature package keeps a manifest mapping TS test cases to named
Swift tests).

Reference repo: `~/bluesky/social-app` (read-only), at commit `ff10dbd355f2a87130b54c888a2a4ee4b6908e15`.

There is no upstream `*.test.ts` for the starter-pack surfaces, so this is a
*behaviour* manifest: each row names the RN source of a behaviour and the Swift
tests that assert it. Where a behaviour has no upstream test, the row is marked
`—`.

## Query keys

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `src/state/queries/starter-packs.ts` (`RQKEY_ROOT = 'starter-pack'`, `RQKEY`) | pack key root and identity | `StarterPackKeyTests.roots`, `.packKeyFromURI`, `.packKeyFormsAgree`, `.packKeyDistinctness` |
| `starter-packs.ts` (`RQKEY` URI branch) | an http URI keys on the parsed handle | `StarterPackKeyTests.packKeyFromHTTPURI` |
| `starter-packs.ts` (`RQKEY` fallback branch) | an unparseable URI still gets a distinct key | `StarterPackKeyTests.packKeyUnparseable` |
| `src/state/queries/actor-starter-packs.ts` (`RQKEY`, `RQKEY_WITH_MEMBERSHIP`) | actor roots do not collide; a missing actor keys as `''` | `StarterPackKeyTests.actorRootsDistinct`, `.actorKeyDisabled` |
| `src/state/queries/starter-pack-search.ts` (`RQKEY(query, limit)`) | the query and the limit both participate in the key | `StarterPackKeyTests.searchKey` |
| `src/state/queries/list-members.ts` (`RQKEY`, `RQKEY_ALL`) | paged and exhaustive member reads are separate roots | `StarterPackKeyTests.memberKeys` |
| session account scope | two accounts get two entries | `StarterPackKeyTests.scopeSeparatesAccounts` |
| — | no starter-pack key declares a `persistedVersion` in RN | `StarterPackKeyTests.noPersistedVersion` |

## Constants

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `src/lib/constants.ts` (`STARTER_PACK_MAX_SIZE`, `JOINED_THIS_WEEK`) | the caps and display estimates match RN | `ConstantsTests.caps`, `.thresholds` |
| `screens/StarterPack/Wizard/index.tsx` (`minimumItems = 8`, feed cap 3) | the wizard minimums and the three-feed cap | `ConstantsTests.caps` |
| `src/state/queries/list-members.ts` (`PAGE_SIZE = 30`, `limit: 50`, `i < 6`) | member page sizes and the page cap | `ConstantsTests.pageSizes` |
| `src/state/queries/*` `staleTime` declarations | staleness budgets | `ConstantsTests.staleTimes` |

## Record payloads

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `src/lib/generate-starterpack.ts` (`createStarterPackList`) | the list record carries `$type`, `name`, `purpose`, `createdAt` | `StarterPackRecordsTests.listRecordShape` |
| `createStarterPackList` (`avatar: undefined`) | absent members are omitted, not written as null/empty | `StarterPackRecordsTests.listRecordShape`, `.listRecordEmptyDescription` |
| `createStarterPackList` (description + facets) | a description and its facets are written when present | `StarterPackRecordsTests.listRecordWithDescription` |
| `starter-packs.ts` (`useCreateStarterPackMutation`) | the created pack references the list and maps `feeds` to `{uri}` refs | `StarterPackRecordsTests.createRecordShape` |
| `useCreateStarterPackMutation` (`feeds?.map`) | `feeds` is omitted entirely when none were chosen | `StarterPackRecordsTests.createRecordWithoutFeeds` |
| `useEditStarterPackMutation` (`putRecord` body) | `createdAt` is carried over and `updatedAt` is added | `StarterPackRecordsTests.editRecordShape` |
| `useEditStarterPackMutation` (feeds quirk) | the edit path writes whole generator views, not `{uri}` refs | `StarterPackRecordsTests.editRecordWritesViews` |
| `useEditStarterPackMutation` (`list: currentStarterPack.list?.uri`) | `list` is omitted when the pack has none | `StarterPackRecordsTests.editRecordWithoutList` |
| `generate-starterpack.ts` (`createListItem`) | an `applyWrites#create` list-item write carries the record under `value` | `StarterPackRecordsTests.listItemWriteWithoutRkey`, `.listItemWriteWithRkey` |
| `starter-packs.ts` (delete branch, `new AtUri(i.uri).rkeySafe`) | an `applyWrites#delete` write is addressed by rkey and carries no `value` | `StarterPackRecordsTests.listItemDeleteWrite` |
| `starter-packs.ts` (`chunk(removedItems, 50)`) | writes chunk at 50 and preserve order | `StarterPackRecordsTests.chunking`, `.chunkingEmpty`, `.chunkingBoundary` |

## Create plan

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `useCreateStarterPackMutation` + `createStarterPackList` | the sequence is list create, one list-item batch, pack create | `StarterPackPlannerTests.createPlanShape` |
| `createStarterPackList` (list URI known only after the create) | the plan names the placeholder it will substitute | `StarterPackPlannerTests.createPlanPlaceholder`, `.createPlanPayloads` |
| `createStarterPackList` (item batch) | every list item references the list URI | `StarterPackPlannerTests.createPlanListItems` |
| — | the create path does not chunk, unlike the edit path | `StarterPackPlannerTests.createPlanDoesNotChunk` |
| `createStarterPackList` (`throw new Error('No profiles given')`) | no members means nothing is written | `StarterPackPlannerTests.createPlanWithoutMembers` |
| — | resolving the list URI rewrites the placeholder everywhere | `StarterPackPlannerTests.createPlanResolution`, `.createPlanConvenienceOverload` |
| `screens/StarterPack/Wizard/index.tsx` (`getDefaultName`) | the default name comes from the sanitized display name, else the handle | `StringTests.defaultPackName`, `.defaultPackNameFallback`, `.defaultPackNameTruncation` |

## Edit plan (diffing)

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `useEditStarterPackMutation` (`parseStarterPackUri(...)!.rkey`) | the rkey is derived from the pack URI | `StarterPackPlannerTests.editPlanRkey`, `.editPlanBadURI` |
| `useEditStarterPackMutation` (`removedItems`) | the author is never removed and selected members are kept | `StarterPackPlannerTests.removedItems`, `.removedItemsNeverIncludesAuthor` |
| `useEditStarterPackMutation` (`addedProfiles`) | added members are the selected profiles not already listed | `StarterPackPlannerTests.addedProfiles` |
| `useEditStarterPackMutation` (call order) | deletes first, then adds, then `putRecord` | `StarterPackPlannerTests.editPlanOrder`, `.editPlanNoDiff` |
| `useEditStarterPackMutation` (edit putRecord body) | the edited record carries `createdAt` over and sets `updatedAt` | `StarterPackPlannerTests.editPutRecordPayload` |
| `useEditStarterPackMutation` (`chunk(..., 50)`, both lists) | deletes chunk at 50, adds chunk at 50, deletes first | `StarterPackPlannerTests.editPlanChunking`, `.editDeleteRkeys` |
| `useDeleteStarterPackMutation` (list first, then pack) | the backing list is deleted before the pack | `StarterPackPlannerTests.deletePlanOrder`, `.deletePlanWithoutList` |
| — | the executor runs the plan in order against the wire | `StarterPackPlannerTests.executorCreate`, `.executorEdit`, `.executorDelete`, `.executorFailure` |

## Views and tabs

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `screens/StarterPack/StarterPackScreen.tsx` (`showPeopleTab`/`showFeedsTab`/`showPostsTab`) | the people/posts tabs follow the list, the feeds tab the feeds | `StarterPackDetailTests.tabs`, `.postsURI` |
| `StarterPackScreen.tsx` (`isValid`) | a listless pack is valid only for its owner | `StarterPackDetailTests.validWithList`, `.validWithoutListForOwner` |
| `StarterPackScreen.tsx` (`InvalidStarterPack` branch) | the missing-list-owned case is called out | `StarterPackDetailTests.deletedListOwned` |
| `StarterPackScreen.tsx` (`listItemCount`) | the member count comes from the list view, falling back to the sample | `StarterPackDetailTests.itemCount` |
| `StarterPackScreen.tsx` (`isOwn`) | ownership is set only for the creator | `StarterPackDetailTests.ownership` |
| `StarterPackScreen.tsx` (`joinedAllTimeCount >= 25`) | the joined line is hidden below 25 | `StarterPackDetailTests.joinedLineThreshold` |
| `StarterPackScreen.tsx` (header record/feeds) | the record's name, description and feeds are carried through in order | `StarterPackDetailTests.detailFields`, `.feeds`, `.recordRecovery` |
| `screens/StarterPack/StarterPackLandingScreen.tsx` (`isValid`) | the landing screen requires a list even for the owner | `StarterPackDetailTests.landingValidity`, `.landingState` |
| `StarterPackLandingScreen.tsx` (sample filter/slice) | the landing sample drops labelers and caps at eight | `StarterPackDetailTests.landingSample` |
| `StarterPackLandingScreen.tsx` (`listItemsCount <= 8`) | the follow copy names a remainder only above the threshold | `StarterPackDetailTests.followCopy` |

## Wizard state machine

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `screens/StarterPack/Wizard/State.tsx` (`createInitialState`, else branch) | a fresh wizard starts on details seeded with the target profile | `StarterPackWizardTests.freshInitialState` |
| `State.tsx` (`createInitialState`, starterPack branch) | an edit wizard seeds name, description, members and feeds | `StarterPackWizardTests.editInitialState` |
| `State.tsx` (`Next`/`Back` branches) | navigation advances, clamps at both ends, and records the direction | `StarterPackWizardTests.nextAdvances`, `.backSteps`, `.moveToSameStep`, `.moveDirection`, `.stepFlags`, `.adjacentSteps` |
| `State.tsx` (`SetName` -> `slice(0, 50)`) | the name is sliced to 50 characters | `StarterPackWizardTests.nameSliced`, `.nameKept` |
| `State.tsx` (`SetDescription`) | the description is not sliced by the reducer | `StarterPackWizardTests.descriptionNotSliced` |
| `State.tsx` (`AddProfile`, `length > STARTER_PACK_MAX_SIZE`) | the cap admits the 151st profile and refuses the 152nd | `StarterPackWizardTests.profileCapOffByOne` |
| `State.tsx` (`AddFeed`, `length >= 3`) | the fourth feed is refused | `StarterPackWizardTests.feedCap` |
| `State.tsx` (refusal toasts) | a refusal names the limit in RN's words | `StarterPackWizardTests.profileCapMessage` |
| `State.tsx` (`RemoveProfile`/`RemoveFeed`) | members are removed by DID and feeds by URI | `StarterPackWizardTests.removal`, `.membershipChecks` |
| `State.tsx` (`SetProcessing`) | processing is recorded and gates the footer | `StarterPackWizardTests.processingDisablesContinue` |
| `Wizard/index.tsx` (`items.length < 8`, footer `disabled`) | the people step needs eight members to continue | `StarterPackWizardTests.minimumProfilesGate`, `.noMinimumOnOtherSteps`, `.canNextGate` |
| `Wizard/index.tsx` (`nextBtn` labels) | the footer reads Skip on an empty feeds step, else Finish | `StarterPackWizardTests.footerLabels` |
| `Wizard/index.tsx` (`isEditEnabled`) | the edit affordance needs more than one person or any feed | `StarterPackWizardTests.editEnabled` |
| `Wizard/index.tsx` (count/limit badge) | the count and limit reflect the current step | `StarterPackWizardTests.itemCounts` |
| `Wizard/index.tsx` (`getName`, `enforceLen(..., 28, true)`) | labels prefer the display name and truncate at 28 | `StarterPackWizardTests.memberLabels`, `.memberLabelTruncation`, `.feedLabels` |
| `components/StarterPack/Wizard/WizardEditListDialog.tsx` (`getData`) | the edit list puts the target first, then members, and lists feeds on the feeds step | `StarterPackWizardTests.editListProfiles`, `.editListExcludesDuplicateTarget`, `.editListFeeds` |
| — | errors and refusals are recorded and can be cleared | `StarterPackWizardTests.errorAndRefusals` |

## Share and QR

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `src/lib/routes/links.ts` (`makeStarterPackLink`) | the app share link is `https://bsky.app/start/<handle>/<rkey>` | `StarterPackURITests.appShareLink`, `StarterPackShareTests.shareData` |
| `src/lib/strings/starter-pack.ts` (`getStarterPackOgCard`) | the card URL uses the creator's DID | `StarterPackURITests.ogCardURL` |
| `components/StarterPack/QrCodeDialog.tsx` (download filename) | the QR filename replaces only spaces | `StarterPackShareTests.qrFilename` |
| `components/StarterPack/ShareDialog.tsx` (`!imageLoaded \|\| !link` gate) | the share data is not ready until the short link resolves | `StarterPackShareTests.shareDataNotReady` |
| — | a pack with a handle and rkey can be shared | `StarterPackShareTests.canShare`, `.cannotShareWithoutRkey` |
| `src/lib/strings/starter-pack.ts` (`createStarterPackGooglePlayUri`) | the Play referrer carries the pack in `utm_content` | `StarterPackURITests.googlePlayURI`, `.googlePlayURIRejectsEmpty` |
| `starter-pack.ts` (`createStarterPackLinkFromAndroidReferrer`) | an install referrer recovers the pack URI, and rejects other sources/shapes | `StarterPackURITests.androidReferrer`, `.androidReferrerWrongSource`, `.androidReferrerWrongShape` |
| `starter-pack.ts` (`startUriToStarterPackUri`) | a `/start/` path rewrites to `/starter-pack/` | `StarterPackURITests.startToStarterPackPath` |

## URI parsing

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `starter-pack.ts` (`parseStarterPackUri`, at:// branch) | an `at://` pack URI parses to its authority and rkey | `StarterPackURITests.parseAtURI`, `.parseWrongCollection`, `.parseMissingRkey` |
| `starter-pack.ts` (`parseStarterPackUri`, URL branch) | an http URI parses to its handle and rkey; `/start/` is accepted | `StarterPackURITests.parseHttpStarterPackURL`, `.parseLegacyStartPath`, `.parseTooManySegments`, `.parseWrongPath`, `.parseNilAndEmpty` |
| `starter-pack.ts` (`httpStarterPackUriToAtUri`) | an http URI converts to `at://` and an `at://` URI passes through | `StarterPackURITests.httpToAtURI` |
| `starter-pack.ts` (`createStarterPackUri`) | the record URI is built from a DID and rkey | `StarterPackURITests.makeURI` |
| — | a record key is recoverable from any `at://` URI | `StarterPackURITests.parseRecordRkey` |

## Membership, opt-out and follow-all

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `components/dialogs/StarterPackDialog.tsx` (`isInPack = !!listItem`) | a row with a list item means the viewer is a member | `MembershipTests.memberFromRow`, `.nonMemberFromRow`, `.membershipFromRows` |
| `starter-packs.ts` (`useReferenceListOptOutMutation`, viewer state) | an opt-out URI on the list viewer means the viewer opted out | `MembershipTests.optOutDetected`, `.optOutAbsent` |
| `StarterPackScreen.tsx` (opt-out menu labels) | the menu offers the inverse of the current state | `MembershipTests.optOutMenuAction` |
| `useReferenceListOptOutMutation` (create branch) | an opt-out record names the list, not the pack, as its subject | `MembershipTests.optOutRecord`, `.optOutPlans` |
| `useReferenceListOptOutMutation` (delete branch) | undoing deletes the record the viewer state named | `MembershipTests.optOutPlans`, `.undoWithoutRecord` |
| `StarterPackScreen.tsx` (`onFollowAll` filter) | the viewer, followed, blocked and muted accounts are excluded; order is kept | `FollowAllTests.excludesSelf`, `.excludesFollowing`, `.excludesBlockedAndMuted`, `.preservesOrder`, `.loggedOut` |
| `Wizard/State.tsx` (seed from `listItems`) | the wizard seeds from members who did not opt out | `FollowAllTests.seedableMembers` |
| `Wizard/index.tsx` (`optedOutDids`) | the opted-out DID set drives the wizard's badge | `FollowAllTests.optedOutDIDs` |

## Pagination and the pack view query

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `src/state/queries/list-members.ts` (`useListMembersQuery`) | the member read asks for the RN page size and no cursor first | `PaginationTests.membersFirstPage` |
| `list-members.ts` (`getNextPageParam: lastPage => lastPage.cursor`) | the member walk follows the cursor and accumulates | `PaginationTests.membersPagination`, `.membersTerminal` |
| `list-members.ts` (`getAllListMembers`, `limit: 50`, six pages) | the exhaustive walk pages at 50 and stops at the cap | `PaginationTests.allMembersWalk`, `.allMembersPageCap` |
| `actor-starter-packs.ts` (`useActorStarterPacksQuery`, `limit: 10`) | the actor pack read pages and accumulates | `PaginationTests.actorPacksFirstPage`, `.actorPacksPagination` |
| `actor-starter-packs.ts` (`useActorStarterPacksWithMembershipsQuery`) | the membership read keeps the list item that proves membership | `PaginationTests.membershipPagination` |
| `starter-pack-search.ts` (`useStarterPackSearch`, `limit = 25`) | search asks with RN's default limit | `PaginationTests.searchFirstPage` |
| `starter-pack-search.ts` (`select`, uniqueness) | search results de-duplicate across pages and reset on a fresh search | `PaginationTests.searchDeduplication`, `.searchResetOnRefresh`, `.searchCursorWalk` |
| `starter-packs.ts` (`useStarterPackQuery`) | the pack view query resolves `at://`/http targets, caches, and is disabled without a target | `PaginationTests.packQueryLoad`, `.packQueryHTTP`, `.packQueryDisabled`, `.packQueryDetail`, `.packQueryFailure` |
| `starter-packs.ts` (`precacheStarterPack`) | a view can be written into the cache without a request | `PaginationTests.precache` |
| `list-members.ts` / `starter-pack-search.ts` (error handling) | a failing read surfaces the error | `PaginationTests.membersFailure`, `.searchFailure` |
| `list-members.ts` (`repeatedCursor` guard) | a server echoing its own cursor is refused rather than looped | `CursorWalkGuardTests.repeatedCursorRefused` |
| — | the multi-page walks reach their terminal pages | `CursorWalkGuardTests.memberWalkThreePages`, `.searchWalkFourPages`, `.actorWalkThreePages`, `.membershipWalkThreePages` |

## XRPC surface

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `starter-packs.ts` (`getStarterPack`) | the read carries the pack param and appview proxy routing | `LiveStarterPackXrpcTests.getStarterPack` |
| `notifications/util.ts` (`app.bsky.graph.getStarterPacks`) | the batch read emits one `uris` parameter per pack | `LiveStarterPackXrpcTests.getStarterPacks` |
| `actor-starter-packs.ts` (`getActorStarterPacks`) | `actor`, `cursor` and `limit` are sent; a nil cursor is omitted | `LiveStarterPackXrpcTests.getActorStarterPacks`, `.getActorStarterPacksNoCursor` |
| `actor-starter-packs.ts` (`getStarterPacksWithMembership`) | `actor` and `limit` are sent | `LiveStarterPackXrpcTests.getStarterPacksWithMembership` |
| `starter-pack-search.ts` (`searchStarterPacksV2`) | the V2 endpoint is used with `q` | `LiveStarterPackXrpcTests.searchStarterPacks` |
| `list-members.ts` (`getList`) | `list`, `cursor` and `limit` are sent | `LiveStarterPackXrpcTests.getList` |
| `starter-packs.ts` (`applyWrites` -> PDS) | writes post `repo` + `writes` to the PDS with no proxy header; empty batches make no request | `LiveStarterPackXrpcTests.applyWrites`, `.applyWritesEmpty` |
| `starter-packs.ts` (`createRecord`) | the create posts `repo`/`collection`/`record` and omits an absent rkey | `LiveStarterPackXrpcTests.createRecord`, `.createRecordWithRkey` |
| `starter-packs.ts` (`putRecord`) | the update posts the rkey and record | `LiveStarterPackXrpcTests.putRecord` |
| `starter-packs.ts` (`deleteRecord`) | the delete posts `repo`/`collection`/`rkey` | `LiveStarterPackXrpcTests.deleteRecord` |
| — | a failing write is mapped to an XRPC error | `LiveStarterPackXrpcTests.writeFailure` |

## String sanitizers

| RN source | Behaviour | Swift tests |
| --- | --- | --- |
| `src/lib/strings/display-names.ts` (`sanitizeDisplayName`) | check marks and control characters are stripped; whitespace collapses | `StringTests.sanitizeDisplayName`, `.collapseWhitespace` |
| `src/lib/strings/handles.ts` (`sanitizeHandle`, `isInvalidHandle`) | handles lowercase and prefix; `handle.invalid` becomes a warning | `StringTests.sanitizeHandle`, `.invalidHandle` |
| `src/lib/strings/helpers.ts` (`enforceLen`) | slicing and the ellipsis marker | `StringTests.enforceLen` |
| `src/lib/moderation/create-sanitized-display-name.ts` (`createSanitizedDisplayName`) | the default name prefers the display name and falls back to the handle | `StringTests.defaultPackName`, `.defaultPackNameFallback`, `.defaultPackNameTruncation` |

## Deliberate deviations

1. **`QueryStore.loadMore()` is not used for paged walks.** Its public guard
   calls `PaginationState.repeatsCursor(nextCursor)`, whose body is
   `nextCursor == cursor && pageCount > 1`; passing `nextCursor` back in makes the
   comparison self-referential, so every infinite query stalls after two pages.
   The paged starter-pack queries request pages through
   `InfiniteQuery.fetchPage(at:)` behind ``CursorWalkGuard``, which keeps the
   guard's intent (refuse a cursor already used in this walk) without the stall.
   Covered by `CursorWalkGuardTests.*`.
2. **Refusals are returned, not toasted.** `Wizard/State.tsx` shows a Toast when
   the profile or feed cap is hit. A Logic package has no toast, so the reducer
   records a ``WizardRefusal`` and leaves presentation to the caller.
3. **Profile views are narrowed to `WizardProfile`.** RN keeps whole
   `AnyProfileView`s in wizard state and reads `did`, `handle` and `displayName`
   from them (plus the avatar in the footer). The wizard carries exactly those
   three fields; a Views layer keeps whatever else it renders.
4. **`forceLTR` is not ported.** `sanitizeHandle` wraps a handle in bidi
   embedding marks on native only, and a Logic package has no platform to branch
   on. The lowercased handle is returned verbatim, which is what the web build
   produces.
5. **`getStarterPacks` (batch) is exposed but unused by a query.** RN uses it only
   for notification hydration (`notifications/util.ts`); the protocol method
   exists so a caller can reach it, and it is tested at the wire level.
6. **The create plan carries a placeholder list URI.** RN awaits the list create
   and then builds the pack record from its result. The plan is data, so the list
   URI is not known when it is built; a sentinel `at://pending.invalid` placeholder
   is substituted by ``StarterPackPlanExecutor`` (and by
   ``StarterPackWritePlan/resolvingListURI(_:)``). The payload tables assert both
   the placeholder form and the resolved form.
7. **`refencelistoptout` is a plan, not a query.** RN's
   `useReferenceListOptOutMutation` also polls `getStarterPack` until the appview
   observes the write. That retry loop is the same `until(5, 1e3, ...)` helper the
   other mutations use and is not ported; the write itself is planned by
   ``StarterPackOptOutPlanner``.
8. **Moderation is not consulted for pack display.** RN runs `moderateProfile`
   over each member card in the wizard and profile lists. The package depends on
   Moderation but does not call it for pack assembly: the decision inputs
   (per-card blur/alert) are a Views-layer concern, and keeping them out avoids
   freezing a rendering policy into the Logic layer.
9. **The profile cap's off-by-one is preserved.** `AddProfile` guards on
   `profiles.length > STARTER_PACK_MAX_SIZE`, so a 151st profile is admitted and
   the 152nd refused. `WizardTests.profileCapOffByOne` pins that rather than
   "fixing" it, so the port and RN agree on when the toast appears.
10. **No `precachesStarterPack` synthesis.** RN's `precacheStarterPack` fabricates
    a `listView` with an empty `cid` for a basic view. The port caches a full view
    (`StarterPackQuery.precache`) and leaves the basic-to-full synthesis out,
    because the synthetic `cid: ''` is not representable in the generated
    `FormatString<LexLink>` without a lie about the value.

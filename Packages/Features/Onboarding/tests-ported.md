# Onboarding — ported test manifest

Maps the RN source this package ports to the Swift tests that cover it.
Source repo: `~/bluesky/social-app` (read-only reference); paths below are
relative to its `src/`. Swift tests use Swift Testing (`import Testing`).

The RN onboarding flow has **no dedicated unit tests**: there is no
`__tests__/` directory anywhere under `screens/Onboarding` and no
`onboarding*.test.ts` under `state/queries`. The behaviour lives in the wizard
reducer (`screens/Onboarding/state.ts`), the step screens
(`screens/Onboarding/Step*/index.tsx`), the shared follow helper
(`screens/Onboarding/util.ts`), and the query hooks. The cases below are
therefore **semantic** ports — each Swift test asserts the same rule, branch, or
wire call the RN code implements — and every XRPC assertion is against the exact
method and params the RN call sites pass.

## Ported behaviour — wizard state machine

| RN source | RN behaviour | Swift test |
|---|---|---|
| `screens/Onboarding/index.tsx` | step order is profile, interests, suggested-accounts, suggested-starterpacks, finished | `OnboardingWizardOrderTests.defaultConfiguration` |
| `screens/Onboarding/index.tsx` | `starterPacksStepEnabled` / `findContactsStepEnabled` gate two optional steps | `OnboardingWizardOrderTests.findContactsEnabled` |
| `screens/Onboarding/state.ts` (`getStepOrder`) | enabled steps are filtered from a fixed order | `OnboardingWizardOrderTests.progressOrder` |
| `screens/Onboarding/state.ts` (`reducer`, `next`) | advance moves to the next enabled step and marks the direction Forward | `OnboardingWizardTransitionTests.advanceSettles` |
| `screens/Onboarding/state.ts` (`reducer`, `next`) | at the last step the pointer does not move | `OnboardingWizardTransitionTests.advanceAtEnd` |
| `screens/Onboarding/state.ts` (`reducer`, `prev`) | back moves to the previous enabled step and marks the direction Backward | `OnboardingWizardTransitionTests.goBackDirection` |
| `screens/Onboarding/state.ts` (`reducer`, `prev`) | back at the first step does not move | `OnboardingWizardTransitionTests.goBackAtStart` |
| `screens/Onboarding/state.ts` (`hasPrev`) | `canGoBack` is `activeStep !== stepOrder[0]` | `OnboardingWizardTransitionTests.canGoBack` |
| `screens/Onboarding/state.ts` (`reducer`, `skip-contacts`) | `skip-contacts` jumps past the whole find-contacts pair | `OnboardingWizardTransitionTests.skipContactsSettlesPair` |
| `screens/Onboarding/state.ts` (`getStepOrder` filter) | find-contacts and finished are excluded from the display index | `OnboardingWizardOrderTests.progressOrder` |
| `screens/Onboarding/state.ts` (`activeStepIndex`) | find-contacts folds onto its intro for display | `OnboardingWizardTransitionTests.displayIndex` |
| `screens/Onboarding/state.ts` (`nextStep` derivation) | neighbours come from the enabled order | `OnboardingWizardTransitionTests.derivedNeighbours` |
| `screens/Onboarding/StepSuggestedAccounts/index.tsx` | the Skip button advances without following | `OnboardingWizardTransitionTests.skipMarksSkipped` |
| `screens/Onboarding/StepProfile/index.tsx` | the profile step has no Skip control | `OnboardingWizardTransitionTests.skipRequiredRefused` |
| `screens/Onboarding/StepSuggestedStarterpacks/index.tsx` | the starter-packs step has a Skip control | `OnboardingWizardTransitionTests.skipStarterPacks` |

## Ported behaviour — resumability

| RN source | RN behaviour | Swift test |
|---|---|---|
| `state/shell/onboarding.tsx` (`compute`) | the persisted step determines `isActive` / `isComplete` | `OnboardingWizardResumeTests.progressRoundTrip` |
| `state/shell/onboarding.tsx` (`reducer`, `set`) | an unrecognized persisted step is not adopted | `OnboardingWizardResumeTests.disabledStepDiscarded` |
| `screens/Onboarding/state.ts` (`useOnboardingInternalState`) | results survive a step change, so re-entering a finished step shows its input | `OnboardingWizardTransitionTests.goBackPreservesCompletion` |

## Ported behaviour — profile step

| RN source | RN behaviour | Swift test |
|---|---|---|
| `screens/Profile/Header/EditProfileDialog.tsx` | a display name over `MAX_DISPLAY_NAME` (64) is rejected | `ProfileValidationTests.tooLongDisplayName` |
| `screens/Profile/Header/EditProfileDialog.tsx` | the counter counts UTF-16 code units (`string.length`) | `ProfileValidationTests.utf16LengthCounting` |
| `screens/Signup/StepHandle/index.tsx` | handle syntax: dot-separated, 3-18 char name, alphanumeric with interior hyphens | `ProfileValidationTests.validHandles`, `.invalidHandles` |
| `lib/strings/handles.ts` (`createFullHandle`) | a name and domain compose into a full handle, trimming stray dots | `ProfileValidationTests.fullHandleComposition` |
| `screens/Onboarding/StepFinished/index.tsx` (`finishOnboarding`) | the avatar bytes are uploaded, then referenced from the profile record | `ProfileStepTests.uploadThenProfileWrite` |
| `screens/Onboarding/StepFinished/index.tsx` (`finishOnboarding`) | no avatar means no `uploadBlob` call | `ProfileStepTests.noAvatarNoUpload` |
| `lib/api/index.ts` (`uploadBlob`) | `com.atproto.repo.uploadBlob` posts a multipart body and returns the blob ref | `LiveActionServiceTests.avatarUpload` |
| `@bsky/sdk` (`upsertProfile`) | the existing profile record is read and spread, so unmodelled fields survive | `LiveActionServiceTests.profileUpsertSpreadsExisting` |
| `@bsky/sdk` (`upsertProfile`) | a missing profile record is not an error | `LiveActionServiceTests.missingProfileRecord` |
| `@bsky/sdk` (`upsertProfile`) | `avatar` and `joinedViaStarterPack` are encoded into the record | `LiveActionServiceTests.profileRecordFields` |
| `screens/Onboarding/StepFinished/index.tsx` | `displayName = ''` is written from the onboarding flow | `ProfileStepTests.emptyDisplayNameAccepted` |

## Ported behaviour — interests step

| RN source | RN behaviour | Swift test |
|---|---|---|
| `lib/interests.ts` | the taxonomy is the 24-tag alphabetized list | `InterestsTests.taxonomyMatches` |
| `lib/interests.ts` (`popularInterests`) | nine tags are surfaced first | `InterestsTests.popularSubset` |
| `lib/interests.ts` (`useInterestsDisplayNames`) | every tag has a display name | `InterestsTests.displayNamesComplete` |
| `components/InterestTabs.tsx` (`boostInterests`) | the tab order is driven by two chained stable sorts | `InterestsTests.tabOrder`, `.tabOrderNoSelection` |
| `screens/Onboarding/StepInterests/index.tsx` (`saveInterests`) | the selection is stored as step results and the step advances | `InterestsStepTests.writesSelection` |
| `screens/Onboarding/StepInterests/index.tsx` | the `OnboardingInterestsRequiredEnable` gate blocks an empty selection | `InterestsStepTests.emptyRefusedWhenRequired` |
| `state/queries/preferences` (`setInterestsPref`) | the write lands in the `interestsPref` record's `tags` | `LiveActionServiceTests.interestsThroughEngine` |

## Ported behaviour — suggested follows and starter packs

| RN source | RN behaviour | Swift test |
|---|---|---|
| `screens/Onboarding/util.ts` (`bulkWriteFollows`) | follows are written with `com.atproto.repo.applyWrites`, one `#create` per subject | `LiveActionServiceTests.applyWritesShape` |
| `screens/Onboarding/util.ts` (`bulkWriteFollows`) | writes are chunked at 50 per call | `LiveActionServiceTests.chunking` |
| `screens/Onboarding/util.ts` (`bulkWriteFollows`) | a `via` strong reference is attached to each follow record | `LiveActionServiceTests.viaReference` |
| `screens/Onboarding/StepSuggestedAccounts/index.tsx` (`followAll`) | every followable DID is followed in one batch | `SuggestedAccountsStepTests.followsSelection` |
| `screens/Onboarding/StepSuggestedAccounts/index.tsx` | an empty selection makes no call | `SuggestedAccountsStepTests.emptySelection` |
| `screens/Search/util/useSuggestedOnboardingUsers.ts` | `getSuggestedOnboardingUsers` is called with `category` and `limit` | `LiveSuggestionServiceTests.suggestedUsersCall` |
| `state/queries/trending/useGetSuggestedOnboardingUsersQuery.ts` | the default limit is 10 | `LiveSuggestionServiceTests.suggestedUsersCall`, `OnboardingQueryKeyTests.limits` |
| `state/queries/trending/useGetSuggestedOnboardingUsersQuery.ts` | `recIdStr` is preferred and `recId` is the deprecated fallback | `LiveSuggestionServiceTests.recIdFallback` |
| `lib/api/feed/utils.ts` (`createBskyTopicsHeader`) | interests travel in the `X-Bsky-Topics` header | `LiveSuggestionServiceTests.suggestedUsersCall` |
| `screens/Onboarding/StepSuggestedAccounts/index.tsx` | blocked, muted, and already-following users are excluded from follow-all | `LiveSuggestionServiceTests.viewerStateProjection` |
| `state/queries/useOnboardingSuggestedStarterPacksQuery.ts` | the starter-packs call uses a limit of 6 | `LiveSuggestionServiceTests.starterPacksCall` |
| `state/queries/useOnboardingSuggestedStarterPacksQuery.ts` | the key root is `onboarding-suggested-starter-packs` | `OnboardingQueryKeyTests.starterPacksRoot` |
| `state/queries/trending/useGetSuggestedOnboardingUsersQuery.ts` | the key root is `unspecced-suggested-onboarding-users` | `OnboardingQueryKeyTests.usersRoot` |

## Ported behaviour — handle availability

| RN source | RN behaviour | Swift test |
|---|---|---|
| `state/queries/handle-availability.ts` | the Bluesky entryway uses `com.atproto.temp.checkHandleAvailability` | `HandleAvailabilityTests.availableResult` |
| `state/queries/handle-availability.ts` | the entryway returns suggestions on an unavailable handle | `HandleAvailabilityTests.unavailableResult` |
| `state/queries/handle-availability.ts` | `birthDate` and `email` shape the suggestions | `HandleAvailabilityTests.birthDateAndEmail` |
| `state/queries/handle-availability.ts` | a third-party PDS falls back to `com.atproto.identity.resolveHandle` | `HandleAvailabilityTests.resolveHandleTaken` |
| `state/queries/handle-availability.ts` | a resolve-handle failure means the handle is available | `HandleAvailabilityTests.resolveHandleFailure` |
| `state/queries/handle-availability.ts` | an unrecognized result shape throws rather than guessing | `HandleAvailabilityTests.unrecognizedResult` |
| `lib/constants.ts` (`BSKY_SERVICE_DID`) | the entryway is recognized by DID | `HandleAvailabilityTests.strategySelection` |

## Ported behaviour — adult-content gate

| RN source | RN behaviour | Swift test |
|---|---|---|
| `state/queries/preferences` (`setAdultContentEnabled`) | the gate writes a single preference | `StarterPacksAndGateTests.adultContentWrite` |
| `state/queries/preferences` (`setAdultContentEnabled`) | a write failure is reported without changing the step | `StarterPacksAndGateTests.adultContentFailure`, `OnboardingFlowTests.adultContentGate` |

## Ported behaviour — completion

| RN source | RN behaviour | Swift test |
|---|---|---|
| `screens/Onboarding/StepFinished/index.tsx` (`finishOnboarding`) | the five writes run in this order: follows, interests, saved feeds, profile, NUX | `CompletionStepTests.completionSequence` |
| `screens/Onboarding/StepFinished/index.tsx` (`finishOnboarding`) | `BSKY_APP_ACCOUNT_DID` is followed alongside the pack's members | `CompletionStepTests.followsAppAccount` |
| `screens/Onboarding/StepFinished/index.tsx` (`finishOnboarding`) | a joined pack contributes its members, its feeds, and its strong ref | `CompletionStepTests.joinedStarterPack` |
| `screens/Onboarding/StepFinished/index.tsx` (`finishOnboarding`) | a pack that cannot be resolved is logged and every other write still runs | `CompletionStepTests.unresolvableStarterPack` |
| `screens/Onboarding/StepFinished/index.tsx` (`finishOnboarding`) | any single write failing does not stop the rest (`Promise.all` + swallow) | `CompletionStepTests.followFailureBestEffort`, `.nuxFailureBestEffort` |
| `lib/constants.ts` (`DISCOVER_SAVED_FEED`, `TIMELINE_SAVED_FEED`, `VIDEO_SAVED_FEED`) | three default feeds are pinned, in this order | `CompletionStepTests.defaultSavedFeeds` |
| `@bsky/sdk` (`overwriteSavedFeeds`) | each saved feed is minted a fresh TID | `LiveActionServiceTests.savedFeedsThroughEngine` |
| `state/queries/nuxs` (`upsertNux`) | a NUX record is upserted into the app-state preference | `LiveActionServiceTests.nuxThroughEngine` |
| `screens/Onboarding/StepFinished/index.tsx` (`dispatch({type: 'finish'})`) | completion resets the wizard to its initial state | `OnboardingFlowTests.finish` |
| `state/shell/onboarding.tsx` (`reducer`, `finish`) | the shell's step moves to Home on finish | `OnboardingFlowTests.finish`, `.finishBestEffort` |

## Ported behaviour — contacts and list paging

| RN source | RN behaviour | Swift test |
|---|---|---|
| `state/queries/list-members.ts` (`getAllListMembers`) | `app.bsky.graph.getList` is paged to exhaustion via `cursor` | `LiveActionServiceTests.listMembersPaging` |
| `screens/Onboarding/StepFindContacts*` | the find-contacts pair is skippable as one unit | `OnboardingWizardTransitionTests.skipContactsSettlesPair`, `.skipContactsDisabled` |

## Deviations from the RN flow

1. **Explicit completion state.** RN infers "done" from whether step results
   were set and from the active index, and its persisted state is only the
   shell's coarse step. ``StepCompletion`` records settled and skipped steps
   explicitly so a resumed session can derive the next step without replaying
   the flow.

2. **The avatar is uploaded at the profile step, not at completion.** RN defers
   every write to `StepFinished`, uploading the avatar alongside the follows and
   preference writes inside one `Promise.all`. Uploading at the profile step
   keeps each step self-contained: a failed avatar upload cannot take the follow
   and preference writes down with it. ``OnboardingStepRunner/runCompletionStep``
   still accepts avatar bytes so a caller that keeps RN's structure works.

3. **The starter-packs step writes nothing.** RN records the chosen pack in
   local shell state (`useSetActiveStarterPack`) and resolves it at completion.
   ``StarterPacksStepResult`` carries the URI, and the resolution happens in the
   same place RN does it.

4. **The completion writes are sequential, not concurrent.** RN uses
   `Promise.all`; this runner awaits each write in order so the exact call
   sequence is observable and assertable. One stateful client at a time is the
   other reason: the preferences engine's read-modify-write is serialized, so
   the two preference writes could not interleave anyway.

5. **`uploadBlob`'s response is decoded in-package.** `ATProtoClient`'s
   `BlobUploadResponse.BlobRefLink` declares a `link` property while the wire
   member is `$link`, so `XrpcClient.uploadBlob` always returns a nil ref. The
   request bytes are identical; only the response is decoded here. See the open
   questions in the hand-off note.

6. **The handle is validated but not written.** Nothing in the RN onboarding
   flow changes a handle, and a handle is not a profile field
   (`com.atproto.identity.updateHandle` is a separate call). The validation
   rules are implemented because a caller that collects one should get the same
   answer the signup step gives, and ``runProfileStep`` accepts one for that.

7. **The NUX id is app-specific.** RN's onboarding writes no NUX: it drives the
   shell's persisted step. ``OnboardingConstants/onboardingNuxID`` is a durable
   marker so completion survives local storage being cleared; it is deliberately
   not one of the RN NUX ids, which all name unrelated features.

8. **No analytics.** RN emits `onboarding:*` metrics from every step.
   ``OnboardingFlow`` exposes the data they would use (the active step, the
   selections, the results) and leaves emission to the app layer.

9. **The adult-content gate is a call, not a step.** RN's onboarding has no
   adult-content screen; the gate is applied from moderation settings and the
   age-assurance dialog after onboarding. ``applyAdultContentGate(enabled:)`` is
   exposed for a flow that does collect the answer.

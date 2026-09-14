# ModerationUI — ported test manifest

Maps the RN moderation UI source this package ports to the Swift tests that
cover it. Source repo: `~/bluesky/social-app` (read-only reference); paths below
are relative to its `src/`. Swift tests use Swift Testing (`import Testing`).

`ModerationUILogic` is the Linux-verifiable logic half of the feature. It has no
SwiftUI/UIKit and no `Observation`; every model here returns data for a Views
package to render. The moderation inbox is deliberately out of scope (an
internal tool, deferred per the plan).

## Report flow

The report dialog is split across four files: the subject parser, the reducer,
the submit path, and the error classifier. Each RN file has a native test or a
direct derivation, and every case below pins the exact `createReport` body or
the exact state transition.

| RN source | Behaviour ported | Swift tests |
|---|---|---|
| `components/moderation/ReportDialog/utils/parseReportSubject.ts` — profile views | `profileViewBasic`, `profileView`, `profileViewDetailed` all parse as an account subject with the profile NSID | `ReportSubjectParsingTests.accountFromProfileViewBasic`, `ReportSubjectParsingTests.accountFromProfileView`, `ReportSubjectParsingTests.accountFromProfileViewDetailed`, `ReportSubjectParsingTests.accountNsidIsTheRecordNsid` |
| `components/moderation/ReportDialog/utils/parseReportSubject.ts` — status | a status subject needs both a uri and a cid; either missing yields no subject | `ReportSubjectParsingTests.statusParses`, `ReportSubjectParsingTests.statusWithoutUriIsNil`, `ReportSubjectParsingTests.statusWithoutCidIsNil` |
| `components/moderation/ReportDialog/utils/parseReportSubject.ts` — list/feed | the list and generator views parse with their own record NSIDs | `ReportSubjectParsingTests.listParses`, `ReportSubjectParsingTests.feedParses` |
| `components/moderation/ReportDialog/utils/parseReportSubject.ts` — starter pack | the parsed subject carries the REAL `app.bsky.graph.starterpack` NSID; RN wrote the typo'd `app.bsky.graph.starterPack`, which is still accepted on parse | `ReportSubjectParsingTests.starterPackUsesRealNsid`, `ReportSubjectParsingTests.starterPackTypoNsidAcceptedOnParse`, `ReportSubjectParsingTests.starterPackNsidConstants`, `ReportSubjectParsingTests.starterPackSourceType` |
| `components/moderation/ReportDialog/utils/parseReportSubject.ts` — post attributes | `reply` comes from the record; the media flags come from the parsed embed, including the record-with-media case | `ReportSubjectParsingTests.postParses`, `ReportSubjectParsingTests.postReplyAttribute`, `ReportSubjectParsingTests.postNonReplyAttribute`, `ReportSubjectParsingTests.postImageAttribute`, `ReportSubjectParsingTests.postGalleryAttribute`, `ReportSubjectParsingTests.postVideoAttribute`, `ReportSubjectParsingTests.postLinkAttribute`, `ReportSubjectParsingTests.postQuoteAttribute`, `ReportSubjectParsingTests.postWithMediaAttributes`, `ReportSubjectParsingTests.postNoEmbed` |
| `components/moderation/ReportDialog/utils/parseReportSubject.ts` — chat | the convo and convo-message shapes, which carry no record NSID | `ReportSubjectParsingTests.convoParses`, `ReportSubjectParsingTests.convoMessageParses`, `ReportSubjectParsingTests.chatSubjectsHaveNoNsid` |
| `components/moderation/ReportDialog/utils/useReportOptions.ts` | the eight categories, in order, with their options | `ReportFlowTests.catalogCategoryOrder`, `ReportFlowTests.catalogOptionsPopulated` |
| `components/moderation/ReportDialog/const.ts` — reason sets | `OTHER_REPORT_REASONS` and `BSKY_LABELER_ONLY_REPORT_REASONS` | `ReportFlowTests.otherReasonsSet`, `ReportFlowTests.blueskyOnlyReasonsSet` |
| `components/moderation/ReportDialog/const.ts` — reason maps | `NEW_TO_OLD_REASONS_MAP` covers every catalog reason | `ReportFlowTests.newToOldMapCoversCatalog` |
| `components/moderation/ReportDialog/action.ts` — subject bodies | each subject shape maps onto `createReport`'s union: a repoRef for accounts, a strongRef for every record-backed subject, and the chat refs | `ReportFlowTests.accountSubject`, `ReportFlowTests.postSubject`, `ReportFlowTests.listSubject`, `ReportFlowTests.feedSubject`, `ReportFlowTests.starterPackSubject`, `ReportFlowTests.statusSubject`, `ReportFlowTests.convoMessageSubject`, `ReportFlowTests.convoSubject` |
| `components/moderation/ReportDialog/action.ts` — comment | the details text is sent as `reason`, omitted when empty | `ReportFlowTests.commentAsReason`, `ReportFlowTests.noCommentOmitsReason` |
| `components/moderation/ReportDialog/action.ts` — validation | submitting with no reason or no moderation service is refused | `ReportFlowTests.noReasonThrows`, `ReportFlowTests.noLabelerThrows` |
| `components/moderation/ReportDialog/action.ts` — reason fallback | a labeler declaring only the old atproto reason type gets that value; both declared prefers the new one; undeclared passes the new one through | `ReportFlowTests.undeclaredReasonTypesPassThrough`, `ReportFlowTests.newReasonTypePreferred`, `ReportFlowTests.oldReasonTypeFallback`, `ReportFlowTests.bothDeclaredPrefersNew`, `ReportFlowTests.unmappedReasonUnchanged` |
| `components/moderation/ReportDialog/action.ts` — mod tool | the video-timestamp tool metadata is attached only for a video post reported to Bluesky with the opt-in set | `ReportFlowTests.videoTimestampAttached`, `ReportFlowTests.videoTimestampNotOptedIn`, `ReportFlowTests.videoTimestampOnlyForPosts`, `ReportFlowTests.videoTimestampOnlyForBluesky` |
| `components/moderation/ReportDialog/const.ts` — `REPORT_MOD_TOOL_NAME` | the platform-shaped client identifier | `ReportFlowTests.modToolNames` |
| `components/moderation/ReportDialog/index.tsx` — labeler filters | the three `.filter` passes: subject type, declared collections, then the Bluesky-only short circuit and reason types | `ReportFlowTests.undeclaredLabelerSupportsAll`, `ReportFlowTests.subjectTypeFilter`, `ReportFlowTests.accountSubjectType`, `ReportFlowTests.chatSubjectType`, `ReportFlowTests.collectionFilter`, `ReportFlowTests.chatBypassesCollections`, `ReportFlowTests.starterPackCollectionUsesRealNsid`, `ReportFlowTests.reasonTypeFilter`, `ReportFlowTests.oldReasonFormPasses`, `ReportFlowTests.blueskyOnlyReason`, `ReportFlowTests.blueskyOnlySubject`, `ReportFlowTests.convoIsBlueskyOnly`, `ReportFlowTests.supportedLabelersOrder` |
| `components/moderation/ReportDialog/index.tsx` — subject vocabularies | the Bluesky-only subject set is written in `ParsedReportSubject['type']` vocabulary, which is distinct from the labeler-eligibility kind | `ReportFlowTests.subjectTypeNameAndKindDiffer`, `ReportFlowTests.subjectKinds` |
| `components/moderation/ReportDialog/state.ts` (`getNciiQualificationOutcome`) | the NCII answer resolves to pending / external form / in-app | `ReportStateTests.outcomeUndefinedWithoutNcii`, `ReportStateTests.outcomePending`, `ReportStateTests.outcomeExternalForm`, `ReportStateTests.outcomeInApp` |
| `components/moderation/ReportDialog/state.test.ts` — NCII gating | selecting NCII holds at step 2; an answer advances only when it is in-app; an auto-selected labeler does not skip the question | `ReportStateTests.nciiReasonHoldsAtStepTwo`, `ReportStateTests.nonNciiReasonAdvances`, `ReportStateTests.nciiDepictedHoldsAtTwo`, `ReportStateTests.nciiNotDepictedAdvances`, `ReportStateTests.labelerDoesNotSkipPendingNcii`, `ReportStateTests.nciiResolvesToStepFourWithLabeler`, `ReportStateTests.nciiResolvesToStepThreeWithoutLabeler`, `ReportStateTests.clearReasonClearsNcii`, `ReportStateTests.clearCategoryClearsNcii` |
| `components/moderation/ReportDialog/state.test.ts` — video timestamp | the opt-in is off by default, toggles, and is cleared by a labeler or reason change | `ReportStateTests.videoTimestampOffByDefault`, `ReportStateTests.videoTimestampToggles`, `ReportStateTests.clearLabelerClearsVideoTimestamp`, `ReportStateTests.selectLabelerClearsVideoTimestamp`, `ReportStateTests.clearReasonClearsVideoTimestamp`, `ReportStateTests.clearCategoryClearsVideoTimestamp` |
| `components/moderation/ReportDialog/state.ts` — categories | selecting a category advances to step 2; the "other" category jumps to step 3 with its option preset; clearing resets | `ReportStateTests.selectCategoryAdvancesToTwo`, `ReportStateTests.selectOtherCategoryJumpsToThree`, `ReportStateTests.clearCategoryResets`, `ReportStateTests.clearReasonReturnsToTwo` |
| `components/moderation/ReportDialog/state.ts` — details | an "other"-style reason opens the comment field; a labeler selection recomputes it | `ReportStateTests.otherReasonOpensDetails`, `ReportStateTests.nonOtherReasonKeepsDetailsClosed`, `ReportStateTests.showDetails`, `ReportStateTests.selectLabelerRecomputesDetails`, `ReportStateTests.setDetails`, `ReportStateTests.errorRoundTrip` |
| `components/moderation/ReportDialog/state.ts` — labeler step | selecting advances to step 4; clearing returns to step 3 | `ReportStateTests.selectLabelerAdvances`, `ReportStateTests.clearLabelerReturnsToThree` |
| `components/moderation/ReportDialog/errors.ts` + `errors.test.ts` | the classifier's kinds, buckets, fingerprints and tags, including the anchored upstream-status match | `ReportErrorTests.accountTakedown`, `ReportErrorTests.upstreamUnavailable`, `ReportErrorTests.invalidReasonType`, `ReportErrorTests.nonRetryableUpstream`, `ReportErrorTests.nonXrpcError`, `ReportErrorTests.unknownXrpcStatus`, `ReportErrorTests.retryableStatus`, `ReportErrorTests.unanchoredUpstreamMessage`, `ReportErrorTests.fourDigitUpstreamStatus`, `ReportErrorTests.upstreamStatusExtraction` |

## Content labels

| RN source | Behaviour ported | Swift tests |
|---|---|---|
| `components/moderation/LabelPreference.tsx` (`LabelerLabelPreference`) — saved pref | a non-global label scoped to a labeler reads that labeler's map; a global label reads the global map; nothing stored reads the definition default | `ContentLabelTests.labelerScopedLookup`, `ContentLabelTests.globalLookupIgnoresLabelerScope`, `ContentLabelTests.unscopedLookup`, `ContentLabelTests.unsetLookup`, `ContentLabelTests.storedPrefWins`, `ContentLabelTests.defaultApplies`, `ContentLabelTests.warnDefaultKept` |
| `components/moderation/LabelPreference.tsx` — `canWarn` | a label that blurs nothing and warns nothing cannot be warned on, and a stored warn is coerced to ignore | `ContentLabelTests.cannotWarnWhenInert`, `ContentLabelTests.canWarnWithSeverity`, `ContentLabelTests.canWarnWithBlurs`, `ContentLabelTests.storedWarnCoercedOnInertLabel`, `ContentLabelTests.storedHideUntouchedOnInertLabel` |
| `components/moderation/LabelPreference.tsx` — adult gating | an adult label with adult content off is forced to hide and is not configurable; enabling adult content restores it | `ContentLabelTests.adultDisabledForcesHide`, `ContentLabelTests.adultDisabledOverridesStoredIgnore`, `ContentLabelTests.adultEnabledConfigurable`, `ContentLabelTests.nonAdultUnaffected` |
| `components/moderation/LabelPreference.tsx` — global labels | a definition the app owns is configured on the moderation screen, not on a labeler page | `ContentLabelTests.globalLabelDetection`, `ContentLabelTests.labelerLabelDetection`, `ContentLabelTests.globalLabelNotConfigurable` |
| `screens/Moderation/index.tsx` — global label rows | the four global labels in RN's order, shown only while adult content is on | `ContentLabelTests.globalRowOrder`, `ContentLabelTests.globalRowsGatedOnAdultContent` |
| `screens/Profile/Sections/Labels.tsx` — label list | the declared label values are deduped, looked up against the labeler's custom definitions then the global table, and filtered to configurable definitions | `ContentLabelTests.rowsDedupedAndOrdered`, `ContentLabelTests.unknownValueSkipped`, `ContentLabelTests.nonConfigurableSkipped`, `ContentLabelTests.declaredGlobalLabelResolves`, `ContentLabelTests.customShadowsGlobal`, `ContentLabelTests.bangValueSkipsCustom`, `ContentLabelTests.unknownValueNil` |
| `screens/Profile/Sections/Labels.tsx` — subscription gating | an unsubscribed labeler's rows render non-configurable | `ContentLabelTests.unsubscribedNotConfigurable`, `ContentLabelTests.subscribedConfigurable` |
| `lib/moderation.ts` (`filterUserFacingLabels`) | system labels and the viewer's own bot self-label are hidden | `ContentLabelTests.systemLabelsFiltered`, `ContentLabelTests.ownBotLabelFiltered`, `ContentLabelTests.botLabelWithoutAccount` |

## Muted words

| RN source | Behaviour ported | Swift tests |
|---|---|---|
| `components/dialogs/MutedWords.tsx` — submit | the target list is always `["tag"]`, plus `"content"` when "Text & tags" is chosen | `MutedWordsEditorTests.defaultTargets`, `MutedWordsEditorTests.tagsOnlyTargets`, `MutedWordsEditorTests.noSurfaceFallsBackToTags`, `MutedWordsEditorTests.excludeFollowingTarget` |
| `components/dialogs/MutedWords.tsx` — actor target | `exclude-following` when the exclude checkbox is ticked, else `all` | `MutedWordsEditorTests.actorTargetDefaultsToAll`, `MutedWordsEditorTests.excludeFollowingTarget` |
| `components/dialogs/MutedWords.tsx` — durations | forever mints no expiry; 24 hours, 7 days and 30 days mint the matching instant | `MutedWordsEditorTests.foreverNoExpiry`, `MutedWordsEditorTests.twentyFourHourExpiry`, `MutedWordsEditorTests.sevenDayExpiry`, `MutedWordsEditorTests.thirtyDayExpiry`, `MutedWordsEditorTests.durationDayCounts` |
| `components/dialogs/MutedWords.tsx` — validation | an empty or zero-width value is refused with RN's message; the RAW value is sent and the engine sanitizes | `MutedWordsEditorTests.emptyValueRejected`, `MutedWordsEditorTests.zeroWidthValueRejected`, `MutedWordsEditorTests.canSubmitEmpty`, `MutedWordsEditorTests.emptyValueMessage`, `MutedWordsEditorTests.rawValueSent` |
| `components/dialogs/MutedWords.tsx` — add | the `putPreferences` payload carries the muted word with its targets, actor target and optional expiry; a blank word writes nothing | `MutedWordsEditorTests.addWritesItems`, `MutedWordsEditorTests.addSanitizesStoredValue`, `MutedWordsEditorTests.addWritesExpiry`, `MutedWordsEditorTests.addBlankSkipsWrite` |
| `components/dialogs/MutedWords.tsx` — remove | the word is dropped from the items array, matching by id | `MutedWordsEditorTests.removeDropsWord` |
| `components/dialogs/MutedWords.tsx` — renew | the expiry is rewritten and the id kept; "Forever" clears it | `MutedWordsEditorTests.updateRewritesExpiry`, `MutedWordsEditorTests.renewForeverClearsExpiry` |
| `components/dialogs/MutedWords.tsx` — legacy | words without an id are migrated on the next write | `MutedWordsEditorTests.legacyMigration` |
| `components/dialogs/MutedWords.tsx` (`MutedWordRow`) | the row's target phrase, expiry state, excludes-following flag and id | `MutedWordsEditorTests.rowAppliesToContent`, `MutedWordsEditorTests.rowTagsOnly`, `MutedWordsEditorTests.rowsReversed`, `MutedWordsEditorTests.rowExpired`, `MutedWordsEditorTests.rowNotExpired`, `MutedWordsEditorTests.rowNoExpiry`, `MutedWordsEditorTests.rowExcludesFollowing`, `MutedWordsEditorTests.rowIdFromItems` |

## Blocked and muted accounts

| RN source | Behaviour ported | Swift tests |
|---|---|---|
| `state/queries/my-blocked-accounts.ts` | `app.bsky.graph.getBlocks` with `limit: 30`, cursor-paginated, keyed on `my-blocked-accounts` | `BlockedMutedListTests.roots`, `BlockedMutedListTests.pageSize`, `BlockedMutedListTests.blockedPagination`, `BlockedMutedListTests.emptyFirstPage`, `BlockedMutedListTests.firstPageFailure`, `BlockedMutedListTests.repeatedCursor` |
| `state/queries/my-muted-accounts.ts` | `app.bsky.graph.getMutes` with the same shape, keyed on `my-muted-accounts` | `BlockedMutedListTests.mutedPagination`, `BlockedMutedListTests.keysDiffer`, `BlockedMutedListTests.keyScopedToAccount` |
| `view/screens/ModerationBlockedAccounts.tsx` / `ModerationMutedAccounts.tsx` — removal | a row leaves the list immediately, with no change reported for an absent or unloaded entry | `BlockedMutedListTests.optimisticBlockedRemoval`, `BlockedMutedListTests.optimisticMutedRemoval`, `BlockedMutedListTests.optimisticRemovalAbsent`, `BlockedMutedListTests.optimisticRemovalUnloaded` |
| `state/queries/profile.ts` (`useProfileUnblockMutation`) | an unblock deletes the `app.bsky.graph.block` record, deriving the rkey from the block uri | `BlockedMutedListTests.unblockDeletesRecord`, `BlockedMutedListTests.rkeyExtraction` |
| `state/queries/profile.ts` (`useProfileUnmuteMutation`) | an unmute calls `app.bsky.graph.unmuteActor` with the actor did | `BlockedMutedListTests.unmutePostsActor` |

## Labeler services

| RN source | Behaviour ported | Swift tests |
|---|---|---|
| `state/queries/labeler.ts` (`useLabelerInfoQuery`) | a single labeler's detailed view via `app.bsky.labeler.getServices` with `detailed: true` | `LabelerServiceTests.detailedRead` |
| `state/queries/labeler.ts` (`useLabelersDetailedInfoQuery`) | a batch detailed read; an empty did list short-circuits | `LabelerServiceTests.batchRead`, `LabelerServiceTests.batchReadEmpty` |
| `state/queries/labeler.ts` — query keys | the batch key sorts its dids; the detailed key carries `persistedVersion: 1` | `LabelerServiceTests.batchKeyIsOrderInsensitive`, `LabelerServiceTests.detailedKeyIsPersisted` |
| `state/queries/preferences/moderation.ts` (`useMyLabelersQuery`) | the app's labelers lead, then the viewer's subscriptions, deduped; regional authorities can be excluded | `LabelerServiceTests.subscribedDids`, `LabelerServiceTests.subscribedDidsExcludingAuthorities`, `LabelerServiceTests.regionalAuthorityTest` |
| `state/queries/preferences/moderation.ts` (`useLabelDefinitionsQuery`) | the interpreted definitions keyed by labeler did, which is what `ModerationOpts.labelDefs` consumes | `LabelerServiceTests.labelDefinitions`, `LabelerServiceTests.noDefinitions`, `LabelerServiceTests.invalidDefinitionsDropped` |
| `lib/moderation.ts` (`isLabelerSubscribed`) | the app's own labelers are always subscribed; otherwise the preferences decide | `LabelerServiceTests.appLabelerAlwaysSubscribed`, `LabelerServiceTests.subscribedFromPreferences` |
| `screens/Moderation/index.tsx` (`unavailableDids`) | a subscribed labeler absent from the read is unavailable, except the app's and the regional authorities | `LabelerServiceTests.unavailableDids`, `LabelerServiceTests.unavailableExclusions` |
| `state/queries/labeler.ts` (`useLabelerSubscriptionMutation`) — invalid cleanup | a profile with no labeler association, or no profile at all, is invalid; a failed read cleans up nothing | `LabelerServiceTests.invalidNoAssociation`, `LabelerServiceTests.invalidNoProfile`, `LabelerServiceTests.validAssociation`, `LabelerServiceTests.failedProfileRead` |
| `state/queries/labeler.ts` — `MAX_LABELERS` | the cap is 20 and is checked AFTER the invalid-labeler cleanup; unsubscribing is never blocked | `LabelerServiceTests.maxLabelers`, `LabelerServiceTests.capReached`, `LabelerServiceTests.unsubscribeNotCapped`, `LabelerServiceTests.capCheckedAfterCleanup` |
| `state/queries/labeler.ts` (`useRemoveLabelersMutation`, `useLabelerSubscriptionMutation`) | the `labelersPref` is rewritten on remove/add; a duplicate add writes nothing; an invalid did is refused before any write | `LabelerServiceTests.removeLabelerWrites`, `LabelerServiceTests.addLabelerWrites`, `LabelerServiceTests.addExistingLabelerSkips`, `LabelerServiceTests.invalidDidRejected` |
| `state/queries/preferences/index.ts` (set-content-label mutation) | a labeler-scoped content label pref carries `labelerDid`; a global one omits it | `LabelerServiceTests.setLabelerScopedPref`, `LabelerServiceTests.setGlobalPref` |

## Deviations

Recorded in full in the package source; the material ones:

1. **Starter-pack NSID.** RN's `parseReportSubject` writes the typo'd
   `app.bsky.graph.starterPack` into the parsed subject. The port writes the
   REAL `app.bsky.graph.starterpack` and accepts the typo'd spelling on parse.
   Consequence: a labeler that declared only the typo'd collection no longer
   matches the collection filter
   (`ReportFlowTests.starterPackCollectionUsesRealNsid`).
2. **In-flight mutation variables.** RN's label rows read
   `mutateVariables?.visibility` ahead of the stored pref. This package has no
   mutation layer, so the fallback chain stops at the definition default
   (`ContentLabels.row`).
3. **Unreachable surface guard.** RN's muted-word submit guards on
   `!surfaces.length`, but `surfaces` always contains `"tag"`. The port keeps
   the guard for fidelity and documents it as unreachable; a no-selection draft
   mutes in tags only (`MutedWordsEditor.payload(for:)`).
4. **Global label detection.** RN tests `!labelDefinition.definedBy`; the Swift
   `LabelValueDefinition` always carries a `definedBy`, so the port tests
   `definedBy == "app.bsky"` (`ContentLabels.row`).
5. **Error shapes.** RN classifies the lex `XrpcResponseError`. The port takes
   its own ``ReportXrpcError`` shape and normalizes the Swift client's
   `XrpcError` into it, reading the same three fields RN reads
   (`ReportErrorClassifier`).
6. **No analytics.** RN's classification carries a fingerprint and tags for the
   analytics SDK. The port returns them for a Views layer to forward, but does
   not emit them.
7. **Moderation inbox.** Out of scope, deferred per the plan.

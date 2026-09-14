# Preferences tests-ported manifest

Maps the TypeScript sources this package ports to the Swift tests that cover
them. There is no upstream `*.test.ts` for preferences in the RN repo, so the
authoritative source is the `@bsky/sdk@1.1.0` action implementations
(`tools/golden-gen/node_modules/@bsky/sdk/dist/actions/preferences.js`) plus
the RN hydration composed in `src/state/queries/preferences/index.ts`.

## SDK action -> Swift API -> test

| SDK action | Swift API | Test |
|---|---|---|
| `getPreferences` | `PreferencesEngine.getPreferences()` | `HydrationTests.*`, `MigrationTests.*` |
| `updatePreferences` | `PreferencesEngine.update(_:)` | `SerializationTests.*` |
| `setAdultContentEnabled` | `setAdultContentEnabled(_:)` | `setAdultContentEnabledAppendsWhenAbsent`, `setAdultContentEnabledUpdatesInPlace` |
| `setContentLabelPref` | `setContentLabelPref(key:value:labelerDid:)` | `setContentLabelPref*` (4 tests) |
| `addSavedFeeds` | `addSavedFeeds(_:)` | `addSavedFeedsMintsIdsAndOrdersPinnedFirst` |
| `removeSavedFeeds` | `removeSavedFeeds(_:)` | `removeSavedFeedsFiltersById` |
| `updateSavedFeeds` | `updateSavedFeeds(_:)` | `updateSavedFeedsOnlyChangesPinned` |
| `overwriteSavedFeeds` | `overwriteSavedFeeds(_:)` | `overwriteSavedFeedsDedupesKeepingLastPosition` |
| `addPinnedFeed` (deprecated) | `addPinnedFeed(_:)` | `addPinnedFeedCreatesV1Pref` |
| `removePinnedFeed` (deprecated) | `removePinnedFeed(_:)` | `removePinnedFeedSkipsWhenPrefAbsent` |
| `setFeedViewPrefs` | `setFeedViewPrefs(feed:patch:)` | `setFeedViewPrefsCreatesHome`, `setFeedViewPrefsMergesExisting` |
| `setThreadViewPrefs` | `setThreadViewPrefs(_:)` | `setThreadViewPrefsMergesLabField` |
| `setPersonalDetails` | `setPersonalDetails(_:)` | `setPersonalDetailsWritesBirthDate`, `setPersonalDetailsNullClearsBirthDate` |
| `setInterestsPref` | `setInterestsPref(tags:)` | `setInterestsPrefReplacesTags` |
| `addMutedWord` | `addMutedWord(_:)` | `addMutedWord*` (3 tests) |
| `addMutedWords` | `addMutedWords(_:)` | `addMutedWordsAppliesInOrder` |
| `upsertMutedWords` (deprecated) | `upsertMutedWords(_:)` | covered by `addMutedWordsAppliesInOrder` |
| `updateMutedWord` | `updateMutedWord(_:)` | `updateMutedWordMatchesById`, `updateMutedWordFallsBackToValueMatchForLegacy` |
| `removeMutedWord` | `removeMutedWord(_:)` | `removeMutedWordMatchesFirstByIdOrValue`, `removeMutedWordWithoutPrefWritesUnchanged` |
| `removeMutedWords` | `removeMutedWords(_:)` | covered by `removeMutedWords` fan-out in `everyTypedMethodReachesTheServer` |
| `hidePost` | `hidePost(_:)` | `hidePostAppends`, `hidePostSkipsWhenAlreadyHidden` |
| `unhidePost` | `unhidePost(_:)` | `unhidePostFilters`, `unhidePostSkipsWhenPrefAbsent` |
| `addLabeler` | `addLabeler(_:)` | `addLabelerAppends`, `addLabelerSkipsDuplicate` |
| `removeLabeler` | `removeLabeler(_:)` | `removeLabelerFilters`, `removeLabelerSkipsWhenPrefAbsent` |
| `queueNudges` | `queueNudges(_:)` | `queueNudgesDeduplicates` |
| `dismissNudges` | `dismissNudges(_:)` | `dismissNudgesSkipsWhenPrefAbsent` |
| `setIsBetaUser` | `setIsBetaUser(_:)` | `setIsBetaUserPreservesOtherAppState` |
| `setActiveProgressGuide` | `setActiveProgressGuide(_:)` | `setActiveProgressGuideWritesAndClears` |
| `upsertNux` | `upsertNux(_:)` | `upsertNuxInsertsThenUpdates`, `upsertNuxRejectsUnknownProperty` |
| `removeNuxs` | `removeNuxs(_:)` | `removeNuxsFiltersById` |
| `setVerificationPrefs` | `setVerificationPrefs(_:)` | `setVerificationPrefsMerges` |
| `setPostInteractionSettings` | `setPostInteractionSettings(_:)` | `setPostInteractionSettingsReplacesExplicitly` |
| `updateLiveEventPreferences` | `updateLiveEventPreferences(_:)` | `updateLiveEventPreferencesTogglesAndTracksIds` |
| `updateSeenNotifications` | `updateSeenNotifications(_:)` | covered by `everyTypedMethodReachesTheServer` (own endpoint) |

## Behavior ports with no single SDK function

| Behavior | Source | Test |
|---|---|---|
| v1 -> v2 saved-feeds migration | `preferences.js` `getPreferences` (`agent.ts:687-746`) | `MigrationTests.*` (5 tests) |
| v1 legacy double-write on v2 write | `preferences.js` `updateSavedFeedsV2Prefs` | `v2WriteDoubleWritesExistingV1Pref`, `v2WriteIgnoresTimelineInV1CompatArrays` |
| Label-name remap + `show` normalization | `preferences.js` `LABEL_REMAP` / `normalizeVisibility` | `seedsDefaultLabelsThenAppliesStoredRemap`, `unknownLabelVisibilityPassesThrough` |
| Labeler merge with app labelers | `preferences.js` `getPreferences` | `mergesAppLabelerWithUserLabelers` |
| Muted-word `actorTarget` default | `preferences.js` `getPreferences` | `mutedWordsDefaultActorTargetToAll` |
| Muted-word value sanitization | `utils/muted-words.js` | `sanitizeStripsHashAndControlChars` |
| Saved-feed validation | `preferences.js` `validateSavedFeed` | `savedFeedValidationRejects*` |
| RMW serialization | `preferences.js` `serializedPrefsWrite` | `SerializationTests.*` (3 tests) |
| Open-union tolerance | `is$typedObject` dispatch + unknown `$type` | `OpenUnionTests.*` (5 tests) |
| Record position (map vs filter+concat) | `preferences.js` per-action shape | `RecordOrderTests.*` (2 tests) |

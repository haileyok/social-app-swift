# Settings — ported test manifest

Maps the RN source this package ports to the Swift tests that cover it.
Source repo: `~/bluesky/social-app` (read-only reference); paths below are
relative to its `src/`. Swift tests use Swift Testing (`import Testing`).

## Scope note: no dedicated unit tests upstream

The RN settings surfaces have **no dedicated unit tests**. There is no
`__tests__/` directory under `screens/Settings`, `screens/SavedFeeds.tsx`, or
`state/queries/app-passwords.ts`, and no `app-passwords.test.ts`,
`handle*.test.ts`, or settings-screen test file anywhere in `src`. The settings
behavior lives in the screen components (form validation, dialog state machines)
and in the query hooks (which XRPC call carries which body).

The cases below are therefore **semantic** ports: each Swift test asserts the
same rule, branch, state transition, or wire call the RN code implements. Every
XPRC assertion is against the exact method, params, and body the RN call site
passes; every validation assertion is against the exact regex, length, or
comparison the RN code performs; and the user-facing strings asserted on are
the exact copy from the RN module.

## Ported behavior — settings navigation

| RN source | RN behavior | Swift test |
|---|---|---|
| `routes.ts` (`Settings`, `AccountSettings`, `PrivacyAndSecuritySettings`, ...) | every route's path is fixed and stable | `SettingsRouteTests.pathsMatchRoutesTable` |
| `screens/Settings/*` (`LinkItem to=`) | the app-password screen hangs off privacy and security | `SettingsRouteTests.appPasswordsHangOffPrivacyAndSecurity` |
| `screens/Settings/ContentAndMediaSettings.tsx` | feed and thread preference screens hang off content and media | `SettingsRouteTests.feedAndThreadPrefsHangOffContentAndMedia` |
| `screens/Settings/Settings.tsx` | the root menu order is account, privacy, moderation, content, appearance, language, help, sign out | `SettingsRouteTests.rootMenuOrder` |
| `screens/Settings/Settings.tsx` (`destructive`) | sign out is the only destructive root row | `SettingsRouteTests.rootDestructiveRows` |
| `screens/Settings/AccountSettings.tsx` (`destructive`) | deactivate and delete are the destructive account rows | `SettingsRouteTests.accountMenuDestructiveRows` |
| `routes.ts` (tree) | every non-root route has a parent | `SettingsRouteTests.treeIsConnected` |
| `routes.ts` (paths) | a deep link resolves to its route, longest match wins | `SettingsRouteTests.pathResolution`, `pathResolutionPrefersLongestMatch` |

## Ported behavior — appearance

| RN source | RN behavior | Swift test |
|---|---|---|
| `state/persisted/schema.ts` (`defaults`) | `colorMode` defaults to `system`, `darkTheme` to `dim` | `AppearancePreferencesTests.defaults` |
| `alf/fonts.ts` (`getFontScale`) | an absent font scale reads as `0` | `AppearancePreferencesTests.defaults` |
| `alf/fonts.ts` (`getFontFamily`) | an absent font family reads as `theme` | `AppearancePreferencesTests.defaults` |
| `state/shell/color-mode.tsx` (`persisted.write('colorMode')`) | a color-mode change persists and survives a restart | `AppearancePreferencesTests.colorModeRoundTrip` |
| `state/shell/color-mode.tsx` (`persisted.write('darkTheme')`) | a dark-theme change persists and survives a restart | `AppearancePreferencesTests.darkThemeRoundTrip` |
| `state/shell/color-mode.tsx` (unset `darkTheme`) | clearing the variant reads back as the default | `AppearancePreferencesTests.darkThemeCleared` |
| `alf/fonts.ts` (`device.set(['fontScale'])`) | the font scale is device scope, not account scope | `AppearancePreferencesTests.fontScaleIsDeviceScoped` |
| `alf/fonts.ts` (`device.set(['fontFamily'])`) | the font family is device scope and round-trips | `AppearancePreferencesTests.fontFamilyRoundTrip` |
| `alf/fonts.ts` + `color-mode.tsx` | all four appearance values survive a reopen together | `AppearancePreferencesTests.fullAppearanceRoundTrip` |
| `alf/fonts.ts` (`fontScaleMultipliers`) | an unrecognized stored scale degrades to the default | `AppearancePreferencesTests.invalidStoredFontScaleFallsBack` |
| `alf/fonts.ts` (`getFontFamily() || 'theme'`) | an unrecognized stored family degrades to `theme` | `AppearancePreferencesTests.invalidStoredFontFamilyFallsBack` |
| `alf/fonts.ts` (`computeFontScaleMultiplier`) | the multipliers are `1 ± 0.0625`, with the unused extremes collapsing | `AppearancePreferencesTests.fontScaleMultipliers` |
| `alf/util/useColorModeTheme.ts` (`getThemeName`) | `light` wins over the OS scheme | `AppearancePreferencesTests.resolvedThemeLightIgnoresSystem` |
| `alf/util/useColorModeTheme.ts` (`getThemeName`) | `system` follows the scheme, else `darkTheme ?? 'dim'` | `AppearancePreferencesTests.resolvedThemeSystemFollowsScheme` |
| `alf/util/useColorModeTheme.ts` (`getThemeName`) | an explicit dark mode honours the variant | `AppearancePreferencesTests.resolvedThemeDarkUsesVariant` |
| `screens/Settings/AppearanceSettings.tsx` (`darkTheme ?? 'dim'`) | an unset variant under dark mode resolves to dim | `AppearancePreferencesTests.resolvedThemeUnsetVariantFallsBackToDim` |
| `screens/Settings/AppearanceSettings.tsx` (three groups) | the option rows and the dark-theme visibility rule | `AppearancePreferencesTests.optionRows`, `darkThemeGroupVisibility` |

## Ported behavior — app passwords

| RN source | RN behavior | Swift test |
|---|---|---|
| `components/AddAppPasswordDialog.tsx` (`regexFailError`) | names are `[a-zA-Z0-9-_ ]` only | `AppPasswordValidationTests.characterRule` |
| `components/AddAppPasswordDialog.tsx` (`error` derivation) | the character error shows on every keystroke | `AppPasswordValidationTests.displayError` |
| `components/AddAppPasswordDialog.tsx` (`chosenName`) | a blank field falls back to the generated name | `AppPasswordValidationTests.generatedNameFallback` |
| `components/AddAppPasswordDialog.tsx` (`length < 4`) | the chosen name must be at least 4 characters | `AppPasswordValidationTests.minimumLength` |
| `components/AddAppPasswordDialog.tsx` (length check) | the generated name is length-checked too | `AppPasswordValidationTests.generatedNameIsLengthChecked` |
| `components/AddAppPasswordDialog.tsx` (`passwords.find`) | the name must not already exist | `AppPasswordValidationTests.uniqueness` |
| `components/AddAppPasswordDialog.tsx` (check order) | length is checked before uniqueness | `AppPasswordValidationTests.lengthCheckedBeforeUniqueness` |
| `components/AddAppPasswordDialog.tsx` (`shadesOfBlue`) | the suggestion list is the blue-shade names | `AppPasswordValidationTests.suggestionList` |
| `state/queries/app-passwords.ts` (`listAppPasswords`) | a GET with no params | `AppPasswordServiceTests.listRequestShape` |
| `state/queries/app-passwords.ts` (`data.passwords`) | the list decodes name and privileged; never the plaintext | `AppPasswordServiceTests.listDecodes` |
| `state/queries/app-passwords.ts` (`createAppPassword`) | a POST of `{name, privileged}` | `AppPasswordServiceTests.createRequestBody` |
| `state/queries/app-passwords.ts` (`privileged`) | an explicit `false` is sent, not omitted | `AppPasswordServiceTests.createBodySendsFalsePrivileged` |
| `state/queries/app-passwords.ts` (`revokeAppPassword`) | a POST of `{name}` and nothing else | `AppPasswordServiceTests.revokeRequestBody` |
| `state/queries/app-passwords.ts` (create failure) | a rejected create throws rather than yielding an empty password | `AppPasswordServiceTests.createFailurePropagates` |
| `components/AddAppPasswordDialog.tsx` (`actuallyCreateAppPassword`) | a create uses the chosen name and the privileged flag | `AppPasswordStoreTests.createUsesChosenName` |
| `components/AddAppPasswordDialog.tsx` (blank name) | a blank name creates under the generated suggestion | `AppPasswordStoreTests.createFallsBackToGeneratedName` |
| `components/AddAppPasswordDialog.tsx` (validation) | a too-short name never reaches the network | `AppPasswordStoreTests.createRejectsShortNameWithoutNetwork` |
| `components/AddAppPasswordDialog.tsx` (uniqueness) | a duplicate name never reaches the network | `AppPasswordStoreTests.createRejectsDuplicateWithoutNetwork` |
| `components/AddAppPasswordDialog.tsx` (generic error) | a create failure shows the generic copy, keeping the raw message | `AppPasswordStoreTests.createFailureIsMapped` |
| `state/queries/app-passwords.ts` (`onSuccess` invalidate) | the list refreshes after a create | `AppPasswordStoreTests.listReloadsAfterCreate` |
| `screens/Settings/AppPasswords.tsx` (list) | the list is sorted for a stable screen order | `AppPasswordStoreTests.listIsSortedByName` |
| `screens/Settings/AppPasswords.tsx` (fetch error) | a list failure shows the fetch-error copy | `AppPasswordStoreTests.listFailureIsMapped` |
| `state/queries/app-passwords.ts` (delete mutation) | a revoke calls the endpoint and refreshes the list | `AppPasswordStoreTests.revoke` |
| `screens/Settings/AppPasswords.tsx` (delete error) | a revoke failure is mapped and the list is unchanged | `AppPasswordStoreTests.revokeFailureIsMapped` |
| `components/AddAppPasswordDialog.tsx` (`passwords` prop) | form validation reads the loaded list | `AppPasswordStoreTests.formValidationUsesLoadedList` |

## Ported behavior — handle change

| RN source | RN behavior | Swift test |
|---|---|---|
| `lib/strings/handles.ts` (`createFullHandle`) | name and domain are joined, dots trimmed | `HandleRulesTests.createFullHandle` |
| `lib/strings/handles.ts` (`makeValidHandle`) | truncate to 20, lowercase, strip | `HandleRulesTests.makeValidHandle` |
| `lib/strings/handles.ts` (`isInvalidHandle`) | the appview sentinel is recognized | `HandleRulesTests.isInvalidHandle` |
| `lib/strings/handles.ts` (`validateServiceHandle`) | the per-field checks pass for a valid name | `HandleRulesTests.validateServiceHandle` |
| `lib/strings/handles.ts` (`handleChars`) | a dot in the name fails the character rule | `HandleRulesTests.nameWithDotRejected` |
| `lib/strings/handles.ts` (`hyphenStartOrEnd`) | an edge hyphen fails; an interior one is fine | `HandleRulesTests.hyphenAtEdgeRejected` |
| `lib/strings/handles.ts` (`frontLengthNotTooShort`) | shorter than 3 fails | `HandleRulesTests.shortNameRejected` |
| `lib/strings/handles.ts` (`frontLengthNotTooLong`) | longer than 18 fails | `HandleRulesTests.longNameRejected` |
| `lib/strings/handles.ts` (`!str` short-circuit) | an empty name passes the character rule | `HandleRulesTests.emptyNameCharacterRule` |
| `components/ChangeHandleDialog.tsx` (`isInvalid`) | the field state uses three checks, not all five | `HandleRulesTests.invalidUsesThreeChecks` |
| `components/ChangeHandleDialog.tsx` (initial state) | the dialog opens on the provided-handle page | `ChangeHandleFlowTests.initialState` |
| `components/ChangeHandleDialog.tsx` (`setPage`) | switching pages clears the verification result | `ChangeHandleFlowTests.pageSwitchResetsVerification` |
| `components/ChangeHandleDialog.tsx` (`resetVerification`) | typing a domain resets the verification | `ChangeHandleFlowTests.typingDomainResetsVerification` |
| `components/ChangeHandleDialog.tsx` (`Save new handle`) | a valid subdomain submits the assembled handle | `ChangeHandleFlowTests.submitServiceHandle` |
| `components/ChangeHandleDialog.tsx` (taken handle) | a taken handle fails before the update call | `ChangeHandleFlowTests.submitServiceHandleTaken` |
| `components/ChangeHandleDialog.tsx` (`disabled={isInvalid}`) | an invalid subdomain never reaches the network | `ChangeHandleFlowTests.submitServiceHandleInvalidWithoutNetwork`, `submitServiceHandleTooShortWithoutNetwork` |
| `state/queries/handle-availability.ts` (typeahead failures) | an availability-check failure does not block submission | `ChangeHandleFlowTests.availabilityFailureDoesNotBlock` |
| `components/ChangeHandleDialog.tsx` (`ChangeHandleError`) | a PDS rejection maps through the known-message table | `ChangeHandleFlowTests.submitMapsUpdateError` |
| `components/ChangeHandleDialog.tsx` (`verify` mutation) | a matching resolved DID verifies the domain | `ChangeHandleFlowTests.verifyDomainMatches` |
| `components/ChangeHandleDialog.tsx` (`DidMismatchError`) | a different DID is a mismatch carrying the received DID | `ChangeHandleFlowTests.verifyDomainMismatch` |
| `components/ChangeHandleDialog.tsx` (verify failure) | an unresolvable domain reports unresolved | `ChangeHandleFlowTests.verifyDomainUnresolved` |
| `components/ChangeHandleDialog.tsx` (`domain.trim()`) | an empty domain is not verified | `ChangeHandleFlowTests.verifyDomainEmpty` |
| `components/ChangeHandleDialog.tsx` (`changeHandle({handle: domain})`) | a verified domain is written verbatim | `ChangeHandleFlowTests.submitVerifiedDomain` |
| `components/ChangeHandleDialog.tsx` (`isVerified` gate) | an unverified domain cannot be submitted | `ChangeHandleFlowTests.submitUnverifiedDomainRefused` |
| `components/ChangeHandleDialog.tsx` (reserved notice) | a `.bsky.social` handle is flagged as staying reserved | `ChangeHandleFlowTests.currentHandleStaysReserved` |
| `components/ChangeHandleDialog.tsx` (`useUpdateHandleMutation`) | state observers see each transition | `ChangeHandleFlowTests.listenerNotified` |
| `components/ChangeHandleDialog.tsx` (`ChangeHandleError`) | all six known server messages map to their copy | `ChangeHandleFlowTests.errorMapping` |
| `state/queries/handle.ts` (`updateHandle`) | the update posts the handle to the PDS | (see deviations 5) |

## Ported behavior — account lifecycle and export

| RN source | RN behavior | Swift test |
|---|---|---|
| `components/DeleteAccountDialog.tsx` (`Step.SEND_CODE`) | the dialog opens on the send-code step | `DeleteAccountFlowTests.initialState` |
| `components/DeleteAccountDialog.tsx` (`sendEmail`) | a code request advances to the verify step | `DeleteAccountFlowTests.sendCodeAdvances` |
| `components/DeleteAccountDialog.tsx` (`emailSentCount`) | a resend increments the counter | `DeleteAccountFlowTests.sendCodeTwice` |
| `components/DeleteAccountDialog.tsx` (send failure) | a failed request records the error and stays put | `DeleteAccountFlowTests.sendCodeFailure` |
| `components/DeleteAccountDialog.tsx` (`handleDeleteAccount`) | the confirm step is reached explicitly | `DeleteAccountFlowTests.beginConfirmation` |
| `components/DeleteAccountDialog.tsx` (`confirmCode.replace`) | whitespace is stripped from the code before sending | `DeleteAccountFlowTests.confirmDeletionSendsSanitizedCode` |
| `components/DeleteAccountDialog.tsx` (`chatClient.call` first) | the pre-delete (chat) call runs before the deletion | `DeleteAccountFlowTests.preDeleteHookRunsFirst` |
| `components/DeleteAccountDialog.tsx` (chat failure) | a failed pre-delete aborts the deletion | `DeleteAccountFlowTests.preDeleteHookFailureAborts` |
| `components/DeleteAccountDialog.tsx` (delete failure) | a failure resets the code and password and returns to verify | `DeleteAccountFlowTests.confirmDeletionFailureResets` |
| `components/DeleteAccountDialog.tsx` (`Invalid did`) | a missing DID fails before any network call | `DeleteAccountFlowTests.confirmDeletionRequiresDID` |
| `components/DeleteAccountDialog.tsx` (`PASSWORD_MIN_LENGTH`) | the password rule is `>= 8` | `DeleteAccountFlowTests.passwordRule` |
| `components/DeleteAccountDialog.tsx` (`WHITESPACE_RE`) | every whitespace character is stripped | `DeleteAccountFlowTests.confirmationCodeSanitizer` |
| `components/DeactivateAccountDialog.tsx` (`deactivateAccount`) | a deactivation calls the endpoint once | `DeactivateAccountFlowTests.deactivate` |
| `components/DeactivateAccountDialog.tsx` (`Bad token scope`) | the app-password scope has its specific message | `DeactivateAccountFlowTests.deactivateAppPasswordScope` |
| `components/DeactivateAccountDialog.tsx` (default error) | any other failure gets the generic message | `DeactivateAccountFlowTests.deactivateGenericFailure` |
| `components/ExportCarDialog.tsx` (`getRepo({did})`) | the repo export is a GET with the DID and the CAR type | `ExportDataTests.repoRequest`, `repoURL` |
| `components/ExportCarDialog.tsx` (`repo.car`) | the export is saved as `repo.car` | `ExportDataTests.repoRequest` |
| `components/ExportCarDialog.tsx` (bytes) | the response is consumed as raw bytes, not JSON | `ExportDataTests.fetchRepoBytes` |
| `components/ExportCarDialog.tsx` (`currentAccount`) | no session means no export request | `ExportDataTests.storeExportRequestWithoutSession` |

## Ported behavior — saved feeds

| RN source | RN behavior | Swift test |
|---|---|---|
| `screens/SavedFeeds.tsx` (`pinnedFeeds`/`unpinnedFeeds`) | the list is partitioned pinned-first | `SavedFeedsEditorTests.pinnedFirstPartition` |
| `screens/SavedFeeds.tsx` (partition) | the partition is stable within each block | `SavedFeedsEditorTests.partitionPreservesRelativeOrder` |
| `screens/SavedFeeds.tsx` (`onTogglePinned`) | pinning moves the item into the pinned block | `SavedFeedsEditorTests.togglePinnedMovesIntoBlock` |
| `screens/SavedFeeds.tsx` (`onPressRemove`) | only unpinned items are removable | `SavedFeedsEditorTests.removeOnlyUnpinned` |
| `screens/SavedFeeds.tsx` (`onMoveUp`) | moving up swaps with the predecessor; the first is blocked | `SavedFeedsEditorTests.movePinnedUp` |
| `screens/SavedFeeds.tsx` (`onMoveDown`) | moving down swaps with the successor; the last is blocked | `SavedFeedsEditorTests.movePinnedDown` |
| `screens/SavedFeeds.tsx` (bounds) | an out-of-range move is a no-op | `SavedFeedsEditorTests.moveOutOfRange` |
| `screens/SavedFeeds.tsx` (drag reorder) | a reorder replaces the pinned block and keeps the tail | `SavedFeedsEditorTests.reorderPinned` |
| `screens/SavedFeeds.tsx` (drag reorder) | a reorder that changes the id set is rejected | `SavedFeedsEditorTests.reorderPinnedRejectsWrongSet` |
| `screens/SavedFeeds.tsx` (`hasUnsavedChanges`) | the dirty flag tracks edits, and discard resets it | `SavedFeedsEditorTests.dirtyTracking` |
| `screens/SavedFeeds.tsx` (`NoSavedFeedsOfAnyType`) | an empty list reports empty | `SavedFeedsEditorTests.emptyState` |
| `screens/SavedFeeds.tsx` (`NoSavedFeedsOfAnyType`) | the recommended set is discover + following, both pinned | `SavedFeedsEditorTests.recommendedItems` |
| `app.bsky.actor.defs.SavedFeed` | an item round-trips through its preference record | `SavedFeedsEditorTests.prefObjectRoundTrip` |
| `app.bsky.actor.defs.SavedFeed` | a record missing a member does not decode | `SavedFeedsEditorTests.prefObjectMissingField` |
| `lib/constants.ts` (`RECOMMENDED_SAVED_FEEDS`) | the type is inferred from the value | `SavedFeedsEditorTests.typeInference` |
| `state/queries/preferences/index.ts` (read) | the store's editor reflects the loaded preferences | `SavedFeedsStoreTests.loadsFromPreferences` |
| `screens/SavedFeeds.tsx` (local edits) | edits are local until the save | `SavedFeedsStoreTests.editsAreLocalUntilSave` |
| `screens/SavedFeeds.tsx` (`onSaveChanges`) | saving writes the arranged order in one call | `SavedFeedsStoreTests.saveWritesArrangedOrder` |
| `state/queries/preferences/index.ts` (`overwriteSavedFeeds`) | the engine re-partitions pinned-first on write | `SavedFeedsStoreTests.engineOrdersPinnedFirst` |
| `screens/SavedFeeds.tsx` (`onPressRemove`) | a removal is written through on save | `SavedFeedsStoreTests.saveRemoval` |
| `screens/SavedFeeds.tsx` (discard) | discarding restores the loaded list | `SavedFeedsStoreTests.discardEdits` |
| `screens/Feeds/NoSavedFeedsOfAnyType.tsx` | seeding the recommended feeds adds both, pinned | `SavedFeedsStoreTests.addRecommended` |
| `screens/SavedFeeds.tsx` (save failure) | a save failure surfaces the contact error | `SavedFeedsStoreTests.saveFailureIsMapped` |

## Ported behavior — feed, thread, and content-label preferences

| RN source | RN behavior | Swift test |
|---|---|---|
| `state/queries/preferences/const.ts` (`DEFAULT_HOME_FEED_PREFS`) | the following-feed defaults show replies/reposts/quotes | `FollowingFeedPreferencesTests.defaults` |
| `screens/Settings/FollowingFeedPreferences.tsx` (`showReplies`) | the show model inverts the stored `hide*` fields | `FollowingFeedPreferencesTests.fromStored` |
| `screens/Settings/FollowingFeedPreferences.tsx` (`mergeFeedEnabled`) | an absent merge flag reads as false | `FollowingFeedPreferencesTests.storedAbsentMergeFlag` |
| `state/queries/preferences/index.ts` (`setFeedViewPrefs`) | each toggle produces the negated `hide*` patch | `FollowingFeedPreferencesTests.patchesNegate` |
| `screens/Settings/FollowingFeedPreferences.tsx` (`lab_mergeFeedEnabled`) | the merge flag is written positively | `FollowingFeedPreferencesTests.patchesNegate` |
| `state/queries/preferences/index.ts` (`{feed: 'home'}`) | the feed key is `home` | `FollowingFeedPreferencesTests.feedKey` |
| `state/queries/preferences/useThreadPreferences.ts` (`normalizeSort`) | anything but oldest/newest is `top` | `ThreadPreferencesTests.normalizeSort` |
| `state/queries/preferences/useThreadPreferences.ts` (`normalizeView`) | the boolean becomes tree/linear | `ThreadPreferencesTests.normalizeView` |
| `state/queries/preferences/const.ts` (`DEFAULT_THREAD_VIEW_PREFS`) | the default sort is `top` and the view linear | `ThreadPreferencesTests.defaults` |
| `state/queries/preferences/useThreadPreferences.ts` (`savePrefs`) | the patch writes the sort and the tree boolean | `ThreadPreferencesTests.patch` |
| `screens/Settings/FollowingFeedPreferences.tsx` (`setFeedViewPref`) | a toggle writes the `home` pref with the negated field | `PreferencesMutationTests.followingFeedToggleWritesNegatedField` |
| `screens/Settings/FollowingFeedPreferences.tsx` (`lab_mergeFeedEnabled`) | the merge toggle is written positively | `PreferencesMutationTests.mergeFeedTogglePositive` |
| `state/queries/preferences/index.ts` (`setFeedViewPrefs`) | a toggle does not clobber a sibling field | `PreferencesMutationTests.togglesDoNotClobberSiblings` |
| `screens/Settings/ThreadPreferences.tsx` (`setSort`/`setView`) | the thread write sends the exact patch fields | `PreferencesMutationTests.threadPreferencesWrite` |
| `screens/Settings/FollowingFeedPreferences.tsx` (write failure) | a write failure leaves the local model alone | `PreferencesMutationTests.feedToggleFailureLeavesModel` |
| `state/queries/preferences/index.ts` (read) | the stored `home` pref is interpreted into the model | `PreferencesMutationTests.loadInterpretsStoredFeedPrefs` |
| `screens/Moderation/index.tsx` (`adultContentEnabled &&`) | the label rows are hidden while adult content is off | `ContentLabelMatrixTests.hiddenWhenAdultContentOff` |
| `screens/Moderation/index.tsx` (order) | the four configurable labels appear in screen order | `ContentLabelMatrixTests.rowOrder` |
| `@bsky/sdk/moderation` (`DEFAULT_LABEL_SETTINGS`) | an unset label takes the definition's default | `ContentLabelMatrixTests.defaultsComeFromDefinitions` |
| `components/moderation/LabelPreference.tsx` (`savedPref ?? 'warn'`) | a stored preference overrides the default | `ContentLabelMatrixTests.storedPreferenceWins` |
| `components/moderation/LabelPreference.tsx` (`normalizeVisibility`) | the legacy `show` value normalizes to ignore | `ContentLabelMatrixTests.legacyShowValue` |
| `components/moderation/LabelPreference.tsx` (`?? 'warn'`) | an unknown stored value falls back to warn | `ContentLabelMatrixTests.unknownValueFallsBackToWarn` |
| `lib/moderation/useGlobalLabelStrings.ts` | the row copy is the global label strings | `ContentLabelMatrixTests.rowCopy` |
| `components/moderation/LabelPreference.tsx` (`labelOptions`) | the three options and their Show/Warn/Hide labels | `ContentLabelMatrixTests.options` |
| `components/moderation/LabelPreference.tsx` (`values[0]` write) | the write uses the stored wire value | `ContentLabelMatrixTests.storedValues` |
| `state/queries/preferences/index.ts` (`setContentLabelPref`) | a global change carries no labeler scope | `ContentLabelMatrixTests.globalChange` |
| `state/queries/preferences/moderation.ts` (`interpretLabelValueDefinitions`) | only configurable labeler labels are offered | `ContentLabelMatrixTests.labelerRows` |
| `components/moderation/LabelPreference.tsx` (`disabled`) | labeler rows are disabled while adult content is off | `ContentLabelMatrixTests.labelerRowsDisabled` |
| `state/queries/preferences/index.ts` (`usePreferencesQuery`) | the store derives the matrix from loaded preferences | `ContentLabelMatrixTests.storeDerivesMatrix`, `storeMatrixEmptyWhenOff` |
| `state/queries/preferences/index.ts` (`setContentLabelPref` aliases) | the engine double-writes the legacy alias | `ContentLabelMatrixTests.setLabelVisibilityWritesAlias` |
| `state/queries/preferences/index.ts` (`labelerDid`) | a scoped label pref carries the DID and skips the alias | `ContentLabelMatrixTests.setScopedLabelVisibility` |
| `state/queries/preferences/index.ts` (`setAdultContentEnabled`) | the adult toggle writes and gates the derived rows | `ContentLabelMatrixTests.setAdultContent` |

## Ported behavior — languages

| RN source | RN behavior | Swift test |
|---|---|---|
| `locale/languages.ts` (`APP_LANGUAGES`) | the UI language table, in source order | `LanguagesTests.appLanguages` |
| `locale/languages.ts` (`APP_LANGUAGES`) | app-language codes are unique | `LanguagesTests.appLanguageCodesUnique` |
| `locale/languages.ts` (`LANGUAGES`) | the ISO table has one entry per `code2` | `LanguagesTests.languageCodesUnique` |
| `locale/languages.ts` (`LANGUAGES`) | the table's shape and spot-checked entries | `LanguagesTests.languageTableShape` |
| `locale/helpers.ts` (`code3ToCode2`/`code2ToCode3`) | the two code lookups, with pass-through for unknowns | `LanguagesTests.codeConversion` |
| `locale/helpers.ts` (`codeToLanguageName`) | the English name fallback | `LanguagesTests.nameLookup` |
| `locale/helpers.ts` (`fixLegacyLanguageCode`) | the Java-era codes are mapped | `LanguagesTests.legacyCodes` |
| `locale/helpers.ts` (`sanitizeAppLanguageSetting`) | a valid code passes through | `AppLanguageSanitizerTests.validCode` |
| `locale/helpers.ts` (`sanitizeAppLanguageSetting`) | a comma-separated value yields its first language | `AppLanguageSanitizerTests.commaSeparatedValue` |
| `locale/helpers.ts` (`sanitizeAppLanguageSetting`) | an unshipped first value is skipped | `AppLanguageSanitizerTests.unshippedFirstValue` |
| `locale/helpers.ts` (`sanitizeAppLanguageSetting`) | nothing recognizable falls back to `en` | `AppLanguageSanitizerTests.fallback` |
| `locale/helpers.ts` (`fixLegacyLanguageCode` use) | the legacy code is repaired before matching | `AppLanguageSanitizerTests.legacyCodeRepaired` |
| `locale/helpers.ts` (`langs.split(',')`) | empty segments do not break the scan | `AppLanguageSanitizerTests.emptySegments` |
| `screens/Settings/LanguageSettings.tsx` (`possibleLanguages`) | the option list is recent + selected + primary, deduped | `LanguagePreferencesTests.possibleContentLanguages` |
| `screens/Settings/LanguageSettings.tsx` (`possibleLanguages`) | unknown codes are skipped | `LanguagePreferencesTests.possibleLanguagesSkipUnknown` |
| `screens/Settings/LanguageSettings.tsx` (`onChangePrimaryLanguage`) | an empty value is ignored | `LanguagePreferencesTests.setPrimaryIgnoresEmpty` |
| `screens/Settings/LanguageSettings.tsx` (`onChangeAppLanguage`) | the app language is sanitized before saving | `LanguagePreferencesTests.setAppLanguageSanitizes` |
| `state/persisted/schema.ts` (`languagePrefs`) | the model round-trips through the persisted slice | `LanguagePreferencesTests.persistedRoundTrip` |

## Ported behavior — store assembly

| RN source | RN behavior | Swift test |
|---|---|---|
| `screens/Settings/*` (section state) | every section starts idle with defaults | `SettingsStoreTests.initialSectionState` |
| `state/queries/*` (parallel loads) | each section loads independently | `SettingsStoreTests.loadAll` |
| `state/queries/preferences/index.ts` (query error) | one failing section does not stop the others | `SettingsStoreTests.loadAllIsResilientToOneFailure` |
| `state/queries/app-passwords.ts` (refetch) | observers are notified only on an actual change | `SettingsStoreTests.listenerNotifiesOnChange` |
| `routes.ts` (scope) | the exposed route tree is the v1 scope | `SettingsStoreTests.routesInScope` |
| `screens/Settings/SettingsList.tsx` | the store serves the menu sections per route | `SettingsStoreTests.sectionsForRoute` |
| `state/queries/preferences/const.ts` (`DEFAULT_HOME_FEED_PREFS`) | a missing `home` entry takes the engine default | `SettingsStoreTests.homeFeedPreferenceDefault` |
| `state/queries/preferences/index.ts` (`res.feedViewPrefs.home`) | a stored `home` entry is read, not defaulted | `SettingsStoreTests.homeFeedPreferenceStored` |

## Deviations and open questions

1. **Appearance reads `hydrate()` itself.** `PersistedStore` starts at its
   defaults and only reads the file when `hydrate()` is called, which RN does
   once at boot. `AppearancePreferencesStore.snapshot()` calls it too, so the
   store is correct standalone. It is idempotent, so the double call is safe.

2. **The dark-theme resolution matches `getThemeName`, not the screen's
   phrasing.** A `system` color mode on a dark OS scheme resolves to
   `darkTheme ?? 'dim'` - which for the default `darkTheme` is **dim**, not
   `dark`. The appearance screen's copy ("Dark theme") makes it easy to assume
   `dark`; the code and the test both say `dim`.

3. **The interpreted `Preferences` type has no public initializer.** It is
   built only by the engine's hydration path, so `ContentLabelMatrix` takes a
   `ContentLabelInputs` value (the adult flag plus the stored visibility maps)
   rather than the whole `Preferences`. A convenience overload over
   `Preferences` exists for callers that already hold one, and the store uses it.

4. **The patch types' member lists are internal.** `FeedViewPrefPatch` and
   `ThreadViewPrefPatch` expose their wire fields only within `Preferences`, so
   the settings surface states the mappings itself (`wireFields(for:)` /
   `wireFields`). The tests assert both the mapping *and* the resulting stored
   preference record, so the two cannot drift without a failure.

5. **`updateHandle` / `resolveHandle` are not asserted at the wire level.**
   `HandleService` is a protocol and the flow tests use a fake, so the flow's
   branching is covered but the exact URL and body of
   `com.atproto.identity.updateHandle` are not. The app-password service *is*
   asserted byte-for-byte, as the task requires; extending the same treatment to
   the handle service is a follow-up.

6. **The chat-service delete call is a hook.** `DeleteAccountDialog.tsx` calls
   `chat.bsky.actor.deleteAccount` before the PDS deletion. `SettingsLogic`
   does not depend on a chat client, so `DeleteAccountFlow` takes an
   `onBeforeDelete` closure; the test asserts the ordering and that a failure
   there aborts.

7. **The language tables are transcribed, not generated.** RN localizes
   language names at runtime through `Intl.DisplayNames`. The Swift tables bake
   in the English names, which is the same fallback RN uses when
   `Intl.DisplayNames` is unavailable. A future localization layer can replace
   the names while keeping the codes.

8. **`getCheckout` is exposed but unused by RN's dialog.** The task names it,
   so `ExportData.checkoutRequest` builds it and is tested; RN only calls
   `getRepo`. Both are CAR GETs of the same shape.

9. **Beta features, app icons, and the moderation inbox are out of scope.**
   Their routes are enumerated with `isInScope == false` so the navigation tree
   mirrors `routes.ts`, and the menu builder skips them.

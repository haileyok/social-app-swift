# Composer — ported test manifest

Maps the RN source this package ports to the Swift tests that cover it.
Source repo: `~/bluesky/social-app` (read-only reference); paths below are
relative to its `src/`. Swift tests use Swift Testing (`import Testing`).

The RN composer has almost no dedicated unit tests:
`view/com/composer/state/composer.test.ts` covers only two `add_post` cases, and
`state/videoProgress.test.ts` covers the progress bands. Everything else is
component-tested. The cases below are therefore **semantic** ports — each Swift
test asserts the same rule or branch the RN code implements — plus the two
genuinely ported suites, marked **(ported 1:1)** below.

## Ported behaviour

| RN source | RN behaviour / test | Swift test |
|---|---|---|
| `view/com/composer/state/composer.test.ts` **(ported 1:1)** | `add_post` selects the appended post and requests focus | `ComposerReducerTests.addPostAppendsAndFocuses` |
| `view/com/composer/state/composer.test.ts` **(ported 1:1)** | `add_post` inserts mid-thread and keeps later posts after the new one | `ComposerReducerTests.addPostInsertsInTheMiddle` |
| `view/com/composer/state/videoProgress.test.ts` **(ported 1:1)** | `didSkipVideoCompression` distinguishes a real skip from a failed compression attempt | `VideoReducerTests.skipDetection` |
| `view/com/composer/state/videoProgress.test.ts` **(ported 1:1)** | each phase maps onto one continuous timeline | `VideoReducerTests.phaseMapping` |
| `view/com/composer/state/videoProgress.test.ts` **(ported 1:1)** | invalid phase progress is clamped | `VideoReducerTests.phaseClamping` |
| `view/com/composer/state/videoProgress.test.ts` **(ported 1:1)** | `videoProgressWithinPhase` maps global progress back to a phase | `VideoReducerTests.withinPhase` |
| `view/com/composer/state/videoProgress.test.ts` **(ported 1:1)** | `advanceVideoProgress` never moves backwards | `VideoReducerTests.advanceIsMonotonic` |
| `view/com/composer/Composer.tsx` (`canPost`) | an empty thread cannot be published | `ComposerValidationTests.emptyThreadCannotPost` |
| `view/com/composer/Composer.tsx` (`canPost`) | a post at exactly `MAX_GRAPHEME_LENGTH` passes; one grapheme over fails | `ComposerValidationTests.exactlyAtTheLimitCanPost`, `.justOverTheLimitCannotPost` |
| `view/com/composer/Composer.tsx` (`canPost`) | an empty post is exempt from the limit and video checks (the `every` short-circuit) | `ComposerValidationTests.emptyPostIsExemptFromLimit`, `.trailingEmptyPostDoesNotBlock` |
| `view/com/composer/Composer.tsx` (`canPost`) | a video in `error` blocks publishing | `ComposerValidationTests.failedVideoBlocksPublishing` |
| `view/com/composer/Composer.tsx` (`canPost`) | `hasUnavailableChatInvite` blocks publishing | `ComposerValidationTests.unavailableChatInviteBlocks` |
| `view/com/composer/Composer.tsx` (`missingAltError`) | alt text is only required when the account demands it | `ComposerValidationTests.altTextNotRequiredByDefault` |
| `view/com/composer/Composer.tsx` (`missingAltError`) | an image / GIF / video without alt text blocks when required | `ComposerValidationTests.imageWithoutAltBlocksWhenRequired`, `.gifWithoutAltBlocksWhenRequired`, `.videoWithoutAltBlocksWhenRequired` |
| `view/com/composer/Composer.tsx` (`missingAltError`) | a video already in `error` reports the video error, not the alt-text one | `ComposerValidationTests.erroredVideoIsNotAltTextError` |
| `view/com/composer/Composer.tsx` (`isEmptyPost`) | media-only posts are not empty; whitespace-only posts are | `ComposerValidationTests.mediaOnlyPostIsNotEmpty`, `.whitespaceOnlyPostIsEmpty` |
| `view/com/composer/Composer.tsx` (`getFilteredThread`) | no empty posts, trailing-only, and non-trailing classification | `ComposerValidationTests.noEmptyPosts`, `.trailingEmptyPosts`, `.nonTrailingEmptyPosts` |
| `view/com/composer/state/composer.ts` (`embed_add_images`) | <= 4 images use `app.bsky.embed.images`; a fifth promotes to `gallery` | `ComposerReducerTests.smallImageSetUsesImages`, `.fifthImagePromotesToGallery` |
| `view/com/composer/state/composer.ts` (`imagesToMediaVariant`) | a gallery shrinking to <= 4 demotes back to the legacy variant | `ComposerReducerTests.galleryDemotesOnShrink` |
| `view/com/composer/state/composer.ts` (`imagesToMediaVariant`) | image count is capped at `MAX_GALLERY_IMAGES` | `ComposerReducerTests.galleryCapEnforced` |
| `view/com/composer/state/composer.ts` (media exclusivity) | adding a video to images (or a GIF to a video) is a no-op | `ComposerReducerTests.videoOntoImagesIsNoop`, `.gifOntoVideoIsNoop` |
| `view/com/composer/state/composer.ts` (`if (!state.embed.link) nextLabels = []`) | removing the last media clears labels unless a link card remains | `ComposerReducerTests.removingLastImageClearsLabels`, `.removingLastImageKeepsLabelsWithLink`, `.removingLinkKeepsLabelsWithMedia`, `.removingLinkClearsLabelsWithoutMedia`, `.removingVideoClearsLabels` |
| `view/com/composer/state/composer.ts` (`embed_add_uri`) | post URLs become quotes; other URLs become link cards; neither overwrites | `ComposerReducerTests.postUrlBecomesQuote`, `.nonPostUrlBecomesLink`, `.secondUriDoesNotOverwrite` |
| `view/com/composer/state/composer.ts` (`embed_update_image`) | updating an image's alt text preserves its place | `ComposerReducerTests.updateImageAltText` |
| `view/com/composer/state/composer.ts` (`embed_update_gif`) | GIF alt text is editable | `ComposerReducerTests.updateGifAlt` |
| `view/com/composer/state/composer.ts` (`remove_post`) | refuses the last post and steps the active index back | `ComposerReducerTests.removeLastPostRefused`, `.removePostMovesActiveIndex`, `.removeFirstPostClampsIndex` |
| `view/com/composer/state/composer.ts` (`focus_post`) | focusing does not mark the composer dirty | `ComposerReducerTests.focusDoesNotDirty` |
| `view/com/composer/state/composer.ts` (`composerReducer`) | an unknown post id is a no-op | `ComposerReducerTests.unknownPostIdIgnored` |
| `view/com/composer/state/composer.ts` (`createComposerState`) | `initText` extracts post URLs as quotes and other links as link cards | `ComposerReducerTests.initTextSuggestsQuote`, `.initTextSuggestsLinkCard`, `.initTextSuggestsOneOfEach` |
| `view/com/composer/state/composer.ts` (`createComposerState`) | an explicit `initQuoteUri` wins over a detected one | `ComposerReducerTests.explicitQuoteWins` |
| `view/com/composer/state/composer.ts` (`createComposerState`) | `initMention` prefills `@handle` and detects facets | `ComposerReducerTests.initMentionPrefillsAndDetects` |
| `view/com/composer/state/composer.ts` (`createComposerState`) | `initInteractionSettings` seeds the threadgate and postgate | `ComposerReducerTests.initSettingsSeedGates` |
| `view/com/composer/state/composer.ts` (`restore_from_draft`) | restores posts, gates and draft id, and clears the dirty flag | `ComposerReducerTests.restoreFromDraft` |
| `view/com/composer/state/composer.ts` (`clear` / `mark_saved`) | reset to blank; record the saved draft id | `ComposerReducerTests.clearResets`, `.markSaved` |
| `view/com/composer/state/composer.ts` (`getShortenedLength`) | the limit and counter use the post-shortening grapheme count | `FacetPipelineTests.shortenedLength`, `.limitMeasuredAfterShortening` |
| `lib/api/index.ts` (`resolveRT`) | publish text trims leading blank lines and trailing whitespace | `FacetPipelineTests.publishTextTrimming`, `ComposerThreadAssemblyTests.publishedTextTrimmed` |
| `lib/api/index.ts` (`post`) | the minimal text-only record shape, with no seedless optional fields | `ComposerRecordBuilderTests.textOnlyRecord` |
| `lib/api/index.ts` (`post`) | `langs` are written and the lexicon caps them at three | `ComposerRecordBuilderTests.langsWritten` |
| `lib/api/index.ts` (`post`) | labels produce the `com.atproto.label.defs#selfLabels` shape | `ComposerRecordBuilderTests.labelsShape` |
| `lib/api/index.ts` (`post`) | detected links become facets with UTF-8 byte offsets | `ComposerRecordBuilderTests.linkFacetInRecord` |
| `lib/api/index.ts` (`resolveMedia` images) | <= 4 images produce `app.bsky.embed.images` with optional aspect ratio | `ComposerRecordBuilderTests.imagesEmbed` |
| `lib/api/index.ts` (`resolveMedia` gallery) | > 4 images produce `app.bsky.embed.gallery` with per-item `$type` | `ComposerRecordBuilderTests.galleryEmbed` |
| `lib/api/index.ts` (`resolveMedia` video) | a video produces `app.bsky.embed.video` with `presentation` and aspect ratio | `ComposerRecordBuilderTests.videoEmbed`, `.gifPresentation`, `.zeroDimensionsOmitRatio` |
| `lib/api/index.ts` (`resolveMedia` link) | a resolved link card produces `app.bsky.embed.external` | `ComposerRecordBuilderTests.linkCardEmbed` |
| `lib/api/index.ts` (`resolveEmbed`) | media wins over a link card | `ComposerRecordBuilderTests.mediaWinsOverLinkCard` |
| `lib/api/index.ts` (`resolveEmbed`) | a quote alone is `embed.record`; quote plus media is `embed.recordWithMedia` | `ComposerRecordBuilderTests.quoteEmbed`, `.quoteWithMediaEmbed` |
| `lib/api/index.ts` (`resolveEmbed`) | a quote with no resolved ref produces no embed | `ComposerRecordBuilderTests.unresolvedQuoteProducesNoEmbed` |
| `lib/api/index.ts` (`post`) | the full record payload's key set is exactly as expected | `ComposerThreadAssemblyTests.fullPayloadShape` |
| `lib/api/index.ts` (`post` threading) | the second post replies to the first, rooted at the first | `ComposerThreadAssemblyTests.threadRepliesChain` |
| `lib/api/index.ts` (`post` threading) | a reply thread inherits the resolved root for every post | `ComposerThreadAssemblyTests.replyThreadInheritsRoot` |
| `lib/api/index.ts` (`post` `now.setMilliseconds`) | `createdAt` increments by 1 ms per post | `ComposerThreadAssemblyTests.createdAtIncrements` |
| `lib/api/index.ts` (`post`) | a missing rkey throws | `ComposerThreadAssemblyTests.missingRKeyThrows` |
| `lib/api/index.ts` (`post` threadgate) | the threadgate attaches to the first post only | `ComposerThreadAssemblyTests.threadgateOnFirstPostOnly`, `.nobodyThreadgateEmptyAllow` |
| `lib/api/index.ts` (`post` threadgate) | an `everybody` threadgate attaches nothing | `ComposerThreadAssemblyTests.everybodyThreadgateOmitted` |
| `lib/api/index.ts` (`post` postgate) | the postgate attaches to every post with rules or detached URIs | `ComposerThreadAssemblyTests.postgateOnEveryPost`, `.emptyPostgateOmitted` |
| `lib/api/index.ts` (`writes.push`) | the `applyWrites` batch orders post, threadgate, postgate per post | `ComposerThreadAssemblyTests.writeBatchOrder` |
| `state/queries/threadgate/util.ts` | nil => everybody, undefined => everybody, empty => nobody | `ComposerGatesTests.missingRecordIsEverybody`, `.undefinedAllowIsEverybody`, `.emptyAllowIsNobody` |
| `state/queries/threadgate/util.ts` (`threadgateAllowUISettingToAllowRecordValue`) | everybody => nil, nobody => empty, and both win over other settings | `ComposerGatesTests.everybodyProducesNil`, `.nobodyProducesEmpty`, `.everybodyWins`, `.nobodyWins` |
| `state/queries/threadgate/util.ts` | each rule maps between record and UI shape, and round-trips | `ComposerGatesTests.rulesMapToSettings`, `.rulesRoundTrip`, `.listRuleShape` |
| `state/queries/threadgate/util.ts` (`createThreadgateRecord`) | the record's `$type` and post URI, and a missing URI throws | `ComposerGatesTests.recordShape`, `.emptyPostRejected` |
| `state/queries/threadgate/util.ts` (`mergeThreadgateRecords`) | merges union `hiddenReplies` and deduplicate `allow` by `$type`; a nil `allow` stays nil | `ComposerGatesTests.mergeUnions`, `.mergeKeepsNilAllow` |
| `state/queries/postgate/util.ts` (`createPostgateRecord`) | the disable rule writes `#disableRule`; detached URIs are written; a placeholder tolerates an empty post | `ComposerGatesTests.disableRuleShape`, `.detachedUris`, `.placeholderPostgate` |
| `state/queries/postgate/util.ts` (`mergePostgateRecords`) | merges union both arrays and deduplicate rules by `$type` | `ComposerGatesTests.mergePostgates` |
| `view/com/composer/text-input/text-input-util.ts` (`suggestLinkCardUri`) | immediate suggestion skips the stability check | `LinkSuggestionTests.immediateSuggestion` |
| `view/com/composer/text-input/text-input-util.ts` (`suggestLinkCardUri`) | a link not seen on the previous keystroke is ignored while typing | `LinkSuggestionTests.unstableLinkIgnored` |
| `view/com/composer/text-input/text-input-util.ts` (`suggestLinkCardUri`) | a stable tail, a trailing space, or punctuation-then-space makes a link eligible | `LinkSuggestionTests.stableTailSuggests`, `.trailingSpaceSuggests`, `.punctuationThenSpaceSuggests` |
| `view/com/composer/text-input/text-input-util.ts` (`suggestLinkCardUri`) | a link still being extended is not eligible | `LinkSuggestionTests.stillTypingNotEligible` |
| `view/com/composer/text-input/text-input-util.ts` (`suggestLinkCardUri`) | an already-suggested link is skipped; an undetected link becomes eligible again | `LinkSuggestionTests.alreadySuggestedSkipped`, `.noLongerDetectedIsForgotten` |
| `view/com/composer/text-input/text-input-util.ts` (`isValidUrlAndDomain`) | private addresses are rejected; public hosts are accepted | `LinkSuggestionTests.urlValidation` |
| `view/com/composer/state/video.ts` (`videoReducer`) | a fresh video compressing from zero | `VideoReducerTests.freshVideo` |
| `view/com/composer/state/video.ts` (`videoReducer`) | compressing -> uploading, and the skipped-compression band | `VideoReducerTests.compressingToUploading`, `.skippedCompressionBand` |
| `view/com/composer/state/video.ts` (`videoReducer`) | uploading -> processing records the job id at the processing band | `VideoReducerTests.uploadingToProcessing` |
| `view/com/composer/state/video.ts` (`update_job_status`) | server percentage advances progress; a status without progress does not | `VideoReducerTests.jobStatusProgress`, `.jobStatusWithoutProgress` |
| `view/com/composer/state/video.ts` (`to_done` / `to_error`) | `to_done` only applies from `processing`; `to_error` applies from any state | `VideoReducerTests.toDoneOnlyFromProcessing`, `.toErrorFromAnyState`, `.toDone` |
| `view/com/composer/state/video.ts` (signal guard) | an action from a superseded or cancelled token is dropped entirely | `VideoReducerTests.staleTokenDropped`, `.staleToErrorDropped`, `.cancelledDropsActions` |
| `view/com/composer/state/video.ts` (`update_alt_text` / `update_captions`) | alt text and captions survive a transition into `error` | `VideoReducerTests.altAndCaptionsEditable` |
| `view/com/composer/state/video.ts` (reduction outcome) | the reducer reports stale / unexpected / applied | `VideoReducerTests.reductionOutcomes` |
| `view/com/composer/state/video.ts` (`processVideo` poll loop) | a job completing on the first poll; transitioning through states; failing; completing without a blob | `VideoUploadOrchestratorTests.completesImmediately`, `.pollsThroughStates`, `.failsImmediately`, `.completedWithoutBlob` |
| `view/com/composer/state/video.ts` (`processVideo` retry policy) | transport failures retry, then give up after the failure budget; a recovery resumes | `VideoUploadOrchestratorTests.retriesThenGivesUp`, `.recoversAfterTransportFailure` |
| `view/com/composer/state/video.ts` (`processVideo` intervals) | successful polls wait the poll interval, failures the longer retry interval | `VideoUploadOrchestratorTests.pollsThroughStates`, `.retriesThenGivesUp` |
| `view/com/composer/state/video.ts` (deadline) | an overall deadline produces a timeout | `VideoUploadOrchestratorTests.deadlineTimesOut` |
| `view/com/composer/state/video.ts` (upload path) | `startUpload` -> parts -> `finishUpload` returns the job to poll | `VideoUploadOrchestratorTests.uploadPath`, `.startUploadFailurePropagates` |
| `view/com/composer/state/video.ts` (`getProcessingErrorMessage`) | every failure code maps to its message, including the legacy no-code case | `VideoUploadOrchestratorTests.processingMessageMapping`, `.legacyValidationFailure` |
| `view/com/composer/drafts/state/queries.ts` (create/update) | saving creates or updates according to `existingDraftId` | `ComposerDraftsTests.createDraft`, `.updateDraft` |
| `view/com/composer/drafts/state/queries.ts` (`useDraftsQuery`) | listing drafts paginates through the cursor | `ComposerDraftsTests.listDrafts` |
| `view/com/composer/drafts/state/queries.ts` (`useDeleteDraftMutation`) | deletion removes the draft, then its local media; a failed delete leaves the media alone | `ComposerDraftsTests.deleteDraft`, `.deleteRemovesMedia`, `.failedDeleteKeepsMedia` |
| `view/com/composer/drafts/state/queries.ts` (`useSaveDraftMutation`) | network first, local media second | `ComposerDraftsTests.networkBeforeLocalMedia` |
| `view/com/composer/drafts/state/queries.ts` (`useSaveDraftMutation`) | a failed create writes no local media | `ComposerDraftsTests.failedCreateWritesNoMedia` |
| `view/com/composer/drafts/state/queries.ts` (`useSaveDraftMutation`) | existing media files are not re-saved; orphans are deleted | `ComposerDraftsTests.existingMediaNotResaved`, `.orphanedMediaDeleted` |
| `view/com/composer/drafts/state/queries.ts` (draft limit) | the draft-limit error is surfaced distinctly | `ComposerDraftsTests.draftLimitError` |
| `view/com/composer/drafts/state/queries.ts` (device name) | the device name is truncated to the lexicon's 100 characters | `ComposerDraftsTests.deviceNameTruncated` |
| `view/com/composer/drafts/state/api.ts` (`composerStateToDraft`) | images are always written to `embedGallery`, even below the legacy cap | `ComposerDraftCodingTests.imagesAlwaysGallery` |
| `view/com/composer/drafts/state/api.ts` (`composerStateToDraft`) | a link card is only persisted when there is no media | `ComposerDraftCodingTests.linkCardDroppedWithMedia`, `.linkCardPersisted` |
| `view/com/composer/drafts/state/api.ts` (`composerStateToDraft`) | a quote is persisted only when it resolves to a strong ref; labels persist as selfLabels; gates persist | `ComposerDraftCodingTests.quotePersistedWhenResolved`, `.labelsPersisted`, `.gatesPersisted` |
| `view/com/composer/drafts/state/api.ts` (`serializeVideo`) | a video only persists once compressed, and its mime type is encoded into the path | `ComposerDraftCodingTests.uncompressedVideoNotPersisted`, `.videoMimeTypeInPath` |
| `view/com/composer/drafts/state/api.ts` (`parseVideoMimeType`) | the legacy `video:<id>` path defaults to mp4 | `ComposerDraftCodingTests.legacyVideoLocalRef` |
| `view/com/composer/drafts/state/api.ts` (`serializeGif` / `parseGifFromUrl`) | a GIF round-trips through the URL parameters | `ComposerDraftCodingTests.gifRoundTrip` |
| `view/com/composer/drafts/state/api.ts` (`parseGifFromUrl`) | a non-GIF host and a URL without dimensions are rejected | `ComposerDraftCodingTests.nonGifHostNotParsed`, `.gifWithoutDimsNotParsed` |
| `view/com/composer/drafts/state/api.ts` (`draftToComposerPosts`) | hydration restores text, facets and images | `ComposerDraftCodingTests.hydrateTextAndImages` |
| `view/com/composer/drafts/state/api.ts` (`draftToComposerPosts`) | hydration re-picks the variant from the restored count | `ComposerDraftCodingTests.hydrateRepicksVariant` |
| `view/com/composer/drafts/state/api.ts` (`draftToComposerPosts`) | media missing from local storage is dropped | `ComposerDraftCodingTests.hydrateDropsMissingMedia` |
| `view/com/composer/drafts/state/api.ts` (video restore) | a draft video is handed back for re-processing with its captions | `ComposerDraftCodingTests.hydrateVideoForReprocessing` |
| `view/com/composer/drafts/state/api.ts` (`draftToComposerPosts`) | quotes and labels are restored | `ComposerDraftCodingTests.hydrateQuote`, `.hydrateLabels` |
| `view/com/composer/drafts/state/api.ts` (`extractLocalRefs`) | every media path in a draft is gathered | `ComposerDraftCodingTests.localRefSet` |
| `view/com/composer/drafts/state/api.ts` (`draftViewToSummary`) | media counts, missing-file detection, device origin and quote counts | `ComposerDraftCodingTests.summaryCounts`, `.summaryOtherDevice` |
| `lib/moderation.ts` (`SELF_LABELS`) | the composer's label set matches `ADULT_CONTENT_LABELS + OTHER_SELF_LABELS` | `SelfLabelTests.labelSet`, `.recognised` |
| `lib/moderation.ts` (self-label set) | duplicates are refused; an empty set produces no record value | `SelfLabelTests.duplicateRefused`, `.emptySetNoRecord`, `.populatedSetRecord` |
| `state/preferences/languages.tsx` (`toPostLanguages`) | a preference string splits on commas, blanks are dropped, and the list is capped | `LanguageTests.preferenceStringSplits`, `.blankEntriesDropped`, `.cappedAtThree`, `.emptyPreference` |
| `view/com/composer/select-language/PostLanguageSelect.tsx` (`onSelectLanguages`) | an empty selection falls back to the primary language; a manual set marks the selection manual | `LanguageTests.emptySetFallsBack`, `.explicitSetIsManual` |
| `view/com/composer/select-language/PostLanguageSelect.tsx` | one language is added or removed at a time, with duplicates and a fourth refused | `LanguageTests.addLanguage`, `.duplicateRefused`, `.fourthRefused`, `.removeLanguage` |
| `view/com/composer/select-language/SuggestedLanguage.tsx` | adopting a reply target's languages replaces the list, and is a no-op when already selected | `LanguageTests.adoptReplyLanguages`, `.adoptAlreadySelected` |
| `lib/api/index.ts` (`langs.slice(0, 3)`) | the written language list is capped at the lexicon's three | `LanguageTests.cappedAtThree` |
| `lib/languages.ts` (BCP-47 tags) | plausible tags are accepted and junk is rejected | `LanguageTests.plausibility` |
| `@bsky/sdk/richtext` facets (via `lib/api/index.ts`) | an ASCII link converts to a lexicon facet with correct byte offsets | `FacetPipelineTests.asciiLinkFacet` |
| `@bsky/sdk/richtext` facets (via `lib/api/index.ts`) | an emoji before a link shifts the facet by UTF-8 bytes, not graphemes | `FacetPipelineTests.emojiShiftsByteOffsets`, `.emojiFacetJSON`, `.multipleFacetsWithEmoji` |
| `@bsky/sdk/richtext` facets (via `lib/api/index.ts`) | an emoji-only post counts graphemes, not bytes | `FacetPipelineTests.emojiGraphemeCounting` |
| `lib/api/index.ts` (`resolveRT` mention stripping) | an unresolved mention is dropped from the published facets | `FacetPipelineTests.unresolvedMentionDropped` |
| `@bsky/sdk/richtext` mention/tag facets | resolved mentions and tags convert to their lexicon shapes | `FacetPipelineTests.mentionFacet`, `.tagFacet`, `.noFacetsIsNil` |

## Deviations from the RN implementation

1. **`RichText` is snapshotted as a value type.** RN's composer state holds the
   mutable `RichText` class directly. `RichText` here is a non-`Sendable`
   reference type, so `PostDraft.richText` is a `RichTextValue` (text + facets)
   and a `RichText` is rebuilt only where the detection and editing APIs are
   needed. Observable behaviour is unchanged; the state is now `Sendable` and
   `Hashable`, which the RN reducer's structural comparisons imply anyway.

2. **`$type` is written explicitly, via `TypedRecord`.** The generated lexicon
   structs in this repo do **not** encode `$type` from their synthesized
   `encode(to:)` — verified against `App.Bsky.FeedPost.encode(to:)` in
   `Packages/Lexicons`, whose `CodingKeys` declares `case type = "$type"` for
   decoding only and whose `encode` never writes it. The publish path therefore
   wraps each record in `TypedRecord`, which writes `$type` first. This matters
   twice over: the PDS validates the field, and the record's CID is computed over
   its DAG-CBOR form *including* `$type` (the RN source calls this out: "CID is
   calculated with the `$type` field present and will produce the wrong CID if
   you omit it"). Nested plain-ref records — the `record` inside
   `embed.recordWithMedia`, for instance — have the same gap and are **not** yet
   wrapped; see open questions.

3. **CID computation is injected, not implemented.** No DAG-CBOR encoder is
   exposed by the vendored `swift-atproto` here, so
   `ComposerRecordBuilder.build(_:cidProvider:)` takes a `cidProvider` closure.
   RN computes the CID inline (`computeCid` from `lib/api/cid.ts`). The threading
   *semantics* (each post's CID feeding the next post's `reply.parent`) are
   covered; the hash itself stays a host concern until the repo-write path lands.

4. **Blob upload and link/mention resolution are out of scope.**
   `PublishInputs` takes already-uploaded blobs (`ResolvedEmbedMedia`) and
   already-resolved quote refs, so the record builder is pure. RN's
   `resolveMedia` interleaves compression, `uploadBlob` and link resolution; that
   orchestration belongs to the app layer until an upload/query client is wired
   in. `ComposerLogic` carries no `ATProtoClient` dependency.

5. **Video compression is not ported.** `processVideo` begins with
   `compressVideo`, a platform media concern (WebCodecs / ffmpeg).
   `VideoUploadOrchestrator` owns the orchestration — `startUpload` -> part
   uploads -> `finishUpload` -> `getJobStatus` polling — and takes a
   `VideoUploadService` for the transport. The poll policy (retry counts,
   intervals, the 1.5 s cadence, and the failed-job short-circuit) is ported
   exactly.

6. **The poll clock is injectable.** RN calls `setTimeout` directly. Sleeps go
   through `VideoPollClock`, so the retry budget and the overall deadline are
   testable without real waiting, and a fake clock can reach a deadline in a
   bounded number of iterations.

7. **The gallery aspect ratio has a unit fallback.** `app.bsky.embed.gallery#image`
   declares `aspectRatio` as required and `>= 1`, unlike
   `app.bsky.embed.images#image` where it is optional. When an image's dimensions
   are unknown (0), `ResolvedImage.aspectRatioOrUnit` substitutes 1:1 rather than
   writing zeros the lexicon would reject.

8. **`RichText.facets` has an internal setter**, so the facet tests build facets
   through `RichText(text:facets:)` rather than assigning them.

9. **Draft post initialization order.** The generated
   `App.Bsky.DraftDefs_DraftPost` memberwise initializer takes `text` last, not
   first as the RN object literal reads.

10. **Local media storage is injected.** RN's `drafts/state/storage.ts` touches
    the device file system directly; `ComposerDraftMediaStorage` is a protocol so
    the "network first, local media second" ordering is assertable without a file
    system.

11. **No analytics.** RN emits `composer:*` metrics throughout. The state machine
    exposes the data they would use and leaves emission to the app layer.

# VideoFeed port: tests-ported manifest

Maps the React Native immersive-video-feed logic to the Swift port in
`Packages/Features/VideoFeed/Sources/VideoFeedLogic/` and its tests.

The port is **data-only**: it produces the playable video-item list, the pager's
viewability state, the autoplay decision and a per-item playback state store. It
contains no SwiftUI/UIKit, no `Observation`, and **no AVFoundation** - the player
stays in the future `VideoFeedViews` package, and this package hands it values.

## Source mapping

| TypeScript module | Swift source |
|---|---|
| `screens/VideoFeed/index.tsx` (`VideoItem` type, `videos` memo, viewability config, `updateVideoState` slot arithmetic, `isTallAspectRatio`, `onViewableItemsChanged`) | `VideoItem.swift`, `VideoFeedFilter.swift`, `VideoViewability.swift`, `VideoPagerStateMachine.swift` |
| `screens/VideoFeed/index.tsx` (`VideoItemInner`, `usePlaybackTelemetry`, `playbackStartTrackedRef`, `maxTimeRemainingSeconds`) | `VideoPlaybackStore.swift` |
| `screens/VideoFeed/types.ts` (`VideoFeedSourceContext`, `sourceInterstitial`) | `VideoFeedSource.swift`, `VideoFeedKeys.swift` |
| `screens/VideoFeed/index.tsx` (`feedDesc` memo, `usePostFeedQuery`, `initialPostUri` slice) | `VideoFeedSource.swift`, `VideoFeedQuery.swift` |
| `lib/api/feed/custom.ts` (`CustomFeedAPI`) | `VideoPageFetcher.swift` (`VideoGeneratorFetcher`), `LiveVideoFeedXrpc.swift` |
| `lib/api/feed/author.ts` (`AuthorFeedAPI`, `includePins`) | `VideoPageFetcher.swift` (`VideoAuthorFetcher`) |
| `lib/api/feed/utils.ts` (`BSKY_FEED_OWNER_DIDS`, `isBlueskyOwnedFeed`) | `VideoFeedXrpc.swift` (`VideoFeedOwners`) |
| `state/queries/post-feed.ts` (`RQKEY_ROOT`, `RQKEY`, `FeedDescriptor`, `MIN_POSTS`) | `VideoFeedKeys.swift`, `VideoFeedConstants.swift` |
| `state/queries/feed.ts` (`useFeedInfo`, `feedInfoQueryKeyRoot`) | `VideoFeedInfo.swift` |
| `state/preferences/feed-tuners.tsx` (`useFeedTuners`) | `VideoFeedQuery.swift` (`VideoFeedTunerFactory`) |
| `state/preferences/autoplay.tsx` (`useAutoplayDisabled`) | `VideoAutoplay.swift` (`VideoAutoplaySettings`), `VideoAutoplayPreference.swift` |
| `components/Post/Embed/VideoEmbed/VideoVolumeContext.tsx` (`useVideoMuteState`) | `VideoAutoplay.swift` (`videoBeginMuted`) |
| `components/Post/Embed/VideoEmbed/VideoEmbedInner/VideoEmbedInnerNative.tsx` (`autoplay`, `beginMuted`) | `VideoAutoplay.swift` |
| `types/bsky/post.ts` (`Embed` union, `parseEmbed`, `parseEmbedRecordView`) | `VideoItem.swift` (`VideoEmbedKind`) |
| `lib/media/video/analytics.ts` (`hasPlaybackStarted`, `PLAYBACK_START_THRESHOLD_SECONDS`) | `VideoPlaybackStore.swift` |
| `lib/constants.ts` (`VIDEO_FEED_URI`, `STAGING_VIDEO_FEED_URI`, `VIDEO_FEED_URIS`) | `VideoFeedConstants.swift` |

## TS test files ported 1:1

| TypeScript test | Cases ported as |
|---|---|
| `lib/media/video/__tests__/analytics.test.ts` | `VideoPlaybackStoreTests.hasPlaybackStartedFollowsRNs0_05SThreshold` - all six rows of the `it.each` table (`0`, `0.049`, `0.05`, `1`, `NaN`, `Infinity`) |

This is the only RN test file covering video-feed logic; the immersive screen
itself is un-tested upstream, so the remaining cases below are ported from
behavior rather than from a test case.

## Behavior ported from un-tested RN sources

| RN behavior (source) | Swift test |
|---|---|
| `VideoFeed/index.tsx` `videos` memo: per slice, select the item whose URI matches `feedPostUri`, keep only video embeds | `VideoItemModelTests.selectedPostBecomesItem`, `.nonVideoSelectedPostYieldsNoItem`, `.missingSelectedItemYieldsNoItem`, `.mixedFeedFiltersToVideos`, `.allNonVideoIsEmpty` |
| `types/bsky/post.ts` `parseEmbed` embed classification | `VideoItemModelTests.videoEmbedClassifies`, `.galleryEmbedIsNotPlayable`, `.externalEmbedIsNotPlayable`, `.imagesEmbedIsNotPlayable`, `.quotePostIsNotPlayable`, `.quoteWithVideoIsPlayable`, `.quoteWithGalleryIsNotPlayable`, `.noEmbedIsNil` |
| Unknown embed variant tolerance (`_other` / `UnknownRecord`) | `VideoItemModelTests.unknownVariantIsTolerated`, `.unknownPresentationIsTolerated` |
| `app.bsky.embed.video#view` `presentation` known values | `VideoItemModelTests.gifPresentation`, `.missingPresentation` |
| `VideoFeed/index.tsx` `isTallAspectRatio` | `VideoItemModelTests.tallAspectRatio` |
| Captions live on the record (`app.bsky.embed.video#main`), not the view | `VideoItemModelTests.captionsComeFromRecord`, `.noCaptionsWithoutVideoRecord`, `.classifyThreadsCaptions` |
| `feedContext` / `reqId` carried from slice to item | `VideoItemModelTests.feedContextCarries`, `VideoFeedQueryTests.contextSurvivesQuery` |
| `accessibilityLabel={embed.alt ? \`Video: ${alt}\` : \`Video\`}` | `VideoItemModelTests.accessibilityLabel` |
| `initialPostUri` slices the pager from that item | `VideoItemModelTests.initialPostSlicesList`, `.absentInitialPostDoesNotSlice`, `.startingIndex`, `VideoFeedQueryTests.pagerItemsOffset` |
| `viewabilityConfig = {itemVisiblePercentThreshold: 100, minimumViewTime: 0}` | `VideoViewabilityTests.immersiveConfig`, `.stricterThanListDefault`, `.fullyCoveredIsViewable`, `.minimumViewTimeGate` |
| `onViewableItemsChanged`: `viewableItems[0].index` becomes the active index | `VideoViewabilityTests.fullyVisibleBecomesActive`, `.partialVisibilityDoesNotActivate`, `.firstViewableWins`, `.emptyObservationClearsActive`, `.outOfRangeObservation` |
| `updateVideoState` three-player window (`index - 1`, `index`, `index + 1`) | `VideoViewabilityTests.preloadWindowSymmetric`, `.preloadWindowClamps`, `.preloadWindowZeroRadius`, `.preloadWindowWiderRadius`, `.preloadWindowDegenerate`, `.defaultRadiusIsOne`, `.adjacentIndicesClamp`, `.preloadFollowsActive`, `.preloadClampsAtEdges`, `.widerRadiusInMachine` |
| `updateVideoState` pool slot arithmetic (`index % 3`, `(index + 2) % 3`, `(index + 1) % 3`) | `VideoViewabilityTests.poolSlotModulo`, `.slotAssignments`, `.slotAssignmentsClamp` |
| `shouldRenderVideo = active \|\| ios(adjacent)` | `VideoViewabilityTests.adjacentItems`, `.perIndexViewability` |
| Screen blur releases the players; programmatic move re-targets them | `VideoViewabilityTests.clearActiveReleasesPreloads`, `.programmaticMove`, `.invalidMoveIgnored`, `.setItemsResets`, `.setItemsClampsWhenNotResetting`, `.emptyItemList`, `.sameIndexNoChange`, `.transitionReportsChanges` |
| `autoplay = !autoplayDisabled && !isWithinMessage` | `VideoAutoplayTests.gatingTable`, `.defaultSettings` |
| Immersive `updateVideoState` pause on `contentView.blur \|\| contentMedia.blur` | `VideoAutoplayTests.gatingTable`, `.eitherBlurCounts`, `.alertOnlyIsNotBlurred`, `.emptyDecisionIsNotBlurred`, `.noDecisionIsNotBlurred` |
| Moderation pause wins over the autoplay preference | `VideoAutoplayTests.gatingTable`, `.decisionFlags` |
| `beginMuted = isGif \|\| (autoplayDisabled ? false : muted)` | `VideoAutoplayTests.gifBeginsMuted`, `.autoplayHonoursMute`, `.noAutoplayBeginsUnmuted` |
| `VideoAutoPlayDecision` derived flags (`autoplays`, `isPlayable`, `requiresTapToPlay`) | `VideoAutoplayTests.decisionFlags` |
| `onLoadingChange` / `onStatusChange` / `onPlayingChange` lifecycle | `VideoPlaybackStoreTests.loadLifecycle`, `.readyStatus`, `.bufferingRecoversWhileActive`, `.bufferingReturnsToPausedWhenInactive`, `.endedIsDistinct`, `.pauseWhileIdleKeepsPhase` |
| `onError` -> failed phase with the player message | `VideoPlaybackStoreTests.failure`, `.failureWithoutMessage` |
| `onActiveChange` single-active-player model, preloaded neighbors are ready-but-inactive | `VideoPlaybackStoreTests.activeIsExclusive`, `.deactivateClearsPointer`, `.deactivateOtherKeepsPointer`, `.preloadedNeighborNotActive`, `.activeStateAccessor` |
| `onMutedChange` (ignored for GIFs upstream) | `VideoPlaybackStoreTests.muteChanges`, `.registerInheritsDefaultMute` |
| `onTimeRemainingChange` duration estimate (`maxTimeRemainingSeconds`) | `VideoPlaybackStoreTests.timeUpdateRecordsDuration`, `.durationRatchets`, `.progressClamped` |
| `Number.isFinite` guards on time updates | `VideoPlaybackStoreTests.nonFiniteTimeIgnored`, `.infiniteRemaining` |
| `playbackStartTrackedRef` one-shot report at the threshold | `VideoPlaybackStoreTests.playbackStartFiresOnce`, `.playbackStartUnknownItem` |
| Pooled player reassigned to a new playlist resets the item's phase | `VideoPlaybackStoreTests.reRegisterDifferentPlaylistResets`, `.reRegisterSamePlaylistPreserves`, `.eventForUnknownItemIsNoop` |
| List shrink drops playback state | `VideoPlaybackStoreTests.removeItem`, `.retainOnly`, `.retainOnlyKeepsActive` |
| Phase predicates (`isPlaying`, `isPlaybackHalted`, `hasMedia`, `isFailed`) | `VideoPlaybackStoreTests.phaseFlags`, `.anythingPlaying` |
| `state/preferences/autoplay.tsx` `persisted.get('disableAutoplay')` + `persisted.write` | `VideoAutoplayPreferenceTests.unsetUsesDefault`, `.storedWins`, `.accountScoped`, `.clearedPreference`, `.settingsBridge` |
| `state/persisted/schema.ts` `disableAutoplay` default = reduced motion | `VideoAutoplayPreferenceTests.unsetUsesDefault`, `.schemaKey` |
| `RQKEY(feedDesc, params)` incl. `feedCacheKey` | `VideoFeedQueryTests.feedKeyShape`, `.distinctFeedKeys`, `.interstitialInKey`, `.scopeSeparatesAccounts`, `.feedKeyNotPersisted` |
| `useFeedInfo` -> `feedInfoQueryKeyRoot` | `VideoFeedQueryTests.feedInfoKey`, `VideoFeedInfoTests.*` |
| `CustomFeedAPI.fetch` (limit truncation, per-request headers, Bluesky-owned topics) | `VideoFeedQueryTests.generatorFetcherCall`, `.generatorFetcherTruncates`, `.generatorHeaders`, `.loggedOutHeaders`, `.nonBlueskyFeedHeaders` |
| `AuthorFeedAPI.fetch` + `includePins` rule | `VideoFeedQueryTests.authorFetcherCall`, `.includePins`, `.fetcherFactory` |
| `useFeedTuners` for `feedgen` / `author` | `VideoFeedQueryTests.loadFirstPageFilters`, `VideoFeedQueryTests.nonVideoPage` |
| `usePostFeedQuery` page accumulation and per-slice de-duplication | `VideoFeedQueryTests.dataIsHeldUnderKey`, `.pagination`, `.dedupesRepeatedSlices`, `.queryKeyMatchesEntry` |
| `truncateAndInvalidate` refresh | `VideoFeedQueryTests.refreshTruncates` |
| Query subscription re-delivering derived items | `VideoFeedQueryTests.subscription` |
| `VIDEO_FEED_URI` / `VIDEO_FEED_URIS` and the `feedgen\|` / `author\|…\|…` descriptors | `VideoFeedQueryTests.videoSource`, `.videoFeedURIs`, `.authorSource`, `.descriptorRoundTrip`, `.unknownDescriptor`, `.allAuthorFilters` |

## Swift-only tests (no RN analogue)

- `VideoFeedQueryTests.fetcherPropagatesError`, `.loadFailure` - error propagation
  through the fetcher and the query.
- `VideoFeedQueryTests.emptyPage`, `.removeQuery` - empty-feed and cache-removal
  behavior that QueryStore (not RN's TanStack cache) dictates.
- `VideoFeedInfoTests.displayNameFallback` - RN's `Feed by @<handle>` fallback,
  which upstream only exercises through rendering.
- `VideoFeedInfoTests.missingGenerator`, `.errorDescriptions`, `.errorEquality` -
  the package's own error type.
- `VideoItemModelTests.moderationResolverApplies`, `.itemModerationWinsOverResolver`
  - the moderation seam this port introduces so the filter stays pure.
- `VideoViewabilityTests.defaultState` - the empty-state constant.

## Deviations from RN

1. **The tuner options type is local.** `FeedTunerOptions` lives in
   `HomeFeedLogic`, and feature Logic packages in this repo never depend on one
   another, so `VideoTunerOptions` restates the shape for the one field the video
   feed reads (`contentLanguages`).
2. **The moderation resolver is injected.** RN reads `item.moderation` off the
   tuned slice, which the query builds. Building a decision needs labeler config,
   preferences and the post record, so the filter takes a `VideoModerationResolver`
   closure instead of depending on the whole pipeline.
3. **`isOnline` is not modelled.** `app.bsky.feed.defs#generatorView` in the
   generated Lexicons has no `isOnline` field (it lives on the older
   `describeFeedGenerator` response), so `VideoFeedInfo.isAvailable` reports view
   presence instead.
4. **Empty header values are omitted.** RN's `Accept-Language` /
   `X-Bsky-Topics` are only set when non-empty; the port makes that explicit, and
   a test pins it. (This was a real bug the test suite caught.)
5. **`startingVideoIndex` reproduces RN's falsy-zero quirk deliberately** - RN's
   `if (vids && startingVideoIndex && startingVideoIndex > -1)` does not slice at
   index `0`. Slicing at zero is a no-op, so the visible result is identical and
   the port does not carry the bug into `videoPagerItems`.

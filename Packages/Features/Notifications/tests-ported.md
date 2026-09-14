# Notifications port: tests-ported manifest

Maps the React Native notification queries
(`~/bluesky/social-app/src/state/queries/notifications/`) to the Swift port in
`Packages/Features/Notifications/Sources/NotificationsLogic/` and its tests.

The port is data-only: it produces the typed notification rows, the unread
state, and the cache writes the UI needs. It contains no SwiftUI, no
Observation, and no view strings beyond the small English seam in
`NotificationStrings.swift`.

## Source mapping

| TypeScript module | Swift source |
|---|---|
| `notifications/types.ts` (`NotificationType`, `FeedNotification`, `FeedPage`) | `NotificationTypes.swift` |
| `notifications/util.ts` (`fetchPage`, `shouldFilterNotif`, `groupNotifications`, `fetchSubjects`, `toKnownType`, `getSubjectUri`) | `NotificationPageFetcher.swift`, `NotificationReasons.swift` |
| `notifications/feed.ts` (`useNotificationFeedQuery`, `RQKEY`) | `NotificationFeeds.swift` |
| `notifications/unread.tsx` (`Provider`, `checkUnread`, `markAllRead`, `getCachedUnreadPage`, `countUnread`) | `NotificationUnread.swift`, `NotificationClock.swift` |
| `notifications/settings.ts` (`useNotificationSettingsQuery`, `useNotificationSettingsUpdateMutation`) | `NotificationSettings.swift` |
| `state/queries/activity-subscriptions.ts` (`useActivitySubscriptionsQuery`, `putActivitySubscription`) | `ActivitySubscriptions.swift` |

## TS test files ported 1:1

| TypeScript test | Cases ported as |
|---|---|
| `notifications/__tests__/util.test.ts` | `NotificationGroupingTests.starterPackFollowDoesNotGroupWithOrganicFollow`, `.groupsFollowsByStarterPack` |

Both RN cases are ported verbatim, including the `makeFollowNotification`
fixture builder (`NotificationGroupingTests.followNotification`) and its fixed
`2026-07-28T12:00:00.000Z` timestamp.

## Behavior ported from un-tested RN sources

| RN behavior (source) | Swift test |
|---|---|
| `util.ts` `toKnownType` reason→type table | `NotificationReasonMappingTests.knownReasons` (13 cases), `.unknownReasonMapsToUnknown`, `.feedGeneratorLikeSplits` |
| `util.ts` `getSubjectUri` per-reason subject | `NotificationReasonMappingTests.subjectUris`, `.starterPackSubjectIsOwnUri` |
| `util.ts` `shouldFilterNotif` label/mute/follow rules | `NotificationReasonMappingTests.hideLabelFilters`, `.noModerationKeepsEverything`, `.followedAuthorBypassesModeration`, `.moderationTintedNotificationIsFiltered`, `.moderationTintBypassedForFollowedAuthor` |
| `util.ts` `groupNotifications` window/subject/author/starter-pack/follow-back rules | `NotificationGroupingTests.likesGroup`, `.likesTooFarApartDoNotGroup`, `.differentSubjectsDoNotGroup`, `.sameAuthorDoesNotGroup`, `.nonGroupableReasonNeverGroups`, `.followsGroup`, `.followBackDoesNotGroup`, `.differentStarterPacksDoNotGroup` |
| `util.ts` `fetchSubjects` chunked bulk resolution | `NotificationFeedTests.resolvesSubjects`, `.skipsSubjectFetchWhenNotNeeded` |
| `feed.ts` `fetchPage` params + STALE.INFINITY + dedupe-on-merge | `NotificationFeedTests.loadsFirstPage`, `.appendsPagesAndDedupes`, `.mentionsFilterSendsReasons`, `.feedIsNeverStaleByTime`, `.reportsIndexedAt` |
| `feed.ts` `select` seenAt override, hidden replies, subject moderation | `NotificationFeedTests.headSeenAtOverridesIsRead`, `.newerThanSeenAtIsUnread`, `.hiddenReplyDropped` |
| `unread.tsx` `UPDATE_INTERVAL` cadence | `NotificationUnreadTests.pollIntervalIsThirtySeconds`, `.startPollsImmediatelyAndSchedules` |
| `unread.tsx` `checkUnread` count derivation + `30+` cap | `NotificationUnreadTests.checkDerivesUnreadCount`, `.allReadGivesEmptyBadge`, `.countSaturatesAtThirty`, `.unreadBoundaries` (5 cases), `.countsGroupedNotifications` |
| `unread.tsx` poll throttling (`unreadCount !== 0`, `>= 30`, `Math.random() >= 0.5`) | `NotificationUnreadTests.saturatingPollSkips`, `.throttledPollRespectsRandom`, `.zeroCountIsNeverThrottled` |
| `unread.tsx` `AppState`/session guards and the `isFetching` latch | `NotificationUnreadTests.inactiveAppSkipsCheck`, `.signedOutSkipsCheck`, `.concurrentChecksDoNotStack` |
| `unread.tsx` `syncedAt` watermark (never backwards) | `NotificationUnreadTests.syncWatermarkNeverGoesBackwards` |
| `unread.tsx` `usableInFeed` cache + `truncateAndInvalidate` on invalidate | `NotificationUnreadTests.cacheUsableOnlyAfterInvalidate`, `.invalidatingCheckResetsFeeds` |
| `unread.tsx` `markAllRead` (`updateSeen` payload, reset, no reset on failure) | `NotificationUnreadTests.markAllReadSendsWatermark`, `.markAllReadUsesPageIndexedAtWhenLater`, `.failedMarkAllReadKeepsState` |
| `activity-subscriptions.ts` infinite query + put | `ActivitySubscriptionsTests.listsSubscriptions`, `.writesSubscription`, `.emptySubscriptionIsUnsubscribe`, `.readsSubscriptionFromViewerState`, `.collectsSubscribedDids`, `.keyRootMatchesRN` |
| `settings.ts` get/put v2 preferences | `NotificationSettingsTests.readsPreferences`, `.patchWritesMergedPreferences`, `.patchAppliesOnlySetFields`, `.emptyPatch`, `.preferenceConstants`, `.keyRootMatchesRN` |
| Lexicon wire shape for every endpoint the package calls | `NotificationClientAdapterTests.updateSeenSendsIsoDate`, `.listNotificationsQuery`, `.listNotificationsOmitsEmptyReasons`, `.putActivitySubscriptionBody`, `.getPostsBody`, `.putPreferencesBody` |

## Coverage gaps and extensions beyond RN

- `feed.ts` `findAllPostsInQueryData` / `findAllProfilesInQueryData` are RN cache
  scanners used by profile-precaching consumers. They are not ported: the Swift
  store exposes `keys(root:)` and typed payload reads, and the scanner belongs
  with whichever feature needs it rather than in this package.
- The priority view (`NotificationFeeds.renderPriority`) has no RN equivalent in
  the query layer; see "Deviations" below.
- `BroadcastChannel` fan-out and `resetBadgeCount` (push badge) are platform
  concerns and are not ported here.

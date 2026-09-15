# Notifications (Logic)

The Linux-verifiable logic for the notifications feature: the feed query, the
unread-count pipeline, reason→view-data mapping, activity subscriptions, and
notification settings. Product: `NotificationsLogic`.

This package is UI-free by construction — no SwiftUI, no UIKit, no Observation,
and `defaultIsolation: nonisolated`. Ported from
`~/bluesky/social-app/src/state/queries/notifications/`; see
[`tests-ported.md`](./tests-ported.md) for the case-by-case mapping.

## Layout

| File | Responsibility |
|---|---|
| `NotificationTypes.swift` | `NotificationType`, `FeedNotification`, `ResolvedSubject`, `NotificationFeedPage`, `UnreadCount` |
| `NotificationClient.swift` | The `NotificationClient` protocol and its `XRPCNotificationClient` adapter |
| `NotificationReasons.swift` | Reason→type mapping, subject URIs, grouping, moderation filtering, the engine bridging |
| `NotificationPageFetcher.swift` | One page: request, filter, group, resolve subjects in bulk |
| `NotificationFeeds.swift` | Query keys, the infinite feed query, and the select pass |
| `NotificationUnread.swift` | The poll, the cache, mark-all-read, and the badge state |
| `NotificationClock.swift` | Injectable clock, poll scheduler, and random source |
| `ActivitySubscriptions.swift` | The activity-subscription read/write over the prefs endpoints |
| `NotificationSettings.swift` | The v2 notification preferences read and patch write |
| `NotificationStrings.swift` | The English string seam |

## Key design points

- **The store owns de-duplication per page; the select pass owns it per row.**
  `QueryStore` collapses repeated pages on merge; `NotificationFeedQuery.select`
  collapses repeated rows (by `reactKey`) and is the only path that produces
  rows for rendering.
- **`STALE.INFINITY` for the feed, invalidation for freshness.** The feed never
  goes stale on its own; `NotificationUnreadCoordinator.checkUnread(invalidate:)`
  is what truncates and invalidates the feed keys, exactly as RN's `unread.ts`
  drives `feed.ts`.
- **Mark-all-read sends the cache's sync watermark, not `now`.** The watermark
  is `max(sync time, newest indexed row)`, so a page fetched slightly in the
  past cannot mark notifications that arrived after it as read.

## Testing

`swift test` runs 71 tests across seven suites. The fakes are package-local
(`Tests/NotificationsLogicTests/Fakes.swift`) rather than shared `TestSupport`
fixtures; `NotificationClientAdapterTests` additionally drives the real
`XRPCNotificationClient` over a scripted transport so request shapes (URL,
method, body) are asserted at the wire level.

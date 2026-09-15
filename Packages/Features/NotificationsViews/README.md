# NotificationsViews

The SwiftUI half of the Notifications feature: the notifications list screen and
the fixture surface the app shell mounts.

## What is here

| File | What it owns |
|---|---|
| `NotificationsScreen.swift` | The screen: filter bar, row list, loading/empty/error states. |
| `NotificationRowViews.swift` | The two row shapes: `NotificationSentenceRow` (icon + sentence + optional subject preview) and `NotificationPostRow` (a subject post through `UIComponents/PostFeedItem`). |
| `NotificationsFilterBar.swift` | The All / Mentions / Priority control, with the unread badge on All. |
| `NotificationReasonGlyph.swift` | The reason -> SF Symbol + palette token table, ported from the RN item's icon branches. |
| `NotificationsCopy.swift` | The reason -> sentence table, the grouped-author derivation, and display-name sanitising. |
| `NotificationsListModel.swift` | Page -> rows -> `ListState`, unread count, drawable-row filtering. |
| `NotificationsFixtures.swift` | One representative row per rendered reason, plus a grouped row. |
| `NotificationsSurfaces.swift` | `NotificationsSurfaces.notificationsScreen(theme:)` - the app-shell entry point. |
| `NotificationsAccessibility.swift` | Identifiers and launch arguments for UI tests. |

## Where the decisions live

Nothing here decides anything the logic package already decides. The row model
(which reason a notification is, which rows group, whether a row is read, which
subject a row points at) comes from `NotificationsLogic`; the string seam
(`NotificationStrings`) and the unread cap (`UnreadCount`) come from there too.
This package owns only what the RN `NotificationFeedItem` renders: the sentence
per reason, the icon per reason, the grouped-author line, and the layout.

The states are the shared ones: `UIComponents/ListStates` renders the empty and
error surfaces from `ListStrings.notifications` and `ListState`, so a
notifications list reads the same as every other list in the app.

## Reference

Read-only parity source: `~/bluesky/social-app/src/view/screens/Notifications.tsx`
(the pager and the empty state) and
`~/bluesky/social-app/src/view/com/notifications/NotificationFeedItem.tsx` (the
row layout, the per-reason copy, and the per-reason icon).

## Deviations from RN

- **Priority is a tab.** The RN screen has two pager tabs (All, Mentions) and
  asks the appview for a `priority: true` page for its priority view. The port
  exposes that view as a third tab, because the appview's priority flag is a
  page-level property `NotificationFeeds.renderPriority` already derives and a
  tab is how the viewer reaches it.
- **SF Symbols instead of the RN icon set.** Same substitution the app shell
  already makes for its tab icons.
- **A row with an unknown reason is dropped rather than rendered.** The RN item
  returns `null` for a reason it does not know; a `null` row is invisible to
  VoiceOver, so the port filters such rows out before the list rather than
  drawing an empty row.
- **A reply whose subject never resolved shows `NotificationStrings.missingSubject`**
  instead of the RN item's `null`, for the same accessibility reason.

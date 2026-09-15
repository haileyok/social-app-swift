# MessagesViews

The SwiftUI half of the Messages feature: the minimal 1:1 chat UI.

| Screen | Type | Logic it renders |
|---|---|---|
| `InboxScreen` | screen | `InboxQuery` (via `InboxViewModel`) |
| `ConversationScreen` | screen | `ConversationModel` (via `ConversationViewModel`) |
| `ComposerBar` | bar | `ConversationModel.sendMessage` / `batchRetryPendingMessages` |
| `MessageBubble` | row | `ConvoItem` + `ConversationModel` reaction/read state |
| `MessagesFixtureGallery` | fixture | `MessagesFixtureSurfaces` (scripted conversation) |

## Layout of the package

- `InboxViewModel` / `ConversationViewModel` - the only bridge to the logic
  package. `InboxQuery` is a `Sendable` value over a `QueryStore` actor and
  `ConversationModel` is an actor; neither is `Observable`, so each adapter owns
  the rendered snapshot and republishes it after every awaited call on the main
  actor.
- `InboxScreen` / `ConversationScreen` - the two screens. They call into the
  view models and render; they re-derive no rule.
- `MessageBubble` / `ComposerBar` / `MessageListViewSupport` - the row and bar
  treatments, plus the date-separator grouping and the send-state enum.
- `MessageFacets` - the wire facet -> `RichText` conversion. It is explicit
  rather than a cast, so a change in either shape is a compile error here.
- `MessagesAccessibility` - every identifier a future XCUITest addresses.
- `MessagesCopy` - the localization seam (matching `LoginCopy`).
- `MessagesFixtures` / `ScriptedChatClient` / `MessagesFixtureSurfaces` - the
  scripted conversation and the gallery that mounts it.

## Scope: 1:1 only

Group and join surfaces do not exist here. The inbox query drops group convos
before they reach the store, so a row is always a 1:1 conversation. The wire
shapes for group events are still decoded tolerantly by `MessagesLogic`; the UI
ignores them. A system message (which is always a group or lock event in the
lexicon) renders a short generic line rather than reconstructing group metadata
the product does not show.

## Fixture surfaces

`MessagesFixtureSurfaces` mounts the production screens over a `ScriptedChatClient`
answering from `MessagesFixtures`, so the fixture path and the live path render
through the exact same code. The script covers:

- a two-day conversation with a date-separator boundary,
- mine vs theirs bubbles,
- a reaction (`👍`) already on a message, plus the add/remove affordance,
- a send that fails on its first attempt (a scripted 503), which
  `ConversationModel` classifies as a recoverable failure and renders as a
  failed bubble with retry,
- a send that succeeds.

`AppShell+MessagesViews.swift` exposes it as
`MessagesSurfaces.inboxScreen(theme:)` / `MessagesSurfaces.conversationScreen(theme:)`
and a `MessagesDebugButton` sheet.

## Deviations from the React Native screens

1. **Read receipts are derived, not stored.** The wire data has no per-message
   read receipt: a convo carries only the viewer's `unreadCount`. So a sent
   message renders "Read" only when the conversation's unread count is zero
   (meaning the partner has read up to the newest rev) and is suppressed
   otherwise. `ConversationScreen.isReadAhead` is the one place to widen this
   when the server exposes a per-message read state.
2. **The composer omits embeds and replies.** Both are out of the minimal 1:1
   scope. The text path is the whole composer.
3. **Reactions use a menu, not a custom emoji picker.** The quick reaction set is
   a `Menu`; the RN app has a bespoke picker.
4. **Scroll-to-bottom is a button, not a scroll-position effect.** The list
   auto-scrolls when a row is appended; the button appears only when the newest
   row is off screen, gated on `onScrollGeometryChange`.
5. **No session/root takeover.** The screens are fixture-backed and mountable
   from a debug toolbar, matching `LoginScreen`: deciding what the app root shows
   once a session exists is the app shell's call.

## Not implemented here

- Live transport wiring (the app's `XrpcClient` over the chat proxy) - the
  screens take a `ConversationModel`/`InboxQuery` the caller builds.
- Log-driven live updates in the screens: `ConversationViewModel.ingest(_:)` and
  `InboxViewModel.reloadFromCache()` are the seams, and the app's `LogSync` loop
  is what would call them.
- Group, request, join-link and join-request surfaces.

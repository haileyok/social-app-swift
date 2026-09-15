# VideoFeedViews

The immersive, full-screen vertical video feed for the Swift app: a vertical
pager whose pages are video posts, an `AVPlayer`-backed player surface with a
three-slot recycling pool, and the overlay chrome.

This is a `Views` package (⌨ Mac-CI-only), so importing SwiftUI and AVFoundation
is expected; the Linux boundary-lint does not scan it. Every decision it makes
lives in `VideoFeedLogic` next door.

## What lives where

| File | Role |
|---|---|
| `VideoFeedScreen.swift` | Public entry point. Owns the controller, wires the pager and the settings. |
| `VideoFeedController.swift` | The policy plumbing: active index, three-slot reconciliation, autoplay gating. |
| `VideoFeedPager.swift` | `UIScrollView`-backed vertical pager reporting a fractional viewport. |
| `VideoFeedPage.swift` | One page: media, tap surface, scrubber, overlay, moderation blur. |
| `VideoPlayerView.swift` | `VideoPlayerSlot` (one recycled `AVPlayer`), phase model, caption selection. |
| `VideoPlayerSurface.swift` | The `AVPlayerLayer` host view. |
| `VideoItemOverlay.swift` | Author row, caption, mute control, engagement affordances. |
| `VideoScrubber.swift` | Draggable progress track and time labels. |
| `VideoFeedFixtures.swift` | Three sample items for the debug entry point. |
| `VideoFeedStrings.swift` | Every user-facing string, in one place. |
| `VideoFeedAccessibility.swift` | Accessibility identifiers shared with the UI tests. |

## The player pool

RN's immersive screen recycles three players by `index % 3`. The arithmetic is
owned by `VideoFeedLogic`:

- `playerSlotAssignments(activeIndex:count:poolSize:)` returns the slot → item
  map for the active index and its two neighbours;
- `playerPoolSlot(for:poolSize:)` is the single-index form.

`VideoFeedController.synchronize()` applies that map: slots that lost their item
are detached, slots that gained one are attached, and each is then gated. A
preloaded neighbour is loaded but paused, which is what makes a swipe land on a
ready frame instead of a second of black.

## The gates

Nothing here decides whether a video may play. The controller asks:

- `videoAutoplayDecision(settings:moderation:)` - the moderation blur wins over
  the autoplay preference, and a message-thread video is never started;
- `videoBeginMuted(settings:isGif:)` - a GIF always starts muted, but a video
  with autoplay disabled starts **unmuted**, because the viewer tapped it;
- `VideoPagerStateMachine` - which item is active and which indices are in the
  preload window.

A revealed moderation blur is recorded by the controller
(`revealModeration(at:)`) and lets that item play; the view never overrides the
gate on its own.

## Gestures

Single tap toggles play/pause; a double tap likes the post. That is the RN
behaviour (`onPress` in `src/screens/VideoFeed/index.tsx`): a first tap arms a
200 ms timer and a second tap inside it calls `queueLike()` instead. SwiftUI
serialises the two recognizers itself, so the single-tap handler only runs once
the double tap has failed.

## Captions

`app.bsky.embed.video#main` declares caption blobs by CID, and dereferencing one
to a playable URL needs the account's authenticated blob endpoint, which this
package does not own. `VideoPlayerSlot` therefore offers the tracks the player's
own legible media selection group exposes - a stream with embedded captions
offers them, a stream whose captions live only on the record offers none - and
the overlay shows a picker only when there is something to pick. Wiring the
record's `VideoCaptionTrack` blobs through the account's agent is the follow-up
that would complete this.

## Trying it

`VideoFeedSurfaces.videoFeedScreen(theme:)` in `App/Sources/AppShell/AppShell+VideoFeedViews.swift`
mounts the screen against `VideoFeedFixtures.items()` - three publicly playable
sample streams - so the player is exercisable from a debug toolbar without a
signed-in account or a feed fetch.

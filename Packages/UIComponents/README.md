# UIComponents

The shared component library for the Swift app: standard SwiftUI patterns
carrying Bluesky identity through `DesignSystem`.

## Target layout

The package boundary is the platform boundary, same as `DesignSystem`:

| Target | Framework | Verified |
| --- | --- | --- |
| `UIComponentsCore` | none (Foundation only) | Linux (`swift build && swift test`) |
| `UIComponents` | SwiftUI | macOS CI (`ios-selfhosted`) |

Every file in `UIComponents` is wrapped in `#if canImport(SwiftUI)`, so
`swift test` still builds the whole package on Linux and runs the Core tests
locally. The Mac CI build is the verification of record for the views.

## What is in v1

- **`PostFeedItem`** - author line, RichText body, engagement row, context line,
  embed, moderation masks. Rendering data comes from `feedItemViewData(_:)`, a
  pure function of a `PostView`.
- **`PostEmbed`** - the embed matrix: image gallery (1/2/3/4-up), external card,
  quoted post (hydrated, blocked, not-found), record-with-media, video
  placeholder.
- **Buttons** - the RN `color` x `size` x `shape` matrix as `AlfButtonStyle`
  (`ResolvedButton.resolve` holds the token and metric tables).
- **`Avatar`/`AvatarPlaceholder`/`Banner`** - image loading through the injected
  `ImageLoading`, with an initials fallback. No third-party dependency.
- **List states** - `ListSkeleton`, `EmptyStateView`, `ErrorStateView`,
  `RetryRow`, `LoadMoreSpinner`, driven by `ListState`.
- **Toasts** - `ToastPresenter` + `.toastPresenter(_:)` and `ToastBanner`.
- **`ModerationMask`** - blur/hide with a reveal affordance, driven by a
  `ModerationSurface` projected from a `ModerationDecision`.

`ComponentGallery` renders all of the above per theme. It is internal to the app
(reachable from `AppShell+Components.swift`), not a shipped surface.

## Wiring the image loader

`PlaceholderImageLoader` renders nothing, which is enough for previews and the
gallery. The app installs its real loader once at the root:

```swift
RootView().imageLoader(AppImageLoader())
```

`ImageLoading.loadImage(at:targetSize:)` takes a `ImageTargetSize` so the
implementation can downsample rather than decode full-resolution bytes.

## Deferred

- Dialog and Menu (the RN app keeps these separate; not ported).
- Video playback (v1 renders `VideoPlaceholder`).
- A full-lexicon adapter from `App.Bsky.FeedDefs_PostView` onto the render model.
- Localization of the component copy (v1 ships English strings, like the
  gallery).

## Deviations from the brief

- **No `Domain` dependency.** `Packages/Domain` declares no iOS platform, and it
  transitively depends on `Lexicons` (iOS 18) and `SwiftAtproto` (iOS 17), so
  linking it into an iOS target fails. The two functions the library needs
  (`formatCount`, `formatDateDiff`) are reproduced unchanged in
  `UIComponentsCore/MetricFormatting.swift`, with a note to delete them once
  `Domain` gains an iOS platform declaration.
- **`Moderation`'s stand-in types are the render model.** The generated
  `App.Bsky.FeedDefs_PostView` keeps `record` as an opaque `UnknownATPValue`, so
  the post text and facets are not directly reachable; the engine's `PostView`
  carries them and is what `moderatePost` already decides. The engagement counts
  are passed separately (`FeedItemCounts`), because the engine's stand-in type
  has no count fields.
- **Engagement counts are supplied, not read.** See above: the view takes
  `FeedItemCounts` alongside the `PostView`.

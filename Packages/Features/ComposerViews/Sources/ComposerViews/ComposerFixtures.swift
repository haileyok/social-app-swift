#if canImport(SwiftUI)
import ComposerLogic
import Foundation
import Lexicons

/// The shape the composer debug surface renders, and the fixture set the
/// screenshots and previews are driven from.
///
/// The same arrangement `ComponentGallery` and `EmbedFixtures` use: a small enum
/// of named states, each turning into a real ``ComposerState`` through the
/// reducer's own constructors, so a fixture cannot drift from what the app
/// actually puts in the state. Nothing here invents a state the reducer could
/// not produce.
public enum ComposerSurface: String, CaseIterable, Sendable {
  /// A blank composer.
  case empty
  /// Text with link and mention facets, well under the limit.
  case text
  /// A reply, with the reply-context header.
  case reply
  /// A quote post, with the quote-context header.
  case quote
  /// Two images attached, one still missing alt text.
  case images
  /// A thread of three posts, one of them empty and non-trailing.
  case thread
  /// An attached video mid-pipeline.
  case video
  /// A post that is over the grapheme limit, with the counter in the error state.
  case overLimit
  /// A post whose video pipeline failed, blocking publish.
  case videoFailed
  /// A reply-gated thread with self-labels attached.
  case gated
  /// An attached GIF missing alt text.
  case gif
  /// The publish-progress state.
  case publishing
  /// The publish-failure state.
  case publishFailed
}

/// Fixture builders for ``ComposerSurface``.
public enum ComposerFixtures {
  /// The order the debug surface and the screenshot loop walk.
  public static let allSurfaces = ComposerSurface.allCases

  /// The composer state for a surface.
  ///
  /// Every case starts from ``ComposerReducer/createState(_:)`` and applies
  /// ordinary actions, so the fixtures exercise the real reducer paths.
  public static func state(for surface: ComposerSurface) -> ComposerState {
    switch surface {
    case .empty:
      return ComposerReducer.createState(ComposerInit())

    case .text:
      return withText(
        "Hello Bluesky! Links like bsky.app and mentions like @bsky.app are detected as facets.")

    case .reply:
      return withText("That is a good point - I had not thought about it that way.")

    case .quote:
      return withText(
        "This is worth reading.",
        quoteUri: "at://did:plc:fixture/app.bsky.feed.post/3kabc")

    case .images:
      return withImages(count: 2, describedCount: 1)

    case .thread:
      var state = withText("First post in the thread.")
      state = ComposerReducer.reduce(state, .addPost(newId: "fixture-1"))
      // The middle post is deliberately left blank: that is the non-trailing
      // empty post the publish path warns about.
      state = ComposerReducer.reduce(state, .addPost(newId: "fixture-2"))
      state = ComposerReducer.reduce(
        state,
        .updatePost(
          postId: "fixture-2",
          action: .updateRichText(RichTextValue(text: "And a third to close it out."))))
      return state

    case .video:
      return withVideo(status: .processing)

    case .overLimit:
      return withText(String(repeating: "blah ", count: 70))

    case .videoFailed:
      return withVideo(status: .error)

    case .gated:
      var state = withText("A post with warnings and a reply gate.")
      state = ComposerReducer.reduce(
        state,
        .updatePostgate(
          ComposerGates.placeholderPostgateRecord(embeddingRules: [ComposerGates.disableRule])))
      state = ComposerReducer.reduce(state, .updateThreadgate([.followers, .mention]))
      state = ComposerReducer.reduce(
        state,
        .updatePost(
          postId: "fixture-0",
          action: .updateLabels(SelfLabelSet(values: [SelfLabels.other[0]]))))
      return state

    case .gif:
      var state = withText("Look at this one.")
      state = ComposerReducer.reduce(
        state,
        .updatePost(
          postId: "fixture-0",
          action: .addGif(
            GifMedia(
              gif: ComposerGif(url: "https://media.tenor.com/fixture.gif", width: 320, height: 240)))))
      return state

    case .publishing, .publishFailed:
      return withText("Publishing a post from the fixture surface.")
    }
  }

  /// The reply context a surface shows, when it has one.
  public static func replyContext(for surface: ComposerSurface) -> ComposerReplyContext? {
    guard surface == .reply else { return nil }
    return ComposerReplyContext(
      displayName: "Bluesky",
      handle: "bsky.app",
      text: "The original post this is replying to, kept on screen so the author can write with the thread's context in view.")
  }

  /// The publish phase a surface renders.
  public static func publishPhase(for surface: ComposerSurface) -> ComposerPublishPhase? {
    switch surface {
    case .publishing: .posting(detail: ComposerCopy.publishingLabel)
    case .publishFailed: .failed(message: ComposerCopy.publishFailed)
    default: nil
    }
  }

  /// Draft rows for the drafts sheet on a surface.
  ///
  /// Built through ``ComposerDrafts/summarise(id:createdAt:updatedAt:draft:)``
  /// rather than by hand: the summary shape is the drafts layer's to define, and
  /// this way the sheet renders exactly what the real path produces.
  public static func draftRows(for surface: ComposerSurface) -> [DraftSummary] {
    guard surface == .empty else { return [] }
    let drafts = ComposerDrafts(service: FixtureDraftsService(), deviceId: "fixture-device")
    let now = "2026-09-16T12:00:00.000Z"
    return [
      drafts.summarise(
        id: "draft-1",
        createdAt: now,
        updatedAt: now,
        draft: App.Bsky.DraftDefs_Draft(posts: [
          App.Bsky.DraftDefs_DraftPost(text: "A draft I started yesterday.")
        ])),
      drafts.summarise(
        id: "draft-2",
        createdAt: now,
        updatedAt: now,
        draft: App.Bsky.DraftDefs_Draft(posts: [
          App.Bsky.DraftDefs_DraftPost(text: "Another draft, with an image and a link."),
          App.Bsky.DraftDefs_DraftPost(text: "Plus a continuation."),
        ])),
    ]
  }

  // MARK: - Builders

  private static func withText(_ text: String, quoteUri: String? = nil) -> ComposerState {
    // `createState` already runs facet detection over the initial text, which is
    // the same path a share intent takes.
    ComposerReducer.createState(ComposerInit(text: text, quoteUri: quoteUri))
  }

  private static func withImages(count: Int, describedCount: Int) -> ComposerState {
    var state = ComposerReducer.createState(ComposerInit())
    let images = (0..<count).map { index in
      ComposerImage(
        id: "image-\(index)",
        path: "fixture://image-\(index).jpg",
        width: 1600,
        height: 1200,
        alt: index < describedCount ? "A described image." : "")
    }
    state = ComposerReducer.reduce(
      state, .updatePost(postId: "fixture-0", action: .addImages(images)))
    return state
  }

  private enum VideoFixtureStatus { case processing, error }

  private static func withVideo(status: VideoFixtureStatus) -> ComposerState {
    var state = ComposerReducer.createState(ComposerInit())
    let token = VideoJobToken(id: "fixture-job")
    let asset = ComposerVideoAsset(
      uri: "fixture://clip.mp4", size: 8_400_000, width: 1920, height: 1080, durationMs: 12_000)
    let video: ComposerVideo
    switch status {
    case .processing:
      video = .processing(
        VideoProcessingState(
          progress: 0.62,
          token: token,
          asset: asset,
          video: CompressedVideo(
            uri: "fixture://clip-compressed.mp4", mimeType: "video/mp4", size: 3_100_000),
          jobId: "job-fixture",
          jobStatus: nil,
          altText: "",
          captions: []))
    case .error:
      video = .error(
        VideoErrorState(
          progress: 0.2,
          token: token,
          error: "This video is too long.",
          asset: asset,
          video: nil,
          jobId: nil,
          altText: "",
          captions: []))
    }
    state = ComposerReducer.reduce(
      state, .updatePost(postId: "fixture-0", action: .addVideo(video)))
    return state
  }
}

/// The drafts service behind the fixture draft rows.
///
/// It exists so the fixtures go through the real drafts layer instead of hand-
/// building a `DraftSummary` (whose initialiser is internal to `ComposerLogic`).
/// Nothing here talks to a server; the get-drafts call returns an empty page and
/// the rows come from ``ComposerFixtures/draftRows(for:)``'s own drafts.
struct FixtureDraftsService: ComposerDraftsService {
  func getDrafts(cursor: String?) async throws -> App.Bsky.DraftGetDrafts_Output {
    App.Bsky.DraftGetDrafts_Output(drafts: [])
  }

  func createDraft(_ draft: App.Bsky.DraftDefs_Draft) async throws -> String { "fixture-draft" }

  func updateDraft(id: String, draft: App.Bsky.DraftDefs_Draft) async throws {}

  func deleteDraft(id: String) async throws {}
}

/// The reply-context header's data.
///
/// The composer holds a reply target as a resolved `ReplyContext` (strong refs),
/// which carries no display text. The transport that opened the composer has the
/// hydrated post, so it hands the header these three fields.
public struct ComposerReplyContext: Hashable, Sendable {
  /// The author's display name.
  public var displayName: String
  /// The author's handle, without the leading `@`.
  public var handle: String
  /// The target post's text.
  public var text: String

  public init(displayName: String, handle: String, text: String) {
    self.displayName = displayName
    self.handle = handle
    self.text = text
  }
}

/// The publish phase the screen renders.
///
/// A small, view-owned union: the publish flow in `ComposerLogic` is a sequence
/// of record writes and blob uploads with no progress value, so the screen only
/// needs to know which of these it is in.
public enum ComposerPublishPhase: Hashable, Sendable {
  /// Records are being written; `detail` is the line under the spinner.
  case posting(detail: String)
  /// The publish failed; `message` is the line in the failure banner.
  case failed(message: String)
}
#endif

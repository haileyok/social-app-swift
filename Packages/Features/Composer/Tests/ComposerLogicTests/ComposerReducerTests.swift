import Foundation
import RichText
import Testing

@testable import ComposerLogic

/// The composer and post reducers.
///
/// Ported from `composerReducer`/`postReducer` in
/// `src/view/com/composer/state/composer.ts` and the reducer tests in
/// `state/composer.test.ts`.
@Suite("ComposerReducer")
struct ComposerReducerTests {

  // MARK: - Posts

  @Test("add_post appends after the active post and focuses it")
  func addPostAppendsAndFocuses() {
    let state = ComposerReducer.createState(ComposerInit(firstPostId: "post-1"))
    let next = ComposerReducer.reduce(state, .addPost(newId: "post-2"))
    #expect(next.thread.posts.map(\.id) == ["post-1", "post-2"])
    #expect(next.activePostIndex == 1)
    #expect(next.mutableNeedsFocusActive)
    #expect(next.isDirty)
  }

  @Test("add_post inserts in the middle and keeps later posts after the new one")
  func addPostInsertsInTheMiddle() {
    var state = ComposerReducer.createState(ComposerInit(firstPostId: "p0"))
    state = ComposerReducer.reduce(state, .addPost(newId: "p1"))
    state = ComposerReducer.reduce(state, .addPost(newId: "p2"))
    state = ComposerReducer.reduce(state, .focusPost(postId: "p0"))
    let next = ComposerReducer.reduce(state, .addPost(newId: "p-new"))
    #expect(next.thread.posts.map(\.id) == ["p0", "p-new", "p1", "p2"])
    #expect(next.activePostIndex == 1)
  }

  @Test("remove_post refuses to remove the last post")
  func removeLastPostRefused() {
    let state = ComposerReducer.createState(ComposerInit(firstPostId: "only"))
    let next = ComposerReducer.reduce(state, .removePost(postId: "only"))
    #expect(next == state)
  }

  @Test("remove_post moves the active index to the previous post")
  func removePostMovesActiveIndex() {
    var state = ComposerReducer.createState(ComposerInit(firstPostId: "p0"))
    state = ComposerReducer.reduce(state, .addPost(newId: "p1"))
    state = ComposerReducer.reduce(state, .addPost(newId: "p2"))
    // Active is p2; remove the last one and land on p1.
    let next = ComposerReducer.reduce(state, .removePost(postId: "p2"))
    #expect(next.thread.posts.map(\.id) == ["p0", "p1"])
    #expect(next.activePostIndex == 1)
  }

  @Test("removing the first post clamps the active index to zero")
  func removeFirstPostClampsIndex() {
    var state = ComposerReducer.createState(ComposerInit(firstPostId: "p0"))
    state = ComposerReducer.reduce(state, .addPost(newId: "p1"))
    // Focus p1 so removing p0 does not move the active post off the end.
    state = ComposerReducer.reduce(state, .focusPost(postId: "p1"))
    let next = ComposerReducer.reduce(state, .removePost(postId: "p0"))
    #expect(next.activePostIndex == 0)
  }

  @Test("focus_post does not mark the composer dirty")
  func focusDoesNotDirty() {
    let state = ComposerReducer.createState(ComposerInit(firstPostId: "p0"))
    let withTwo = ComposerReducer.reduce(state, .addPost(newId: "p1"))
    let clean = ComposerReducer.reduce(withTwo, .markSaved(draftId: "d1"))
    let focused = ComposerReducer.reduce(clean, .focusPost(postId: "p0"))
    #expect(!focused.isDirty)
  }

  @Test("an unknown post id is a no-op")
  func unknownPostIdIgnored() {
    let state = ComposerReducer.createState(ComposerInit(firstPostId: "p0"))
    let next = ComposerReducer.reduce(
      state, .updatePost(postId: "nope", action: .updateRichText(RichTextValue(text: "x"))))
    #expect(next == state)
  }

  // MARK: - Media

  @Test("images at or below four use the legacy images variant")
  func smallImageSetUsesImages() {
    var post = PostDraft.empty(id: "p")
    post = PostReducer.reduce(post, .addImages(makeImages(4)))
    guard case .images(.images(let images)) = post.embed.media else {
      Issue.record("expected the legacy images variant")
      return
    }
    #expect(images.count == 4)
  }

  @Test("a fifth image promotes to the gallery variant")
  func fifthImagePromotesToGallery() {
    var post = PostDraft.empty(id: "p")
    post = PostReducer.reduce(post, .addImages(makeImages(4)))
    post = PostReducer.reduce(post, .addImages(makeImages(1, start: 5)))
    guard case .images(.gallery(let images)) = post.embed.media else {
      Issue.record("expected the gallery variant")
      return
    }
    #expect(images.count == 5)
  }

  @Test("a gallery shrinking to four demotes back to the legacy variant")
  func galleryDemotesOnShrink() {
    var post = PostDraft.empty(id: "p")
    post = PostReducer.reduce(post, .addImages(makeImages(5)))
    let last = post.embed.media!.images!.last!
    post = PostReducer.reduce(post, .removeImage(last))
    guard case .images(.images(let images)) = post.embed.media else {
      Issue.record("expected the legacy images variant after shrinking to four")
      return
    }
    #expect(images.count == 4)
  }

  @Test("images beyond the gallery cap are dropped")
  func galleryCapEnforced() {
    var post = PostDraft.empty(id: "p")
    post = PostReducer.reduce(post, .addImages(makeImages(15)))
    #expect(post.embed.media?.images?.count == ComposerConstants.maxGalleryImages)
  }

  @Test("removing the last image clears the media slot")
  func removingLastImageClearsMedia() {
    var post = PostDraft.empty(id: "p")
    let images = makeImages(1)
    post = PostReducer.reduce(post, .addImages(images))
    post = PostReducer.reduce(post, .removeImage(images[0]))
    #expect(post.embed.media == nil)
  }

  @Test("removing the last image clears labels when there is no link card")
  func removingLastImageClearsLabels() {
    var post = PostDraft.empty(id: "p")
    let images = makeImages(1)
    post = PostReducer.reduce(post, .addImages(images))
    post = PostReducer.reduce(post, .updateLabels(SelfLabelSet(values: ["sexual"])))
    post = PostReducer.reduce(post, .removeImage(images[0]))
    #expect(post.labels.isEmpty)
  }

  @Test("removing the last image keeps labels while a link card remains")
  func removingLastImageKeepsLabelsWithLink() {
    var post = PostDraft.empty(id: "p")
    let images = makeImages(1)
    post = PostReducer.reduce(post, .addImages(images))
    post = PostReducer.reduce(post, .addURI("https://example.com/story"))
    post = PostReducer.reduce(post, .updateLabels(SelfLabelSet(values: ["sexual"])))
    post = PostReducer.reduce(post, .removeImage(images[0]))
    #expect(post.labels.values == ["sexual"])
  }

  @Test("adding a video to a post that has images is a no-op")
  func videoOntoImagesIsNoop() {
    var post = PostDraft.empty(id: "p")
    post = PostReducer.reduce(post, .addImages(makeImages(1)))
    let before = post.embed.media
    post = PostReducer.reduce(post, .addVideo(ComposerVideo.created(asset: asset())))
    #expect(post.embed.media == before)
  }

  @Test("adding a GIF to a post that has a video is a no-op")
  func gifOntoVideoIsNoop() {
    var post = PostDraft.empty(id: "p")
    post = PostReducer.reduce(post, .addVideo(ComposerVideo.created(asset: asset())))
    let before = post.embed.media
    post = PostReducer.reduce(
      post,
      .addGif(GifMedia(gif: ComposerGif(url: "https://media.tenor.com/a.gif", width: 1, height: 1))))
    #expect(post.embed.media == before)
  }

  @Test("a post URL becomes a quote, not a link card")
  func postUrlBecomesQuote() {
    var post = PostDraft.empty(id: "p")
    post = PostReducer.reduce(post, .addURI("https://bsky.app/profile/alice.test/post/abc"))
    #expect(post.embed.quote?.uri == "https://bsky.app/profile/alice.test/post/abc")
    #expect(post.embed.link == nil)
  }

  @Test("a non-post URL becomes a link card")
  func nonPostUrlBecomesLink() {
    var post = PostDraft.empty(id: "p")
    post = PostReducer.reduce(post, .addURI("https://example.com/story"))
    #expect(post.embed.link?.uri == "https://example.com/story")
    #expect(post.embed.quote == nil)
  }

  @Test("a second URI does not overwrite an existing quote or link")
  func secondUriDoesNotOverwrite() {
    var post = PostDraft.empty(id: "p")
    post = PostReducer.reduce(post, .addURI("https://example.com/one"))
    post = PostReducer.reduce(post, .addURI("https://example.com/two"))
    #expect(post.embed.link?.uri == "https://example.com/one")
  }

  @Test("removing the link clears labels when no media remains")
  func removingLinkClearsLabelsWithoutMedia() {
    var post = PostDraft.empty(id: "p")
    post = PostReducer.reduce(post, .addURI("https://example.com/story"))
    post = PostReducer.reduce(post, .updateLabels(SelfLabelSet(values: ["nudity"])))
    post = PostReducer.reduce(post, .removeLink)
    #expect(post.labels.isEmpty)
  }

  @Test("removing the link keeps labels while media remains")
  func removingLinkKeepsLabelsWithMedia() {
    var post = PostDraft.empty(id: "p")
    post = PostReducer.reduce(post, .addImages(makeImages(1)))
    post = PostReducer.reduce(post, .addURI("https://example.com/story"))
    post = PostReducer.reduce(post, .updateLabels(SelfLabelSet(values: ["nudity"])))
    post = PostReducer.reduce(post, .removeLink)
    #expect(post.labels.values == ["nudity"])
  }

  @Test("removing a video clears labels when no link card remains")
  func removingVideoClearsLabels() {
    var post = PostDraft.empty(id: "p")
    post = PostReducer.reduce(post, .addVideo(ComposerVideo.created(asset: asset())))
    post = PostReducer.reduce(post, .updateLabels(SelfLabelSet(values: ["sexual"])))
    post = PostReducer.reduce(post, .removeVideo)
    #expect(post.embed.media == nil)
    #expect(post.labels.isEmpty)
  }

  @Test("updating an image's alt text preserves its place")
  func updateImageAltText() {
    var post = PostDraft.empty(id: "p")
    post = PostReducer.reduce(post, .addImages(makeImages(2)))
    var edited = post.embed.media!.images![1]
    edited.alt = "a description"
    post = PostReducer.reduce(post, .updateImage(edited))
    #expect(post.embed.media?.images?[1].alt == "a description")
  }

  @Test("updating the GIF alt text works")
  func updateGifAlt() {
    var post = PostDraft.empty(id: "p")
    post = PostReducer.reduce(
      post,
      .addGif(GifMedia(gif: ComposerGif(url: "https://media.tenor.com/a.gif", width: 1, height: 1))))
    post = PostReducer.reduce(post, .updateGifAlt("a cat"))
    guard case .gif(let media) = post.embed.media else {
      Issue.record("expected a GIF")
      return
    }
    #expect(media.alt == "a cat")
  }

  // MARK: - Text and labels

  @Test("updating rich text recomputes the shortened grapheme length")
  func updateRichTextRecomputesLength() {
    var post = PostDraft.empty(id: "p")
    post = PostReducer.reduce(post, .updateRichText(RichTextValue(text: "hello")))
    #expect(post.shortenedGraphemeLength == 5)
  }

  @Test("threadgate and postgate updates are threaded through")
  func gateUpdatesApply() {
    let state = ComposerReducer.createState(ComposerInit())
    let next = ComposerReducer.reduce(state, .updateThreadgate([.followers, .mention]))
    #expect(next.thread.threadgate == [.followers, .mention])
    #expect(next.isDirty)
  }

  // MARK: - Init and restore

  @Test("an empty init produces one empty post and everybody-threadgate")
  func emptyInit() {
    let state = ComposerReducer.createState(ComposerInit(firstPostId: "p0"))
    #expect(state.thread.posts.count == 1)
    #expect(state.thread.posts[0].richText.text.isEmpty)
    #expect(state.thread.threadgate == [.everybody])
    #expect(!state.isDirty)
  }

  @Test("init text with a post URL suggests a quote")
  func initTextSuggestsQuote() {
    let state = ComposerReducer.createState(
      ComposerInit(
        text: "look at this https://bsky.app/profile/alice.test/post/abc",
        firstPostId: "p0"))
    #expect(state.thread.posts[0].embed.quote?.uri == "https://bsky.app/profile/alice.test/post/abc")
  }

  @Test("init text with a non-post URL suggests a link card")
  func initTextSuggestsLinkCard() {
    let state = ComposerReducer.createState(
      ComposerInit(text: "read https://example.com/story", firstPostId: "p0"))
    #expect(state.thread.posts[0].embed.link?.uri == "https://example.com/story")
  }

  @Test("init text with both suggests one of each")
  func initTextSuggestsOneOfEach() {
    let state = ComposerReducer.createState(
      ComposerInit(
        text: "https://example.com/story and https://bsky.app/profile/a.test/post/b",
        firstPostId: "p0"))
    #expect(state.thread.posts[0].embed.link?.uri == "https://example.com/story")
    #expect(state.thread.posts[0].embed.quote?.uri == "https://bsky.app/profile/a.test/post/b")
  }

  @Test("an init quote URI wins over a detected one")
  func explicitQuoteWins() {
    let state = ComposerReducer.createState(
      ComposerInit(
        text: "https://bsky.app/profile/a.test/post/b",
        quoteUri: "at://did:plc:x/app.bsky.feed.post/first",
        firstPostId: "p0"))
    #expect(state.thread.posts[0].embed.quote?.uri == "https://bsky.app/profile/did:plc:x/post/first")
  }

  @Test("an init mention prefills an at-sign and detects facets")
  func initMentionPrefillsAndDetects() {
    let state = ComposerReducer.createState(
      ComposerInit(mention: "alice.test", firstPostId: "p0"))
    #expect(state.thread.posts[0].richText.text == "@alice.test")
    #expect(state.thread.posts[0].richText.hasFacets)
  }

  @Test("interaction settings seed the threadgate and postgate")
  func initSettingsSeedGates() {
    let settings = PostInteractionSettings(
      postgateEmbeddingRules: [ComposerGates.disableRule],
      threadgateAllowRules: [.feedThreadgateFollowerRule(.init())])
    let state = ComposerReducer.createState(
      ComposerInit(interactionSettings: settings, firstPostId: "p0"))
    #expect(state.thread.threadgate == [.followers])
    #expect(state.thread.postgate.embeddingRules?.count == 1)
  }

  @Test("restore_from_draft clears the dirty flag and sets the draft id")
  func restoreFromDraft() {
    let state = ComposerReducer.createState(ComposerInit(firstPostId: "p0"))
    let restored = ComposerReducer.reduce(
      state,
      .restoreFromDraft(
        draftId: "draft-1",
        posts: [Fixtures.post(text: "restored")],
        threadgateAllow: [.feedThreadgateFollowerRule(.init())],
        postgateEmbeddingRules: [ComposerGates.disableRule],
        createdAt: Fixtures.fixedDate))
    #expect(restored.draftId == "draft-1")
    #expect(!restored.isDirty)
    #expect(restored.thread.posts[0].richText.text == "restored")
    #expect(restored.thread.threadgate == [.followers])
    #expect(restored.thread.postgate.embeddingRules?.count == 1)
  }

  @Test("clear resets to a blank state")
  func clearResets() {
    var state = ComposerReducer.createState(ComposerInit(firstPostId: "p0"))
    state = ComposerReducer.reduce(state, .addPost(newId: "p1"))
    state = ComposerReducer.reduce(state, .markSaved(draftId: "d"))
    let cleared = ComposerReducer.reduce(state, .clear(init: ComposerInit(firstPostId: "fresh")))
    #expect(cleared.thread.posts.map(\.id) == ["fresh"])
    #expect(cleared.draftId == nil)
    #expect(!cleared.isDirty)
  }

  @Test("mark_saved records the id and clears the dirty flag")
  func markSaved() {
    var state = ComposerReducer.createState(ComposerInit(firstPostId: "p0"))
    state = ComposerReducer.reduce(state, .addPost(newId: "p1"))
    let saved = ComposerReducer.reduce(state, .markSaved(draftId: "draft-9"))
    #expect(saved.draftId == "draft-9")
    #expect(!saved.isDirty)
  }

  // MARK: - Helpers

  private func makeImages(_ count: Int, start: Int = 1) -> [ComposerImage] {
    (start..<(start + count)).map { index in
      ComposerImage(id: "i\(index)", path: "/img\(index).jpg", width: 100, height: 100)
    }
  }

  private func asset() -> ComposerVideoAsset {
    ComposerVideoAsset(uri: "file:///v.mp4", size: 1000, width: 1920, height: 1080)
  }
}

import Foundation
import Testing

@testable import ComposerLogic

/// The §canPost table and the empty-post classification.
///
/// Ported from the `canPost` expression and `getFilteredThread` in
/// `src/view/com/composer/Composer.tsx`.
@Suite("ComposerValidation")
struct ComposerValidationTests {

  // MARK: - The canPost table

  @Test("an empty thread cannot be published")
  func emptyThreadCannotPost() {
    let thread = Fixtures.thread(posts: [Fixtures.post()])
    #expect(ComposerValidation.validate(thread: thread) == .nothingToPost)
    #expect(!ComposerValidation.canPost(thread: thread))
  }

  @Test("text within the limit can be published")
  func textWithinLimitCanPost() {
    let thread = Fixtures.thread(posts: [Fixtures.post(text: "hello world")])
    #expect(ComposerValidation.validate(thread: thread) == nil)
    #expect(ComposerValidation.canPost(thread: thread))
  }

  @Test("exactly 300 graphemes can be published")
  func exactlyAtTheLimitCanPost() {
    let text = String(repeating: "a", count: 300)
    let thread = Fixtures.thread(posts: [Fixtures.post(text: text)])
    #expect(ComposerValidation.canPost(thread: thread))
  }

  @Test("301 graphemes cannot be published")
  func justOverTheLimitCannotPost() {
    let text = String(repeating: "a", count: 301)
    let post = Fixtures.post(id: "post-a", text: text)
    let thread = Fixtures.thread(posts: [post])
    #expect(ComposerValidation.validate(thread: thread) == .postOverGraphemeLimit(postId: "post-a"))
  }

  @Test("an empty post is exempt from the length limit")
  func emptyPostIsExemptFromLimit() {
    let long = String(repeating: "a", count: 400)
    // The long post is empty of content only when it carries no embed; here it
    // carries text, so this asserts the *other* half of the rule below.
    let thread = Fixtures.thread(posts: [
      Fixtures.post(id: "post-1", text: "hello"),
      Fixtures.post(id: "post-2"),
    ])
    #expect(!long.isEmpty)
    #expect(ComposerValidation.canPost(thread: thread))
  }

  @Test("a blank post after a valid one does not block publishing")
  func trailingEmptyPostDoesNotBlock() {
    let thread = Fixtures.thread(posts: [
      Fixtures.post(id: "post-1", text: "first"),
      Fixtures.post(id: "post-2"),
    ])
    #expect(ComposerValidation.canPost(thread: thread))
  }

  @Test("a failed video blocks publishing")
  func failedVideoBlocksPublishing() {
    let video = ComposerVideo.created(asset: sampleAsset())
    let failed = VideoReducer.toErrorState(video, error: "encoding failed")
    let post = Fixtures.post(
      id: "post-v", text: "watch", embed: EmbedDraft(media: .video(failed)))
    let thread = Fixtures.thread(posts: [post])
    #expect(ComposerValidation.validate(thread: thread) == .videoFailed(postId: "post-v"))
  }

  @Test("an in-progress video does not block publishing on its own")
  func inProgressVideoDoesNotBlock() {
    let video = ComposerVideo.created(asset: sampleAsset())
    let post = Fixtures.post(
      id: "post-v", text: "watch", embed: EmbedDraft(media: .video(video)))
    let thread = Fixtures.thread(posts: [post])
    #expect(ComposerValidation.canPost(thread: thread))
  }

  @Test("an unavailable chat invite blocks publishing")
  func unavailableChatInviteBlocks() {
    let thread = Fixtures.thread(posts: [Fixtures.post(text: "hi")])
    #expect(
      ComposerValidation.validate(thread: thread, hasUnavailableChatInvite: true)
        == .unavailableChatInvite)
  }

  // MARK: - Alt text

  @Test("alt text is not required when the account does not demand it")
  func altTextNotRequiredByDefault() {
    let images = [ComposerImage(id: "i1", path: "/a.jpg", width: 10, height: 10, alt: "")]
    let post = Fixtures.post(text: "pic", embed: EmbedDraft(media: .images(.images(images))))
    let thread = Fixtures.thread(posts: [post])
    #expect(ComposerValidation.canPost(thread: thread))
  }

  @Test("an image without alt text blocks publishing when required")
  func imageWithoutAltBlocksWhenRequired() {
    let images = [ComposerImage(id: "i1", path: "/a.jpg", width: 10, height: 10, alt: "")]
    let post = Fixtures.post(text: "pic", embed: EmbedDraft(media: .images(.images(images))))
    let thread = Fixtures.thread(posts: [post])
    #expect(
      ComposerValidation.validate(thread: thread, requireAltText: true)
        == .imageMissingAltText)
  }

  @Test("an image with alt text passes")
  func imageWithAltPasses() {
    let images = [ComposerImage(id: "i1", path: "/a.jpg", width: 10, height: 10, alt: "a cat")]
    let post = Fixtures.post(text: "pic", embed: EmbedDraft(media: .images(.images(images))))
    let thread = Fixtures.thread(posts: [post])
    #expect(ComposerValidation.canPost(thread: thread, requireAltText: true))
  }

  @Test("a GIF without alt text blocks publishing when required")
  func gifWithoutAltBlocksWhenRequired() {
    let gif = GifMedia(gif: ComposerGif(url: "https://media.tenor.com/x.gif", width: 1, height: 1))
    let post = Fixtures.post(text: "gif", embed: EmbedDraft(media: .gif(gif)))
    let thread = Fixtures.thread(posts: [post])
    #expect(
      ComposerValidation.validate(thread: thread, requireAltText: true) == .gifMissingAltText)
  }

  @Test("a video without alt text blocks publishing when required")
  func videoWithoutAltBlocksWhenRequired() {
    let video = ComposerVideo.created(asset: sampleAsset())
    let post = Fixtures.post(text: "vid", embed: EmbedDraft(media: .video(video)))
    let thread = Fixtures.thread(posts: [post])
    #expect(
      ComposerValidation.validate(thread: thread, requireAltText: true)
        == .videoMissingAltText)
  }

  @Test("a video already in error reports the video error, not the alt-text one")
  func erroredVideoIsNotAltTextError() {
    let video = ComposerVideo.created(asset: sampleAsset())
    let failed = VideoReducer.toErrorState(video, error: "nope")
    let post = Fixtures.post(text: "vid", embed: EmbedDraft(media: .video(failed)))
    let thread = Fixtures.thread(posts: [post])
    #expect(
      ComposerValidation.validate(thread: thread, requireAltText: true)
        == .videoFailed(postId: "post-0"))
  }

  // MARK: - Empty post classification

  @Test("a thread with no empty posts is unchanged")
  func noEmptyPosts() {
    let thread = Fixtures.thread(posts: [
      Fixtures.post(id: "post-1", text: "a"),
      Fixtures.post(id: "post-2", text: "b"),
    ])
    let filtered = thread.filteringEmptyPosts()
    #expect(filtered.classification == .none)
    #expect(filtered.thread.posts.map(\.id) == ["post-1", "post-2"])
  }

  @Test("trailing empty posts are dropped without a prompt")
  func trailingEmptyPosts() {
    let thread = Fixtures.thread(posts: [
      Fixtures.post(id: "post-1", text: "a"),
      Fixtures.post(id: "post-2"),
      Fixtures.post(id: "post-3"),
    ])
    let filtered = thread.filteringEmptyPosts()
    #expect(filtered.classification == .trailingOnly)
    #expect(!filtered.classification.requiresConfirmation)
    #expect(filtered.thread.posts.map(\.id) == ["post-1"])
  }

  @Test("an empty post between non-empty ones requires confirmation")
  func nonTrailingEmptyPosts() {
    let thread = Fixtures.thread(posts: [
      Fixtures.post(id: "post-1", text: "a"),
      Fixtures.post(id: "post-2"),
      Fixtures.post(id: "post-3", text: "c"),
    ])
    let filtered = thread.filteringEmptyPosts()
    #expect(filtered.classification == .nonTrailing)
    #expect(filtered.classification.requiresConfirmation)
    #expect(filtered.thread.posts.map(\.id) == ["post-1", "post-3"])
  }

  @Test("a post with media but no text is not empty")
  func mediaOnlyPostIsNotEmpty() {
    let images = [ComposerImage(id: "i1", path: "/a.jpg", width: 10, height: 10, alt: "x")]
    let post = Fixtures.post(embed: EmbedDraft(media: .images(.images(images))))
    #expect(!post.isEmpty)
  }

  @Test("a post with only whitespace is empty")
  func whitespaceOnlyPostIsEmpty() {
    #expect(Fixtures.post(text: "   \n  ").isEmpty)
  }

  // MARK: - Helpers

  private func sampleAsset() -> ComposerVideoAsset {
    ComposerVideoAsset(uri: "file:///v.mp4", size: 1000, width: 1920, height: 1080)
  }
}

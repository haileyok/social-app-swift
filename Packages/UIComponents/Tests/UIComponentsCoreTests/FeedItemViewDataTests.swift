import Foundation
import Moderation
import RichText
import Testing

@testable import UIComponentsCore

@Suite("Feed item view data")
struct FeedItemViewDataTests {
  /// A fixed instant so relative-time assertions are deterministic.
  private let now = ISO8601DateFormatter().date(from: "2026-09-14T12:00:00Z")!

  private func post(
    text: String = "hello",
    displayName: String? = "Alice",
    handle: String = "alice.bsky.social",
    avatar: String? = nil,
    indexedAt: String? = "2026-09-14T10:00:00.000Z",
    embed: PostViewEmbed? = nil,
    facets: [RichTextFacet]? = nil
  ) -> PostView {
    PostView(
      uri: "at://did:plc:x/app.bsky.feed.post/1",
      author: ProfileViewBasic(
        did: "did:plc:x", handle: handle, displayName: displayName, avatar: avatar),
      record: FeedPostRecord(text: text, facets: facets),
      embed: embed,
      indexedAt: indexedAt)
  }

  @Test("The author line falls back to the handle when there is no display name")
  func displayNameFallback() {
    let data = feedItemViewData(
      post(displayName: nil), options: FeedItemRenderOptions(now: now))
    #expect(data.displayName == "@alice.bsky.social")
    #expect(data.handle == "@alice.bsky.social")

    let blank = feedItemViewData(
      post(displayName: "   "), options: FeedItemRenderOptions(now: now))
    #expect(blank.displayName == "@alice.bsky.social")

    let named = feedItemViewData(post(), options: FeedItemRenderOptions(now: now))
    #expect(named.displayName == "Alice")
  }

  @Test("Relative time is derived from indexedAt")
  func relativeTime() {
    let twoHours = feedItemViewData(
      post(indexedAt: "2026-09-14T10:00:00.000Z"), options: FeedItemRenderOptions(now: now))
    #expect(twoHours.relativeTime == "2h")

    let fiveMinutes = feedItemViewData(
      post(indexedAt: "2026-09-14T11:55:00.000Z"), options: FeedItemRenderOptions(now: now))
    #expect(fiveMinutes.relativeTime == "5m")
  }

  @Test("An unparseable or missing timestamp yields no label")
  func badTimestamp() {
    let missing = feedItemViewData(post(indexedAt: nil), options: FeedItemRenderOptions(now: now))
    #expect(missing.relativeTime.isEmpty)
    let garbage = feedItemViewData(
      post(indexedAt: "not-a-date"), options: FeedItemRenderOptions(now: now))
    #expect(garbage.relativeTime.isEmpty)
  }

  @Test("Both ISO-8601 spellings parse")
  func timestampSpellings() {
    #expect(parseIndexedAt("2026-09-14T10:00:00.000Z") != nil)
    #expect(parseIndexedAt("2026-09-14T10:00:00Z") != nil)
    #expect(parseIndexedAt("2026-09-14") == nil)
  }

  @Test("Counts are formatted, and zero or missing counts are hidden")
  func counts() {
    let data = feedItemViewData(
      post(),
      counts: FeedItemCounts(replyCount: 12, repostCount: 2500, likeCount: 1_234_567),
      options: FeedItemRenderOptions(now: now))
    #expect(data.replyCount == "12")
    #expect(data.repostCount == "2.5K")
    #expect(data.likeCount == "1.2M")
  }

  @Test("A zero count renders as no label, matching the RN control")
  func zeroCount() {
    #expect(formatOptionalCount(0) == nil)
    #expect(formatOptionalCount(nil) == nil)
    #expect(formatOptionalCount(1) == "1")
  }

  @Test("A post without counts leaves the engagement row empty")
  func noCounts() {
    let data = feedItemViewData(post(), options: FeedItemRenderOptions(now: now))
    #expect(data.replyCount == nil)
    #expect(data.repostCount == nil)
    #expect(data.likeCount == nil)
  }

  @Test("The body is split into segments")
  func segments() {
    let facets = [RichTextFixtures.tag("hello", byteStart: 0, byteEnd: 5)].compactMap { $0 }
    let data = feedItemViewData(
      post(text: "hello world", facets: facets), options: FeedItemRenderOptions(now: now))
    #expect(data.text == "hello world")
    #expect(data.segments.count >= 2)
    #expect(data.segments.first?.tag == "hello")
  }

  @Test("A post with no record renders an empty body rather than crashing")
  func noRecord() {
    let bare = PostView(uri: "at://x", author: ProfileViewBasic(did: "d", handle: "h"))
    let data = feedItemViewData(bare, options: FeedItemRenderOptions(now: now))
    #expect(data.text.isEmpty)
    #expect(data.embed == nil)
    #expect(data.avatar == .placeholder("h"))
  }

  @Test("The context line comes from the options")
  func contextLine() {
    let data = feedItemViewData(
      post(), options: FeedItemRenderOptions(now: now, contextLine: "Reposted by Bob"))
    #expect(data.contextLine == "Reposted by Bob")
  }

  @Test("The embed info is derived from the post's embed")
  func embedInfo() {
    let data = feedItemViewData(
      post(embed: .images([EmbedImage(alt: "a"), EmbedImage(alt: "b")])),
      options: FeedItemRenderOptions(now: now))
    #expect(data.embed?.variant == .images)
    #expect(data.embed?.imageCount == 2)
  }

  @Test("The avatar falls back to initials when there is no URL")
  func avatarFallback() {
    let named = AvatarSource.resolve(avatar: nil, handle: "alice.bsky.social", displayName: "Alice")
    #expect(named == .placeholder("Alice"))
    #expect(avatarInitials("Alice") == "A")

    let anonymous = AvatarSource.resolve(avatar: nil, handle: "alice.bsky.social", displayName: nil)
    #expect(anonymous == .placeholder("alice.bsky.social"))
    #expect(avatarInitials("alice.bsky.social") == "A")

    let empty = AvatarSource.resolve(avatar: "", handle: "h", displayName: "Bob")
    #expect(empty == .placeholder("Bob"))
    #expect(avatarInitials("") == "?")

    let remote = AvatarSource.resolve(
      avatar: "https://cdn.example/a.jpg", handle: "h", displayName: nil)
    #expect(remote == .remote(URL(string: "https://cdn.example/a.jpg")!))
  }

  @Test("A moderation decision is projected onto the view data")
  func moderationProjection() {
    var decision = ModerationDecision()
    decision.causes = [
      ModerationCause(
        type: .hidden, source: .user, priority: 1, downgraded: false)
    ]
    let data = feedItemViewData(post(), decision: decision)
    // The engine's `hidden` cause both filters and blurs a content-list surface;
    // the hider prefers the blur (it is the more informative affordance), and
    // the media surface stays untouched.
    guard case .blur(_, let allowOverride) = data.moderation.content else {
      Issue.record("a hidden post should blur in a content list")
      return
    }
    #expect(allowOverride)
    #expect(data.moderation.media == .none)
    #expect(data.moderation.avatar == .none)
  }
}

@Suite("Image loading plumbing")
struct ImageLoadingTests {
  @Test("A nil target size yields a zero pixel key")
  func keyWithoutSize() {
    let key = ImageCacheKey(url: URL(string: "https://example.com/a.jpg")!, targetSize: nil)
    #expect(key.pixelWidth == 0)
    #expect(key.pixelHeight == 0)
  }

  @Test("Equivalent sizes round to the same key")
  func keyRounding() {
    let url = URL(string: "https://example.com/a.jpg")!
    let a = ImageCacheKey(url: url, targetSize: ImageTargetSize(width: 40, height: 40, scale: 2))
    let b = ImageCacheKey(url: url, targetSize: ImageTargetSize(width: 40.1, height: 40.1, scale: 2))
    #expect(a == b)
    #expect(a.pixelWidth == 80)
    #expect(a.pixelHeight == 80)
  }

  @Test("The phase reports when a placeholder is showing")
  func phases() {
    #expect(ImageLoadPhase.idle.isPlaceholder)
    #expect(ImageLoadPhase.loading.isPlaceholder)
    #expect(ImageLoadPhase.failed.isPlaceholder)
    #expect(ImageLoadPhase.loaded.isPlaceholder == false)
  }

  @Test("The avatar size ladder is ascending")
  func avatarSizes() {
    let sides = AvatarSize.allCases.map(\.side)
    #expect(sides == sides.sorted())
    #expect(AvatarSize.md.side == 40)
  }

  @Test("The placeholder loader refuses every request")
  func placeholderLoader() async {
    let loader = PlaceholderImageLoader()
    await #expect(throws: ImageLoaderError.placeholderOnly) {
      _ = try await loader.loadImage(at: URL(string: "https://example.com/a.jpg")!, targetSize: nil)
    }
  }
}

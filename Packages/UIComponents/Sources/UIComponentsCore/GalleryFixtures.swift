import Foundation
import Moderation

/// Sample data for the gallery, previews and tests.
///
/// Pure: it builds the same ``PostView`` shape the moderation engine consumes,
/// so the gallery exercises the real render path. Hydrated embeds go through
/// ``EmbedFixtures``, because the engine's view types decode-only.
public enum GalleryFixtures {
  /// A profile view with an optional avatar and display name.
  public static func profile(
    handle: String,
    displayName: String?,
    avatar: String? = nil,
    did: String = "did:plc:fixture"
  ) -> ProfileViewBasic {
    ProfileViewBasic(did: did, handle: handle, displayName: displayName, avatar: avatar)
  }

  /// A post with plain text.
  public static func post(
    _ text: String,
    author: ProfileViewBasic = GalleryFixtures.profile(
      handle: "alice.bsky.social", displayName: "Alice"),
    embed: PostViewEmbed? = nil,
    facets: [RichTextFacet]? = nil,
    indexedAt: String? = "2026-09-14T12:00:00.000Z"
  ) -> PostView {
    PostView(
      uri: "at://did:plc:fixture/app.bsky.feed.post/1",
      author: author,
      record: FeedPostRecord(text: text, facets: facets),
      embed: embed,
      indexedAt: indexedAt)
  }

  /// An images embed with `count` images that carry placeholder URLs.
  public static func images(_ count: Int) -> PostViewEmbed {
    .images(EmbedFixtures.images(count))
  }

  /// An external link card.
  public static let external = PostViewEmbed.external(
    EmbedExternal(
      uri: "https://bsky.social/about",
      title: "Bluesky",
      description: "Social media as it should be. Find your community among millions of users."))

  /// A quoted post.
  public static func quote(text: String = "The quoted post body.") -> PostViewEmbed? {
    EmbedFixtures.quote(text: text)
  }

  /// A quoted post with an images embed.
  public static func recordWithMedia(imageCount: Int = 1) -> PostViewEmbed? {
    EmbedFixtures.recordWithMedia(imageCount: imageCount)
  }

  /// A blocked quote.
  public static var blockedQuote: PostViewEmbed? { EmbedFixtures.blockedQuote() }

  /// A not-found quote.
  public static var notFoundQuote: PostViewEmbed? { EmbedFixtures.notFoundQuote() }

  /// One of each moderation outcome, for the gallery's moderation section.
  public static func moderatedSurfaces() -> [(String, ModerationSurface)] {
    var blurDecision = ModerationDecision()
    blurDecision.causes = [ModerationCause(type: .hidden, source: .user, priority: 1)]

    var noOverrideDecision = ModerationDecision()
    noOverrideDecision.causes = [ModerationCause(type: .blockedBy, source: .user, priority: 1)]

    var mediaBlurDecision = ModerationDecision()
    let definition = LabelValueDefinition(
      identifier: "graphic-media",
      severity: .none,
      blurs: .media,
      defaultSetting: .warn,
      flags: [],
      behaviors: LabelTargetBehaviors(
        content: ModerationBehavior(contentList: .blur, contentView: .blur, contentMedia: .blur)),
      definedBy: "did:plc:labeler")
    mediaBlurDecision.causes = [
      ModerationCause(
        type: .label, source: .labeler(did: "did:plc:labeler"), priority: 1,
        labelDef: definition, target: LabelTarget.content,
        behavior: definition.behaviors[LabelTarget.content])
    ]

    return [
      ("None", .none),
      ("Blur, revealable", moderationSurface(blurDecision.ui(.contentList))),
      ("Filter, hidden", .filter(ModerationCauseDescription.contentWarning)),
      ("Blur, no override", moderationSurface(noOverrideDecision.ui(.contentList))),
      ("Media-only blur", moderationSurface(mediaBlurDecision.ui(.contentMedia))),
    ]
  }

  /// A fixed instant the gallery's relative timestamps are measured against, so
  /// the demo does not drift with the clock.
  public static let galleryNow = ISO8601DateFormatter().date(from: "2026-09-14T12:00:00Z")!
}

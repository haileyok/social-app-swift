import Lexicons
import Moderation
import SwiftAtproto

/**
 Bridges generated lexicon values onto the Moderation engine's stand-in shapes.

 `Moderation` is deliberately self-contained - it declares its own `PostView`,
 `ProfileViewBasic` and `FeedPostRecord` so it can be verified on Linux without
 the generated lexicon package. `UIComponents` then builds its view data from
 those engine shapes (``FeedItemViewData``). Something has to cross the seam, and
 it belongs here rather than in either package, because the dependency edge only
 ever runs one way.

 RN calls `moderatePost(postView, opts)` directly on the atproto `PostView`; this
 adapter forwards every field the engine reads.

 The engine's `EmbedRecordView` / `EmbedRecordWithMediaView` / `EmbedViewRecord`
 declare no public initializer, so the quoted-post variants are bridged by
 encoding the generated view to JSON and decoding it into the engine's type -
 the same wire-shape trick `NotificationsLogic` uses for rich-text facets. The
 flat media variants (images, gallery, external) are constructed field by field
 so their image URLs survive; the nested-media case inside `recordWithMedia`
 keeps the JSON path and therefore loses image URLs.
 */
public enum LexiconModeration {
  /// The engine's subject type for a lexicon post view.
  public static func subject(_ post: App.Bsky.FeedDefs_PostView) -> Moderation.PostView {
    Moderation.PostView(
      type: "app.bsky.feed.defs#postView",
      uri: post.uri.rawValue,
      cid: post.cid.rawValue,
      author: author(post.author),
      record: record(post.record),
      embed: postViewEmbed(post.embed),
      labels: post.labels?.map(label),
      indexedAt: post.indexedAt.rawValue)
  }

  /// Runs the engine over a post view.
  public static func moderate(
    _ post: App.Bsky.FeedDefs_PostView, opts: ModerationOpts
  ) -> ModerationDecision {
    moderatePost(subject(post), opts: opts)
  }

  static func author(
    _ author: App.Bsky.ActorDefs_ProfileViewBasic
  ) -> Moderation.ProfileViewBasic {
    Moderation.ProfileViewBasic(
      did: author.did.rawValue,
      handle: author.handle.rawValue,
      displayName: author.displayName,
      avatar: author.avatar?.rawValue,
      viewer: nil,
      labels: author.labels?.map(label))
  }

  static func label(_ label: Com.Atproto.LabelDefs_Label) -> Moderation.Label {
    Moderation.Label(
      ver: label.ver,
      src: label.src.rawValue,
      uri: label.uri.rawValue,
      cid: label.cid?.rawValue,
      val: label.val,
      neg: label.neg,
      cts: label.cts.rawValue)
  }

  /// The record fields the engine reads. `nil` for a non-post record.
  static func record(_ value: UnknownATPValue) -> Moderation.FeedPostRecord? {
    guard case .record(let record) = value, let post = record as? App.Bsky.FeedPost else {
      return nil
    }
    return Moderation.FeedPostRecord(
      text: post.text,
      // Facets are only read for tag matching, and this app matches muted words
      // against the record text path, so the byte-indexed facets are dropped
      // here exactly as `PostThreadLogic.PostModerationAdapter` does.
      facets: nil,
      tags: post.tags,
      langs: post.langs?.map(\.rawValue),
      embed: nil)
  }

  // MARK: - Embeds

  /// The engine's embed union for a lexicon post-view embed.
  ///
  /// Returns `nil` for a video embed. The engine's union has no video case, so a
  /// video is mapped to ``Moderation/PostViewEmbed/unknown(type:)`` with the
  /// video view's type - which is what makes ``UIComponentsCore/embedVariantInfo``
  /// report it as unsupported and `PostEmbed` draw its labelled placeholder.
  public static func postViewEmbed(
    _ embed: App.Bsky.FeedDefs_PostView_Embed?
  ) -> Moderation.PostViewEmbed? {
    guard let embed else { return nil }
    switch embed {
    case .embedImagesView(let view):
      return .images(view.images.map(image))
    case .embedGalleryView(let view):
      return .gallery(view.items.map(galleryItem))
    case .embedExternalView(let view):
      return .external(
        Moderation.EmbedExternal(
          uri: view.external.uri.rawValue,
          title: view.external.title,
          description: view.external.description))
    case .embedVideoView:
      return .unknown(type: "app.bsky.embed.video#view")
    case .embedRecordView(let view):
      guard let decoded: Moderation.EmbedRecordView = decode(view) else {
        return .unknown(type: "app.bsky.embed.record#view")
      }
      return .record(decoded)
    case .embedRecordWithMediaView(let view):
      guard let decoded: Moderation.EmbedRecordWithMediaView = decode(view) else {
        return .unknown(type: "app.bsky.embed.recordWithMedia#view")
      }
      return .recordWithMedia(decoded)
    case ._other(let record):
      // `UnknownRecord.type` is the wire `$type`; its static `nsId` is the
      // literal "unknown" and would lose the variant.
      return .unknown(type: record.type)
    }
  }

  /// The engine's image shape. The engine reads `image`, and the generated view
  /// names its render URL `thumb`, so the thumbnail is forwarded.
  static func image(_ image: App.Bsky.EmbedImages_ViewImage) -> Moderation.EmbedImage {
    Moderation.EmbedImage(alt: image.alt, image: image.thumb.rawValue)
  }

  /// The engine's gallery item, restricted to the image case.
  static func galleryItem(
    _ item: App.Bsky.EmbedGallery_View_Items_Elem
  ) -> Moderation.EmbedGalleryItem {
    switch item {
    case .embedGalleryViewImage(let image):
      return .image(
        Moderation.EmbedImage(alt: image.alt, image: image.thumbnail.rawValue))
    case ._other:
      return .unknown(type: "app.bsky.embed.gallery#viewImage")
    }
  }

  /// Wire-shape bridge for the engine types that have no public initializer.
  static func decode<T: Decodable>(_ value: some Encodable) -> T? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }
}

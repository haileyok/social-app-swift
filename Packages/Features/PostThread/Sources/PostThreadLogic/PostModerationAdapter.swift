import Foundation
import Lexicons
import Moderation

/// Bridges a lexicon `#postView` into the Moderation engine's subject type.
///
/// The Moderation package is deliberately self-contained (it does not depend on
/// Lexicons), so it carries its own `PostView`/`FeedPostRecord` shapes. This
/// adapter is the seam between the two, and it lives here rather than in
/// Moderation because the dependency edge only ever runs one way.
///
/// RN calls `moderatePost(node.post, moderationOpts)` directly on the atproto
/// `PostView`; every field the engine reads is forwarded.
public enum PostModerationAdapter {
  /// The Moderation-engine subject for a lexicon post view.
  public static func subject(_ post: App.Bsky.FeedDefs_PostView) -> Moderation.PostView {
    Moderation.PostView(
      uri: post.uri.rawValue,
      cid: post.cid.rawValue,
      author: author(post.author),
      record: record(post.record),
      embed: postViewEmbed(post.embed),
      labels: post.labels?.map(label),
      indexedAt: post.indexedAt.rawValue
    )
  }

  /// Bridges every hydrated post-view embed into the render/moderation union.
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
      return .record(recordView(view))
    case .embedRecordWithMediaView(let view):
      guard let decoded: Moderation.EmbedRecordWithMediaView = decode(view) else {
        return .unknown(type: "app.bsky.embed.recordWithMedia#view")
      }
      return .recordWithMedia(decoded)
    case ._other(let record):
      return .unknown(type: record.type)
    }
  }

  static func recordView(_ view: App.Bsky.EmbedRecord_View) -> Moderation.EmbedRecordView {
    let bridgedRecord: Moderation.EmbedRecordViewUnion
    switch view.record {
    case .embedRecordViewRecord(let quoted):
      bridgedRecord = .viewRecord(
        Moderation.EmbedViewRecord(
          uri: quoted.uri.rawValue,
          cid: quoted.cid.rawValue,
          author: author(quoted.author),
          value: record(quoted.value),
          labels: quoted.labels?.map(label),
          indexedAt: quoted.indexedAt.rawValue))
    case .embedRecordViewBlocked(let blocked):
      bridgedRecord = .viewBlocked(
        Moderation.EmbedViewBlocked(
          uri: blocked.uri.rawValue,
          blocked: blocked.blocked,
          author: nil))
    case .embedRecordViewNotFound, .embedRecordViewDetached:
      bridgedRecord = .viewNotFound
    case .feedDefsGeneratorView:
      bridgedRecord = .unknown(type: "app.bsky.feed.defs#generatorView")
    case .graphDefsListView:
      bridgedRecord = .unknown(type: "app.bsky.graph.defs#listView")
    case .labelerDefsLabelerView:
      bridgedRecord = .unknown(type: "app.bsky.labeler.defs#labelerView")
    case .graphDefsStarterPackViewBasic:
      bridgedRecord = .unknown(type: "app.bsky.graph.defs#starterPackViewBasic")
    case ._other(let unknown):
      bridgedRecord = .unknown(type: unknown.type)
    }
    return Moderation.EmbedRecordView(record: bridgedRecord)
  }

  static func image(_ image: App.Bsky.EmbedImages_ViewImage) -> Moderation.EmbedImage {
    Moderation.EmbedImage(alt: image.alt, image: image.thumb.rawValue)
  }

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

  static func decode<T: Decodable>(_ value: some Encodable) -> T? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }

  /// Runs the engine over a post view.
  public static func moderate(
    _ post: App.Bsky.FeedDefs_PostView,
    opts: ModerationOpts
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
      labels: author.labels?.map(label)
    )
  }

  static func label(_ label: Com.Atproto.LabelDefs_Label) -> Moderation.Label {
    Moderation.Label(
      ver: label.ver,
      src: label.src.rawValue,
      uri: label.uri.rawValue,
      cid: label.cid?.rawValue,
      val: label.val,
      neg: label.neg,
      cts: label.cts.rawValue
    )
  }

  /// The record fields the engine reads. Returns `nil` for a non-post record,
  /// which is how the engine treats a post it cannot reason about.
  static func record(_ value: UnknownATPValue) -> Moderation.FeedPostRecord? {
    guard let post = value.postRecord else { return nil }
    return Moderation.FeedPostRecord(
      text: post.text,
      // Facets are only read for tag matching; muted-word tag matching is
      // handled by the record text path.
      facets: nil,
      tags: post.tags,
      langs: post.langs?.map(\.rawValue),
      embed: nil
    )
  }
}

extension UnknownATPValue {
  /// The `app.bsky.feed.post` record, when this value is one.
  public var postRecord: App.Bsky.FeedPost? {
    guard case .record(let record) = self else { return nil }
    return record as? App.Bsky.FeedPost
  }
}

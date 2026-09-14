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
      // Embeds are not bridged yet: the engine only reads them for
      // record-with-media label checks, which the thread screen does not
      // surface. Add the bridge when a caller needs it.
      embed: nil,
      labels: post.labels?.map(label),
      indexedAt: post.indexedAt.rawValue
    )
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

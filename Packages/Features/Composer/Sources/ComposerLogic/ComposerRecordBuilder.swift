import ATProtoClient
import Domain
import Foundation
import Lexicons
import RichText
import SwiftAtproto

/// A strong reference to a record, which is what reply refs and quote embeds are.
public struct RecordReference: Hashable, Sendable {
  public var uri: String
  public var cid: String

  public init(uri: String, cid: String) {
    self.uri = uri
    self.cid = cid
  }

  /// The lexicon shape.
  public var strongRef: Com.Atproto.RepoStrongRef {
    Com.Atproto.RepoStrongRef(
      cid: FormatString<LexLink>(rawValue: cid),
      uri: FormatString<ATURI>(rawValue: uri))
  }
}

/// The reply context a post is published into.
///
/// The composer resolves this before publishing: `parent` is the post being
/// replied to and `root` is the thread root (which equals `parent` when the
/// target is itself a root).
public struct ReplyContext: Hashable, Sendable {
  public var root: RecordReference
  public var parent: RecordReference

  public init(root: RecordReference, parent: RecordReference) {
    self.root = root
    self.parent = parent
  }

  /// The lexicon shape.
  public var replyRef: App.Bsky.FeedPost_ReplyRef {
    App.Bsky.FeedPost_ReplyRef(parent: parent.strongRef, root: root.strongRef)
  }
}

/// Resolved media, ready to be written into a record.
///
/// The composer state holds local files and job ids; by publish time every blob
/// has been uploaded and every image compressed, so the record builder deals
/// only in blobs and dimensions. This split mirrors RN, where `resolveMedia`
/// uploads and then the record is assembled from the results.
public enum ResolvedEmbedMedia: Hashable, Sendable {
  /// `app.bsky.embed.images` - legacy, up to four images.
  case images([ResolvedImage])
  /// `app.bsky.embed.gallery` - more than four images.
  case gallery([ResolvedImage])
  /// `app.bsky.embed.video` - a completed video job.
  case video(ResolvedVideo)
  /// `app.bsky.embed.external` - a resolved link card or GIF.
  case external(ResolvedExternal)

  /// The lexicon shape.
  public var embedValue: App.Bsky.FeedPost_Embed {
    switch self {
    case .images(let images):
      .embedImages(
        App.Bsky.EmbedImages(
          images: images.map {
            App.Bsky.EmbedImages_Image(
              alt: $0.alt, aspectRatio: $0.aspectRatio, image: $0.blob)
          }))
    case .gallery(let images):
      .embedGallery(
        App.Bsky.EmbedGallery(
          items: images.map {
            .embedGalleryImage(
              App.Bsky.EmbedGallery_Image(
                alt: $0.alt, aspectRatio: $0.aspectRatioOrUnit, image: $0.blob))
          }))
    case .video(let video):
      .embedVideo(
        App.Bsky.EmbedVideo(
          alt: video.alt, aspectRatio: video.aspectRatio, captions: video.captions,
          presentation: video.presentation, video: video.blob))
    case .external(let external):
      .embedExternal(
        App.Bsky.EmbedExternal(
          external: App.Bsky.EmbedExternal_External(
            associatedRefs: external.associatedRefs,
            description: external.description,
            thumb: external.thumb,
            title: external.title,
            uri: FormatString<URI>(rawValue: external.uri))))
    }
  }
}

/// An uploaded image with its alt text and dimensions.
public struct ResolvedImage: Hashable, Sendable {
  public var blob: LexBlob
  public var alt: String
  public var aspectRatio: App.Bsky.EmbedDefs_AspectRatio?

  public init(blob: LexBlob, alt: String, width: Double, height: Double) {
    self.blob = blob
    self.alt = alt
    self.aspectRatio = Self.aspectRatio(width: width, height: height)
  }

  /// The aspect ratio with a unit fallback.
  ///
  /// `app.bsky.embed.gallery#image` declares `aspectRatio` as **required** and
  /// constrained to `>= 1`, unlike `app.bsky.embed.images#image` where it is
  /// optional. When the picked image's dimensions are unknown (0), the optional
  /// value is `nil` and this substitutes 1:1, which validates while being
  /// visually neutral for an image whose real shape is unknown.
  public var aspectRatioOrUnit: App.Bsky.EmbedDefs_AspectRatio {
    aspectRatio ?? App.Bsky.EmbedDefs_AspectRatio(height: 1, width: 1)
  }

  /// Rounds to integers and omits the ratio when either dimension is unusable.
  ///
  /// Ported from `resolveMedia`'s video branch, which notes that "aspect ratio
  /// values must be >0 - better to leave as unset otherwise; posting will fail
  /// if aspect ratio is set to 0". The same rule is applied to images here
  /// because the lexicon constraint is identical.
  static func aspectRatio(width: Double, height: Double) -> App.Bsky.EmbedDefs_AspectRatio? {
    let w = Int(width.rounded())
    let h = Int(height.rounded())
    guard w > 0, h > 0 else { return nil }
    return App.Bsky.EmbedDefs_AspectRatio(height: h, width: w)
  }
}

/// An uploaded video with its alt text, captions and aspect ratio.
public struct ResolvedVideo: Hashable, Sendable {
  public var blob: LexBlob
  public var alt: String
  public var captions: [App.Bsky.EmbedVideo_Caption]?
  public var aspectRatio: App.Bsky.EmbedDefs_AspectRatio?
  public var presentation: App.Bsky.EmbedVideo_Presentation

  public init(
    blob: LexBlob,
    alt: String,
    captions: [App.Bsky.EmbedVideo_Caption]?,
    width: Double,
    height: Double,
    mimeType: String
  ) {
    self.blob = blob
    self.alt = alt
    self.captions = captions
    self.aspectRatio = ResolvedImage.aspectRatio(width: width, height: height)
    // `image/gif` renders as an animated GIF; everything else is a normal video.
    self.presentation = mimeType == "image/gif" ? .gif : .`default`
  }
}

/// A resolved link card or GIF external embed.
public struct ResolvedExternal: Hashable, Sendable {
  public var uri: String
  public var title: String
  public var description: String
  public var thumb: LexBlob?
  public var associatedRefs: [Com.Atproto.RepoStrongRef]?

  public init(
    uri: String,
    title: String,
    description: String,
    thumb: LexBlob? = nil,
    associatedRefs: [Com.Atproto.RepoStrongRef]? = nil
  ) {
    self.uri = uri
    self.title = title
    self.description = description
    self.thumb = thumb
    self.associatedRefs = associatedRefs
  }
}

/// A built post record plus the writes that must accompany it.
///
/// The composer publishes a thread as a single `applyWrites` batch; a threadgate
/// accompanies the first post and a postgate accompanies every post that has
/// embedding rules or detached URIs.
public struct BuiltPostRecord: Sendable {
  /// The post record.
  public let record: App.Bsky.FeedPost
  /// The collection, always `app.bsky.feed.post`.
  public let collection: String
  /// The record key.
  public let rkey: String
  /// The AT-URI the record will live at.
  public let uri: String
  /// The threadgate create write, present only on the first post of a thread
  /// whose reply permissions are anything other than "everybody".
  public let threadgate: App.Bsky.FeedThreadgate?
  /// The postgate create write, present only when the thread's postgate has
  /// rules or detached URIs.
  public let postgate: App.Bsky.FeedPostgate?
}

/// One write in the `applyWrites` batch.
public enum ComposerWrite: Sendable {
  case create(collection: String, rkey: String, value: App.Bsky.FeedPost)
  case createThreadgate(collection: String, rkey: String, value: App.Bsky.FeedThreadgate)
  case createPostgate(collection: String, rkey: String, value: App.Bsky.FeedPostgate)
}

/// The resolved inputs the record builder needs for one post.
///
/// The composer collects these from its state and from the network (blob
/// uploads, link resolution, mention resolution) before calling
/// ``ComposerRecordBuilder``, which is then pure.
public struct PublishInputs: Sendable {
  /// The thread to publish, with empty posts already dropped.
  public var thread: ThreadDraft
  /// The language codes to attach (already capped at three).
  public var langs: [String]
  /// The reply context, when this is a reply.
  public var reply: ReplyContext?
  /// Resolved embeds per post id. A post with no entry publishes without an embed.
  public var media: [String: ResolvedEmbedMedia]
  /// Resolved link cards per post id (used when the post has no media).
  public var linkCards: [String: ResolvedExternal]
  /// Resolved quote references per post id, required for any post with a quote.
  public var quoteReferences: [String: RecordReference]?
  /// Per-post record keys. The caller allocates these so the publish order and
  /// the `createdAt` increments stay under its control.
  public var rkeys: [String: String]
  /// The repo DID the records are written to.
  public var did: String
  /// The instant the first post is stamped with; each subsequent post is one
  /// millisecond later, because the sort order of posts sharing a `createdAt`
  /// is undefined.
  public var createdAt: Date

  public init(
    thread: ThreadDraft,
    langs: [String] = [],
    reply: ReplyContext? = nil,
    media: [String: ResolvedEmbedMedia] = [:],
    linkCards: [String: ResolvedExternal] = [:],
    quoteReferences: [String: RecordReference]? = nil,
    rkeys: [String: String],
    did: String,
    createdAt: Date = Date()
  ) {
    self.thread = thread
    self.langs = langs
    self.reply = reply
    self.media = media
    self.linkCards = linkCards
    self.quoteReferences = quoteReferences
    self.rkeys = rkeys
    self.did = did
    self.createdAt = createdAt
  }
}

/// Assembles post records and their gate records.
///
/// Ported from `post()` in `lib/api/index.ts`. The ordering rules that matter:
///
/// 1. **Embed precedence.** A quote plus media becomes
///    `app.bsky.embed.recordWithMedia`; a quote alone becomes
///    `app.bsky.embed.record`; media alone is its own embed; and only if there
///    is neither does a link card become `app.bsky.embed.external`.
/// 2. **Reply threading.** The first post replies to the resolved context; each
///    subsequent post replies to the previous post in the batch, with `root`
///    inherited from the first post's context (or the first post itself when the
///    thread is not a reply).
/// 3. **`createdAt` increments by 1 ms per post**, so ordering is stable.
/// 4. **Gates attach by index.** The threadgate goes with the first post only;
///    the postgate goes with every post whose gate has content.
public enum ComposerRecordBuilder {
  /// The post collection NSID.
  public static let postCollection = "app.bsky.feed.post"

  /// Builds every record for a thread.
  ///
  /// - Parameter cidProvider: computes the CID of a built record, which the next
  ///   post in the thread needs for its `reply.parent`. No DAG-CBOR encoder is
  ///   exposed by the ATProto stack today, so this is injected; see the package
  ///   notes on deviations.
  public static func build(
    _ inputs: PublishInputs,
    cidProvider: (App.Bsky.FeedPost) throws -> String
  ) throws -> [BuiltPostRecord] {
    var results: [BuiltPostRecord] = []
    var replyContext = inputs.reply
    var now = inputs.createdAt

    for (index, post) in inputs.thread.posts.enumerated() {
      guard let rkey = inputs.rkeys[post.id] else {
        throw ComposerBuildError.missingRKey(postId: post.id)
      }
      // The sort order of posts sharing a createdAt is undefined, so each post
      // is stamped one millisecond after the last.
      now = now.addingTimeInterval(0.001)

      let uri = "at://\(inputs.did)/\(postCollection)/\(rkey)"
      let record = postRecord(
        for: post, inputs: inputs, uri: uri, reply: replyContext, createdAt: now)

      results.append(
        BuiltPostRecord(
          record: record,
          collection: postCollection,
          rkey: rkey,
          uri: uri,
          threadgate: try threadgate(forPostAt: index, inputs: inputs, uri: uri, createdAt: now),
          postgate: try postgate(inputs: inputs, uri: uri, createdAt: now)))

      // Only another post in this batch needs this record's CID for its parent
      // reference. A single post/reply can publish without a local DAG-CBOR CID
      // implementation because the PDS computes its CID during createRecord.
      if index < inputs.thread.posts.count - 1 {
        let ref = RecordReference(uri: uri, cid: try cidProvider(record))
        replyContext = ReplyContext(root: replyContext?.root ?? ref, parent: ref)
      }
    }

    return results
  }

  /// Assembles one post record from its resolved inputs.
  static func postRecord(
    for post: PostDraft,
    inputs: PublishInputs,
    uri: String,
    reply: ReplyContext?,
    createdAt: Date
  ) -> App.Bsky.FeedPost {
    _ = uri
    let richText = ComposerText.publishRichText(post.richText)
    let labels = post.labels.recordValue
    return App.Bsky.FeedPost(
      createdAt: FormatString<Date>(rawValue: isoString(createdAt)),
      embed: embed(for: post, inputs: inputs),
      entities: nil,
      facets: facets(from: richText),
      labels: labels.map { App.Bsky.FeedPost_Labels.comAtprotoLabelDefsSelfLabels($0) },
      langs: inputs.langs.isEmpty
        ? nil : inputs.langs.map { FormatString<Language>(rawValue: $0) },
      reply: reply?.replyRef,
      tags: nil,
      text: richText.text)
  }

  /// The threadgate write for a post, present only on the first post of a
  /// thread whose permissions are anything but "everybody".
  static func threadgate(
    forPostAt index: Int,
    inputs: PublishInputs,
    uri: String,
    createdAt: Date
  ) throws -> App.Bsky.FeedThreadgate? {
    guard index == 0, !inputs.thread.threadgate.contains(.everybody) else { return nil }
    return try ComposerGates.createThreadgateRecord(
      post: uri,
      allow: ComposerGates.allowRecordValue(from: inputs.thread.threadgate),
      createdAt: createdAt)
  }

  /// The postgate write for a post, present only when the thread's postgate has
  /// embedding rules or detached URIs.
  static func postgate(
    inputs: PublishInputs,
    uri: String,
    createdAt: Date
  ) throws -> App.Bsky.FeedPostgate? {
    let rules = inputs.thread.postgate.embeddingRules ?? []
    let detached = inputs.thread.postgate.detachedEmbeddingUris ?? []
    guard !rules.isEmpty || !detached.isEmpty else { return nil }
    return try ComposerGates.createPostgateRecord(
      post: uri,
      embeddingRules: rules,
      detachedEmbeddingUris: detached.map(\.rawValue),
      createdAt: createdAt)
  }

  /// Flattens built records into the ordered `applyWrites` batch.
  ///
  /// Ported from the `writes.push` sequence in `post()`: the post, then its
  /// threadgate (first post only), then its postgate (when present), per post.
  public static func writes(from records: [BuiltPostRecord]) -> [ComposerWrite] {
    var writes: [ComposerWrite] = []
    for built in records {
      writes.append(.create(collection: built.collection, rkey: built.rkey, value: built.record))
      if let threadgate = built.threadgate {
        writes.append(
          .createThreadgate(
            collection: ComposerGates.threadgateCollection,
            rkey: built.rkey,
            value: threadgate))
      }
      if let postgate = built.postgate {
        writes.append(
          .createPostgate(
            collection: ComposerGates.postgateCollection,
            rkey: built.rkey,
            value: postgate))
      }
    }
    return writes
  }

  /// The embed for a post, applying the precedence rules.
  ///
  /// Ported from `resolveEmbed`.
  public static func embed(
    for post: PostDraft,
    inputs: PublishInputs
  ) -> App.Bsky.FeedPost_Embed? {
    let media = inputs.media[post.id]

    if post.embed.quote != nil {
      guard let quoteRef = inputs.quoteReferences?[post.id] else { return nil }
      let quoteEmbed = App.Bsky.EmbedRecord(record: quoteRef.strongRef)
      if let media {
        return .embedRecordWithMedia(
          App.Bsky.EmbedRecordWithMedia(media: mediaValue(media), record: quoteEmbed))
      }
      return .embedRecord(quoteEmbed)
    }

    if let media { return media.embedValue }
    if let card = inputs.linkCards[post.id] { return ResolvedEmbedMedia.external(card).embedValue }
    return nil
  }

  /// Wraps resolved media for the `recordWithMedia` slot.
  static func mediaValue(_ media: ResolvedEmbedMedia) -> App.Bsky.EmbedRecordWithMedia_Media {
    switch media {
    case .images(let images):
      .embedImages(
        App.Bsky.EmbedImages(
          images: images.map {
            App.Bsky.EmbedImages_Image(alt: $0.alt, aspectRatio: $0.aspectRatio, image: $0.blob)
          }))
    case .gallery(let images):
      .embedGallery(
        App.Bsky.EmbedGallery(
          items: images.map {
            .embedGalleryImage(
              App.Bsky.EmbedGallery_Image(
                alt: $0.alt, aspectRatio: $0.aspectRatioOrUnit, image: $0.blob))
          }))
    case .video(let video):
      .embedVideo(
        App.Bsky.EmbedVideo(
          alt: video.alt, aspectRatio: video.aspectRatio, captions: video.captions,
          presentation: video.presentation, video: video.blob))
    case .external(let external):
      .embedExternal(
        App.Bsky.EmbedExternal(
          external: App.Bsky.EmbedExternal_External(
            associatedRefs: external.associatedRefs,
            description: external.description,
            thumb: external.thumb,
            title: external.title,
            uri: FormatString<URI>(rawValue: external.uri))))
    }
  }

  /// Converts the RichText facets to lexicon facets.
  ///
  /// The RichText package's ``Facet``/``FacetFeature`` are structurally
  /// identical to the lexicon's; the conversion is explicit so a change in
  /// either stays a compile error here rather than a silent wire mismatch.
  /// Unresolved mentions (empty `did`) are dropped, matching
  /// `stripInvalidMentions` in the publish path.
  public static func facets(from richText: RichText) -> [App.Bsky.RichtextFacet]? {
    guard let facets = richText.facets, !facets.isEmpty else { return nil }
    let converted: [App.Bsky.RichtextFacet] = facets.compactMap { facet in
      let features: [App.Bsky.RichtextFacet_Features_Elem] = facet.features.compactMap { feature in
        switch feature {
        case .link(let uri):
          return .richtextFacetLink(.init(uri: FormatString<URI>(rawValue: uri)))
        case .mention(let did):
          guard !did.isEmpty else { return nil }
          return .richtextFacetMention(.init(did: FormatString<DID>(rawValue: did)))
        case .tag(let tag):
          return .richtextFacetTag(.init(tag: tag))
        }
      }
      guard !features.isEmpty else { return nil }
      return App.Bsky.RichtextFacet(
        features: features,
        index: App.Bsky.RichtextFacet_ByteSlice(
          byteEnd: facet.index.byteEnd, byteStart: facet.index.byteStart))
    }
    return converted.isEmpty ? nil : converted
  }
}

/// Failures the record builder can raise.
public enum ComposerBuildError: Error, Sendable, Equatable {
  /// A post has no record key. The caller must allocate one per post.
  case missingRKey(postId: String)
  /// A post has a quote that was not resolved to a strong ref.
  case unresolvedQuote(postId: String)
}

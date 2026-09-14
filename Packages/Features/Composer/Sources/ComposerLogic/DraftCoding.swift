import Domain
import Foundation
import Lexicons
import RichText
import SwiftAtproto

/// A media file the composer wants persisted alongside a server draft.
///
/// The server draft stores only a `localRef.path`; the bytes live on the device.
/// The storage layer is injected so this package stays free of a file-system
/// dependency.
public struct DraftMediaFile: Hashable, Sendable {
  /// The `localRef.path` written into the draft.
  public var localRefPath: String
  /// Where the bytes can be read from right now.
  public var sourcePath: String

  public init(localRefPath: String, sourcePath: String) {
    self.localRefPath = localRefPath
    self.sourcePath = sourcePath
  }
}

/// A converted server draft plus the local media it references.
public struct DraftConversion: Sendable {
  /// The lexicon draft.
  public var draft: App.Bsky.DraftDefs_Draft
  /// Local media the draft references, keyed by `localRef.path`.
  public var localRefPaths: [DraftMediaFile]

  public init(draft: App.Bsky.DraftDefs_Draft, localRefPaths: [DraftMediaFile]) {
    self.draft = draft
    self.localRefPaths = localRefPaths
  }
}

/// A video that a hydrated draft wants re-processed.
///
/// Videos cannot be restored synchronously the way images can: they must be
/// re-compressed and re-uploaded, so hydration hands them back to the caller.
public struct RestoredVideo: Hashable, Sendable {
  /// The local file to process.
  public var uri: String
  public var altText: String
  public var mimeType: String
  /// The `localRef.path` the draft stored, so a re-save reuses it.
  public var localRefPath: String
  /// Caption tracks read from the draft.
  public var captions: [VideoCaptionTrack]

  public init(
    uri: String,
    altText: String,
    mimeType: String,
    localRefPath: String,
    captions: [VideoCaptionTrack] = []
  ) {
    self.uri = uri
    self.altText = altText
    self.mimeType = mimeType
    self.localRefPath = localRefPath
    self.captions = captions
  }
}

/// How hydration should name and measure restored media.
///
/// The RN code reaches for `nanoid` and `getImageDim` directly; injecting them
/// keeps this package free of those dependencies and makes the restore
/// deterministic in tests.
public struct DraftHydrateOptions: Sendable {
  /// Supplies ids for restored images.
  public let imageIdGenerator: @Sendable () -> String
  /// Reports an image's dimensions, or `nil` when they cannot be read.
  public let imageDimensions: @Sendable (String) -> (width: Double, height: Double)?

  public init(
    imageIdGenerator: @escaping @Sendable () -> String = { UUID().uuidString },
    imageDimensions: @escaping @Sendable (String) -> (width: Double, height: Double)? = { _ in nil }
  ) {
    self.imageIdGenerator = imageIdGenerator
    self.imageDimensions = imageDimensions
  }
}

/// The result of hydrating a server draft back into composer posts.
public struct DraftHydration: Sendable {
  /// The posts, in order.
  public var posts: [PostDraft]
  /// Videos to re-process, keyed by post index.
  public var restoredVideos: [Int: RestoredVideo]
  /// The reply permissions restored from the draft.
  public var threadgateAllow: [App.Bsky.FeedThreadgate_Allow_Elem]?
  /// The embedding rules restored from the draft.
  public var postgateEmbeddingRules: [App.Bsky.FeedPostgate_EmbeddingRules_Elem]?
  /// Every `localRef.path` the draft references, for orphan cleanup.
  public var originalLocalRefs: Set<String>

  public init(
    posts: [PostDraft],
    restoredVideos: [Int: RestoredVideo] = [:],
    threadgateAllow: [App.Bsky.FeedThreadgate_Allow_Elem]? = nil,
    postgateEmbeddingRules: [App.Bsky.FeedPostgate_EmbeddingRules_Elem]? = nil,
    originalLocalRefs: Set<String> = []
  ) {
    self.posts = posts
    self.restoredVideos = restoredVideos
    self.threadgateAllow = threadgateAllow
    self.postgateEmbeddingRules = postgateEmbeddingRules
    self.originalLocalRefs = originalLocalRefs
  }
}

/// Converts between composer state and the server draft format.
///
/// Ported from `src/view/composer/composer/drafts/state/api.ts`.
///
/// Two RN behaviours are worth calling out because they look like bugs and are
/// not:
///
/// 1. **Images are always written to `embedGallery`, even the legacy <= 4 case.**
///    `embedImages` is still *read* for backwards compatibility with older
///    drafts, but never written. Hydration re-picks the variant from the restored
///    count, so a draft whose server slot disagrees with its count still restores
///    to a coherent media state.
/// 2. **A link card is only written when there is no media.** Media wins; the
///    link is dropped from the draft rather than persisted and ignored later.
public enum ComposerDraftCoding {
  /// The GIF hostnames whose URLs carry the composer's dimension/alt params.
  public static let gifHostnames = ["media.tenor.com", "static.klipy.com"]

  /// Converts composer state into a server draft.
  ///
  /// - Parameters:
  ///   - state: the composer state to convert.
  ///   - deviceId: this device's identifier.
  ///   - deviceName: this device's display name (truncated to the lexicon's 100
  ///     characters).
  ///   - idGenerator: supplies `localRef` ids, so tests are deterministic.
  ///   - resolveQuote: resolves a quote URI to a strong ref; `nil` writes the
  ///     draft without the quote record, matching RN's `if (resolved ...)` guard.
  public static func draft(
    from state: ComposerState,
    deviceId: String,
    deviceName: String,
    idGenerator: () -> String = { UUID().uuidString },
    resolveQuote: (String) -> RecordReference? = { _ in nil }
  ) -> DraftConversion {
    var media: [DraftMediaFile] = []
    var posts: [App.Bsky.DraftDefs_DraftPost] = []

    for post in state.thread.posts {
      var draftPost = App.Bsky.DraftDefs_DraftPost(text: post.richText.text)
      if !post.labels.isEmpty {
        draftPost.labels = .comAtprotoLabelDefsSelfLabels(
          Com.Atproto.LabelDefs_SelfLabels(
            values: post.labels.values.map { Com.Atproto.LabelDefs_SelfLabel(val: $0) }))
      }

      switch post.embed.media {
      case .images(let images):
        let converted = serializeImages(images.images, idGenerator: idGenerator, into: &media)
        draftPost.embedGallery = App.Bsky.DraftDefs_DraftEmbedGallery(
          items: converted.map { .draftDefsDraftEmbedImage($0) })
      case .video(let video):
        if let serialized = serializeVideo(video, idGenerator: idGenerator, into: &media) {
          draftPost.embedVideos = [serialized]
        }
      case .gif(let gif):
        if let serialized = serializeGif(gif) {
          draftPost.embedExternals = [serialized]
        }
      case nil:
        break
      }

      if let quote = post.embed.quote, let ref = resolveQuote(quote.uri) {
        draftPost.embedRecords = [
          App.Bsky.DraftDefs_DraftEmbedRecord(record: ref.strongRef)
        ]
      }

      // Only persist the link card when no media owns the embed slot.
      if let link = post.embed.link, post.embed.media == nil {
        draftPost.embedExternals = [
          App.Bsky.DraftDefs_DraftEmbedExternal(uri: FormatString<URI>(rawValue: link.uri))
        ]
      }

      posts.append(draftPost)
    }

    let draft = App.Bsky.DraftDefs_Draft(
      deviceId: deviceId,
      deviceName: String(deviceName.prefix(100)),
      langs: nil,
      postgateEmbeddingRules: draftPostgateRules(from: state.thread.postgate.embeddingRules ?? []),
      posts: posts,
      threadgateAllow: draftThreadgateAllow(from: state.thread.threadgate))

    return DraftConversion(draft: draft, localRefPaths: media)
  }

  /// Serializes images to the draft's gallery shape, reusing an existing
  /// `localRefPath` when the image came from a restored draft.
  static func serializeImages(
    _ images: [ComposerImage],
    idGenerator: () -> String,
    into media: inout [DraftMediaFile]
  ) -> [App.Bsky.DraftDefs_DraftEmbedImage] {
    images.map { image in
      let localRefPath = image.localRefPath ?? "image:\(idGenerator())"
      media.append(DraftMediaFile(localRefPath: localRefPath, sourcePath: image.sourcePath))
      return App.Bsky.DraftDefs_DraftEmbedImage(
        alt: image.alt.isEmpty ? nil : image.alt,
        localRef: App.Bsky.DraftDefs_DraftEmbedLocalRef(path: localRefPath))
    }
  }

  /// Serializes a video, encoding the mime type into the `localRef` path.
  ///
  /// Ported from `serializeVideo`. A video with no compressed file yet is not
  /// serialized at all (`return undefined`), so a draft saved mid-compression
  /// simply has no video.
  static func serializeVideo(
    _ video: ComposerVideo,
    idGenerator: () -> String,
    into media: inout [DraftMediaFile]
  ) -> App.Bsky.DraftDefs_DraftEmbedVideo? {
    guard let compressed = video.video else { return nil }
    let mimeType = compressed.mimeType.isEmpty ? "video/mp4" : compressed.mimeType
    let ext = mimeToExt(mimeType)
    let localRefPath = "video:\(mimeType):\(idGenerator()).\(ext)"
    media.append(DraftMediaFile(localRefPath: localRefPath, sourcePath: compressed.uri))

    let captions = video.captions
      .filter { !$0.lang.isEmpty }
      .map {
        App.Bsky.DraftDefs_DraftEmbedCaption(
          content: $0.content, lang: FormatString<Language>(rawValue: $0.lang))
      }

    return App.Bsky.DraftDefs_DraftEmbedVideo(
      alt: video.altText.isEmpty ? nil : video.altText,
      captions: captions.isEmpty ? nil : captions,
      localRef: App.Bsky.DraftDefs_DraftEmbedLocalRef(path: localRefPath))
  }

  /// Serializes a GIF as an external embed, encoding dimensions and alt text as
  /// query parameters on its URL.
  ///
  /// Ported from `serializeGif`.
  static func serializeGif(_ gif: GifMedia) -> App.Bsky.DraftDefs_DraftEmbedExternal? {
    guard var components = URLComponents(string: gif.gif.url) else { return nil }
    var items = components.queryItems ?? []
    items.removeAll { ["ww", "hh", "alt", "mp4", "webm"].contains($0.name) }
    items.append(URLQueryItem(name: "ww", value: String(gif.gif.width)))
    items.append(URLQueryItem(name: "hh", value: String(gif.gif.height)))
    if !gif.alt.isEmpty {
      items.append(URLQueryItem(name: "alt", value: gif.alt))
    }
    components.queryItems = items
    guard let url = components.string else { return nil }
    return App.Bsky.DraftDefs_DraftEmbedExternal(uri: FormatString<URI>(rawValue: url))
  }

  /// The file extension for a video mime type, so the saved `localRef` path is
  /// readable. Ported from `mimeToExt`.
  public static func mimeToExt(_ mimeType: String) -> String {
    switch mimeType {
    case "video/mp4": "mp4"
    case "video/webm": "webm"
    case "video/quicktime": "mov"
    case "image/gif": "gif"
    default: "mp4"
    }
  }

  /// Converts composer reply-permission settings into the draft's allow list.
  ///
  /// The draft lexicon declares its own copy of the threadgate rule union, so
  /// the two shapes must be mapped explicitly.
  static func draftThreadgateAllow(
    from settings: [ThreadgateAllowUISetting]
  ) -> [App.Bsky.DraftDefs_Draft_ThreadgateAllow_Elem]? {
    guard let allow = ComposerGates.allowRecordValue(from: settings) else { return nil }
    return allow.map { element in
      switch element {
      case .feedThreadgateMentionRule(let rule): .feedThreadgateMentionRule(rule)
      case .feedThreadgateFollowerRule(let rule): .feedThreadgateFollowerRule(rule)
      case .feedThreadgateFollowingRule(let rule): .feedThreadgateFollowingRule(rule)
      case .feedThreadgateListRule(let rule): .feedThreadgateListRule(rule)
      case ._other(let value): ._other(value)
      }
    }
  }

  /// Converts a draft's allow list back into the threadgate record shape.
  static func threadgateAllowFromDraft(
    _ element: App.Bsky.DraftDefs_Draft_ThreadgateAllow_Elem
  ) -> App.Bsky.FeedThreadgate_Allow_Elem {
    switch element {
    case .feedThreadgateMentionRule(let rule): .feedThreadgateMentionRule(rule)
    case .feedThreadgateFollowerRule(let rule): .feedThreadgateFollowerRule(rule)
    case .feedThreadgateFollowingRule(let rule): .feedThreadgateFollowingRule(rule)
    case .feedThreadgateListRule(let rule): .feedThreadgateListRule(rule)
    case ._other(let value): ._other(value)
    }
  }

  /// Converts postgate embedding rules into the draft's copy of the union.
  static func draftPostgateRules(
    from rules: [App.Bsky.FeedPostgate_EmbeddingRules_Elem]
  ) -> [App.Bsky.DraftDefs_Draft_PostgateEmbeddingRules_Elem]? {
    guard !rules.isEmpty else { return nil }
    return rules.map { rule in
      switch rule {
      case .feedPostgateDisableRule(let value): .feedPostgateDisableRule(value)
      case ._other(let value): ._other(value)
      }
    }
  }

  /// Converts a draft's embedding rules back into the postgate record shape.
  static func postgateRuleFromDraft(
    _ element: App.Bsky.DraftDefs_Draft_PostgateEmbeddingRules_Elem
  ) -> App.Bsky.FeedPostgate_EmbeddingRules_Elem {
    switch element {
    case .feedPostgateDisableRule(let value): .feedPostgateDisableRule(value)
    case ._other(let value): ._other(value)
    }
  }

  /// Parses the mime type back out of a video `localRef.path`.
  ///
  /// Ported from `parseVideoMimeType`, including its backwards-compatibility
  /// rule: the legacy format `video:<id>` carries no mime type and defaults to
  /// `video/mp4`.
  public static func parseVideoMimeType(_ localRefPath: String) -> String {
    let parts = localRefPath.split(separator: ":").map(String.init)
    if parts.count >= 3, parts[1].contains("/") {
      return parts[1]
    }
    return "video/mp4"
  }

  /// Parses a GIF's dimensions and alt text back out of its URL.
  ///
  /// Ported from `parseGifFromUrl`: only the known GIF hostnames are accepted,
  /// and the composer's own params are stripped so a re-serialize does not
  /// produce a doubled query string.
  public static func parseGifFromUrl(_ uri: String) -> GifMedia? {
    guard let components = URLComponents(string: uri),
      let host = components.host,
      gifHostnames.contains(host)
    else { return nil }

    let items = components.queryItems ?? []
    func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

    guard let width = value("ww").flatMap(Int.init),
      let height = value("hh").flatMap(Int.init)
    else { return nil }

    var cleaned = components
    cleaned.queryItems = items.filter {
      !["ww", "hh", "alt", "mp4", "webm"].contains($0.name)
    }
    guard let url = cleaned.string else { return nil }

    return GifMedia(
      gif: ComposerGif(url: url, width: width, height: height),
      alt: value("alt") ?? "")
  }

  /// Hydrates composer posts from a server draft.
  ///
  /// Ported from `draftToComposerPosts`. Media that is not present in
  /// `loadedMedia` is dropped (the file is missing or lives on another device).
  public static func hydrate(
    draft: App.Bsky.DraftDefs_Draft,
    loadedMedia: [String: String],
    firstPostId: (Int) -> String = { "draft-post-\($0)" },
    imageIdGenerator: @escaping @Sendable () -> String = { UUID().uuidString },
    imageDimensions: @escaping @Sendable (String) -> (width: Double, height: Double)? = { _ in nil }
  ) -> DraftHydration {
    var restoredVideos: [Int: RestoredVideo] = [:]
    var posts: [PostDraft] = []

    for (index, draftPost) in draft.posts.enumerated() {
      var restoredVideo: RestoredVideo?
      let post = hydratePost(
        draftPost,
        id: firstPostId(index),
        loadedMedia: loadedMedia,
        options: DraftHydrateOptions(
          imageIdGenerator: imageIdGenerator, imageDimensions: imageDimensions),
        restoredVideo: &restoredVideo)
      if let restoredVideo { restoredVideos[index] = restoredVideo }
      posts.append(post)
    }

    return DraftHydration(
      posts: posts,
      restoredVideos: restoredVideos,
      threadgateAllow: (draft.threadgateAllow ?? []).map(threadgateAllowFromDraft),
      postgateEmbeddingRules: (draft.postgateEmbeddingRules ?? []).map(postgateRuleFromDraft),
      originalLocalRefs: localRefs(in: draft))
  }

  /// Hydrates one draft post.
  ///
  /// Videos are handed back through `restoredVideo` rather than attached,
  /// because they must be re-compressed and re-uploaded before they can be
  /// published.
  static func hydratePost(
    _ draftPost: App.Bsky.DraftDefs_DraftPost,
    id: String,
    loadedMedia: [String: String],
    options: DraftHydrateOptions,
    restoredVideo: inout RestoredVideo?
  ) -> PostDraft {
    let richText = RichTextValue(text: draftPost.text).detectingFacetsWithoutResolution()
    var embed = EmbedDraft()
    embed.media = hydrateImages(
      draftPost, loadedMedia: loadedMedia, options: options)
    if embed.media == nil, let gif = hydrateGif(draftPost) { embed.media = .gif(gif) }
    restoredVideo = hydrateVideo(draftPost, loadedMedia: loadedMedia)
    embed.quote = hydrateQuote(draftPost)
    if embed.media == nil { embed.link = hydrateLink(draftPost) }

    return PostDraft(
      id: id, richText: richText, labels: hydrateLabels(draftPost), embed: embed)
  }

  /// Restores images from both draft slots, dropping any whose file is missing.
  static func hydrateImages(
    _ draftPost: App.Bsky.DraftDefs_DraftPost,
    loadedMedia: [String: String],
    options: DraftHydrateOptions
  ) -> ComposerMedia? {
    var draftImages: [App.Bsky.DraftDefs_DraftEmbedImage] = draftPost.embedImages ?? []
    if let gallery = draftPost.embedGallery {
      for item in gallery.items {
        if case .draftDefsDraftEmbedImage(let image) = item { draftImages.append(image) }
      }
    }
    let restored: [ComposerImage] = draftImages.compactMap { draftImage in
      guard let path = loadedMedia[draftImage.localRef.path] else { return nil }
      let dimensions = options.imageDimensions(path) ?? (width: 0, height: 0)
      return ComposerImage(
        id: options.imageIdGenerator(),
        path: path,
        width: dimensions.width,
        height: dimensions.height,
        alt: draftImage.alt ?? "",
        localRefPath: draftImage.localRef.path)
    }
    guard !restored.isEmpty else { return nil }
    // Re-pick the variant from the restored count so it agrees with the
    // composer reducer's rule even if the draft's server slot disagrees.
    return .images(.variant(for: restored))
  }

  /// Restores a GIF from the draft's external embed, when one is there.
  static func hydrateGif(_ draftPost: App.Bsky.DraftDefs_DraftPost) -> GifMedia? {
    for external in draftPost.embedExternals ?? [] {
      if let gif = parseGifFromUrl(external.uri.rawValue) { return gif }
    }
    return nil
  }

  /// Finds a video the draft references and its local file, if present.
  static func hydrateVideo(
    _ draftPost: App.Bsky.DraftDefs_DraftPost,
    loadedMedia: [String: String]
  ) -> RestoredVideo? {
    guard let video = draftPost.embedVideos?.first,
      let uri = loadedMedia[video.localRef.path]
    else { return nil }
    return RestoredVideo(
      uri: uri,
      altText: video.alt ?? "",
      mimeType: parseVideoMimeType(video.localRef.path),
      localRefPath: video.localRef.path,
      captions: (video.captions ?? []).map {
        VideoCaptionTrack(lang: $0.lang.rawValue, content: $0.content)
      })
  }

  /// Restores a quote as an app URL.
  static func hydrateQuote(_ draftPost: App.Bsky.DraftDefs_DraftPost) -> QuoteLink? {
    guard let record = draftPost.embedRecords?.first,
      let path = URLHelpers.postUriToRelativePath(record.record.uri.rawValue)
    else { return nil }
    return QuoteLink(uri: URLHelpers.toBskyAppUrl(path))
  }

  /// Restores a non-GIF external embed as a link card.
  static func hydrateLink(_ draftPost: App.Bsky.DraftDefs_DraftPost) -> ExternalLink? {
    for external in draftPost.embedExternals ?? [] where parseGifFromUrl(external.uri.rawValue) == nil {
      return ExternalLink(uri: external.uri.rawValue)
    }
    return nil
  }

  /// Restores self-labels from the draft.
  static func hydrateLabels(_ draftPost: App.Bsky.DraftDefs_DraftPost) -> SelfLabelSet {
    var labels = SelfLabelSet()
    if case .comAtprotoLabelDefsSelfLabels(let selfLabels)? = draftPost.labels {
      for value in selfLabels.values {
        labels.insert(value.val)
      }
    }
    return labels
  }

  /// Every `localRef.path` a draft references.
  ///
  /// Ported from `extractLocalRefs`, which is how orphaned media is identified
  /// when a draft is re-saved or deleted.
  public static func localRefs(in draft: App.Bsky.DraftDefs_Draft) -> Set<String> {
    var refs = Set<String>()
    for post in draft.posts {
      for image in post.embedImages ?? [] { refs.insert(image.localRef.path) }
      if let gallery = post.embedGallery {
        for item in gallery.items {
          if case .draftDefsDraftEmbedImage(let image) = item { refs.insert(image.localRef.path) }
        }
      }
      for video in post.embedVideos ?? [] { refs.insert(video.localRef.path) }
    }
    return refs
  }
}

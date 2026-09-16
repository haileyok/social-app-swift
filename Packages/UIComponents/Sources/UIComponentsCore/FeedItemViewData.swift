import Foundation
import Moderation
import RichText

/// The data a ``PostFeedItem`` renders, derived from a ``PostView``.
///
/// Building this in the core keeps every display decision - the formatted
/// relative time, the count strings, which embed variant is present, whether a
/// repost/context line shows - out of the view and testable on Linux. The view
/// receives a value and draws it.
public struct FeedItemViewData: Sendable {
  /// The author line.
  public let authorDid: String
  public let displayName: String
  public let handle: String
  /// The relative timestamp, e.g. `2h`. Empty when the post has no timestamp.
  public let relativeTime: String
  /// The RichText body, already segment-split for the renderer.
  public let segments: [RichTextSegment]
  /// The raw text, for the accessibility label and the empty-body case.
  public let text: String
  /// The embed, when present.
  public let embed: EmbedVariantInfo?
  /// The hydrated embed value, for the views that need its contents.
  public let postEmbed: PostViewEmbed?
  /// Engagement counts, already formatted. `nil` when the API omitted the count.
  public let replyCount: String?
  public let repostCount: String?
  public let likeCount: String?
  /// A repost/context header, e.g. "Reposted by Alice".
  public let contextLine: String?
  /// The author's avatar source.
  public let avatar: AvatarSource
  /// Moderation projections for the four surfaces.
  public let moderation: FeedItemModeration

  public init(
    displayName: String,
    handle: String,
    relativeTime: String,
    segments: [RichTextSegment],
    text: String,
    embed: EmbedVariantInfo?,
    postEmbed: PostViewEmbed?,
    replyCount: String?,
    repostCount: String?,
    likeCount: String?,
    contextLine: String?,
    avatar: AvatarSource,
    moderation: FeedItemModeration,
    authorDid: String = ""
  ) {
    self.authorDid = authorDid
    self.displayName = displayName
    self.handle = handle
    self.relativeTime = relativeTime
    self.segments = segments
    self.text = text
    self.embed = embed
    self.postEmbed = postEmbed
    self.replyCount = replyCount
    self.repostCount = repostCount
    self.likeCount = likeCount
    self.contextLine = contextLine
    self.avatar = avatar
    self.moderation = moderation
  }
}

extension FeedItemViewData {
  /// Remote assets this post row will draw, ordered avatar first then media.
  public var imageURLs: [URL] {
    var urls: [URL] = []
    if case .remote(let url) = avatar { urls.append(url) }
    if let postEmbed { urls.append(contentsOf: postEmbed.imageURLs) }
    return urls
  }
}

extension PostViewEmbed {
  /// Image URLs nested in this hydrated embed.
  public var imageURLs: [URL] {
    switch self {
    case .images(let images):
      return images.compactMap(embedImageURL)
    case .gallery(let items):
      return galleryImages(items).compactMap(embedImageURL)
    case .recordWithMedia(let value):
      return value.media?.imageURLs ?? []
    case .record(let record):
      guard let avatar = record.record?.viewRecord?.author?.avatar,
        let url = URL(string: avatar)
      else { return [] }
      return [url]
    case .external, .video, .unknown:
      return []
    }
  }
}

extension RecordWithMediaViewMedia {
  fileprivate var imageURLs: [URL] {
    switch self {
    case .images(let images): return images.compactMap(embedImageURL)
    case .gallery(let items): return galleryImages(items).compactMap(embedImageURL)
    case .external, .video, .unknown: return []
    }
  }
}

/// Everything the view builder needs that is not on the post itself.
public struct FeedItemRenderOptions: Sendable {
  /// The current time, so relative timestamps are deterministic in tests.
  public let now: Date
  /// The locale used for counts and dates.
  public let locale: Locale
  /// A repost/context header supplied by the caller (a feed reason, a
  /// "replying to" line). The caller knows the feed's semantics; the component
  /// only renders the string it is given.
  public let contextLine: String?

  public init(now: Date = Date(), locale: Locale = Locale(identifier: "en_US"), contextLine: String? = nil) {
    self.now = now
    self.locale = locale
    self.contextLine = contextLine
  }
}

/// Builds the view data for a post.
///
/// - Parameter decision: the moderation decision for the post. Pass a fresh
///   `ModerationDecision()` when moderation is not in play.
public func feedItemViewData(
  _ post: PostView,
  decision: ModerationDecision = ModerationDecision(),
  options: FeedItemRenderOptions = FeedItemRenderOptions()
) -> FeedItemViewData {
  let author = post.author
  let handle = "@\(author.handle)"
  let displayName = author.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
  let richText = richTextFromRecord(post.record)
  let embed = post.embed
  return FeedItemViewData(
    displayName: (displayName?.isEmpty == false ? displayName! : handle),
    handle: handle,
    relativeTime: relativeTimeString(indexedAt: post.indexedAt, now: options.now, locale: options.locale),
    segments: richText.segments(),
    text: richText.text,
    embed: embedVariantInfo(embed),
    postEmbed: embed,
    replyCount: nil,
    repostCount: nil,
    likeCount: nil,
    contextLine: options.contextLine,
    avatar: AvatarSource.resolve(
      avatar: author.avatar, handle: author.handle, displayName: author.displayName),
    moderation: FeedItemModeration.project(decision),
    authorDid: author.did)
}

/// Builds the view data for an already-hydrated engagement row.
///
/// The engine's stand-in ``PostView`` has no counts (they live on the generated
/// lexicon's `FeedDefs_PostView`), so the counts are supplied separately. This
/// overload keeps the renderer usable today and lets a full-lexicon adapter pass
/// the real numbers without changing the view.
public func feedItemViewData(
  _ post: PostView,
  counts: FeedItemCounts,
  decision: ModerationDecision = ModerationDecision(),
  options: FeedItemRenderOptions = FeedItemRenderOptions()
) -> FeedItemViewData {
  let base = feedItemViewData(post, decision: decision, options: options)
  return FeedItemViewData(
    displayName: base.displayName,
    handle: base.handle,
    relativeTime: base.relativeTime,
    segments: base.segments,
    text: base.text,
    embed: base.embed,
    postEmbed: base.postEmbed,
    replyCount: formatOptionalCount(counts.replyCount, locale: options.locale),
    repostCount: formatOptionalCount(counts.repostCount, locale: options.locale),
    likeCount: formatOptionalCount(counts.likeCount, locale: options.locale),
    contextLine: base.contextLine,
    avatar: base.avatar,
    moderation: base.moderation,
    authorDid: base.authorDid)
}

/// The engagement counts for one post.
public struct FeedItemCounts: Equatable, Sendable {
  public let replyCount: Int?
  public let repostCount: Int?
  public let likeCount: Int?

  public init(replyCount: Int? = nil, repostCount: Int? = nil, likeCount: Int? = nil) {
    self.replyCount = replyCount
    self.repostCount = repostCount
    self.likeCount = likeCount
  }
}

/// Formats an optional count through ``FormatCount``. `nil` and `0` both render
/// as nil so the engagement row hides an absent metric, matching the RN
/// `PostControl` which omits a zero-count label.
public func formatOptionalCount(_ value: Int?, locale: Locale = Locale(identifier: "en_US")) -> String? {
  guard let value, value > 0 else { return nil }
  return MetricFormat.formatCount(value, locale: locale)
}

/// Parses the loose `indexedAt` string into a relative label.
///
/// The lexicon declares `indexedAt` as an ISO-8601 date; the engine's stand-in
/// type keeps it a string, so the parse lives here. An unparseable value yields
/// an empty string, and the view omits the timestamp rather than showing
/// something wrong.
public func relativeTimeString(
  indexedAt: String?, now: Date = Date(), locale: Locale = Locale(identifier: "en_US")
) -> String {
  guard let indexedAt, let date = parseIndexedAt(indexedAt) else { return "" }
  let diff = MetricTime.dateDiff(earlier: date, later: now)
  return MetricTime.formatDateDiff(diff, locale: locale)
}

/// Parses the timestamp formats the API emits (with and without fractional
/// seconds). Kept internal-facing but public for adapters that need the date.
public func parseIndexedAt(_ raw: String) -> Date? {
  let withFraction = ISO8601DateFormatter()
  withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let date = withFraction.date(from: raw) { return date }
  let plain = ISO8601DateFormatter()
  plain.formatOptions = [.withInternetDateTime]
  return plain.date(from: raw)
}

/// Converts a post record's engine fac/entity shape into a ``RichText``.
///
/// The engine's ``RichTextFacet`` is byte-indexed exactly like
/// ``RichText/Facet``, so the conversion is field-for-field.
public func richTextFromRecord(_ record: FeedPostRecord?) -> RichText {
  guard let record else { return RichText(text: "") }
  let facets = record.facets?.compactMap(richTextFacet)
  return RichText(text: record.text, facets: facets)
}

/// Converts one engine facet to a RichText facet, dropping features whose range
/// is invalid. A facet with no recognised feature is kept as a plain range so
/// the byte offsets of later facets are unaffected.
func richTextFacet(_ facet: RichTextFacet) -> Facet? {
  guard let index = facet.index, let start = index.byteStart, let end = index.byteEnd else {
    return nil
  }
  guard start <= end else { return nil }
  let features = (facet.features ?? []).compactMap(richTextFeature)
  return Facet(index: ByteSlice(byteStart: start, byteEnd: end), features: features)
}

/// Maps the engine's loosely-typed feature onto RichText's typed one.
func richTextFeature(_ feature: RichTextFacetFeature) -> FacetFeature? {
  guard let type = feature.type else { return nil }
  switch type {
  case FacetType.link:
    // The engine's stand-in feature carries only `tag`, so a link's URI is not
    // recoverable from it; fall through to nil rather than inventing a link.
    return nil
  case FacetType.tag:
    guard let tag = feature.tag else { return nil }
    return .tag(tag: tag)
  case FacetType.mention:
    return nil
  default:
    return nil
  }
}

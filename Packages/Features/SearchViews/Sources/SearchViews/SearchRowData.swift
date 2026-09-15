import DesignSystem
import Foundation
import Lexicons
import Moderation
import RichText
import SwiftAtproto
import UIComponents
import UIComponentsCore

/// Presentation helpers turning lexicon views into the shapes `UIComponents`
/// renders.
///
/// The conversion is deliberately one-directional and total: nothing here
/// decides *whether* a row should show (the logic layer owns that) and nothing
/// re-derives a rule the search package already applied. These are the
/// mechanical mappings a view needs so it never touches a lexicon type directly.
public enum SearchRowData {
  /// The avatar source for a profile view.
  public static func avatar(_ profile: Lexicons.App.Bsky.ActorDefs_ProfileView) -> AvatarSource {
    AvatarSource.resolve(
      avatar: profile.avatar?.rawValue,
      handle: profile.handle.rawValue,
      displayName: profile.displayName)
  }

  /// The avatar source for a basic profile view.
  public static func avatar(_ profile: Lexicons.App.Bsky.ActorDefs_ProfileViewBasic) -> AvatarSource {
    AvatarSource.resolve(
      avatar: profile.avatar?.rawValue,
      handle: profile.handle.rawValue,
      displayName: profile.displayName)
  }

  /// The name a row shows: the display name when set, otherwise the handle.
  ///
  /// Matches the RN list rows, which fall back to the handle rather than
  /// rendering an empty title line.
  public static func displayName(_ profile: Lexicons.App.Bsky.ActorDefs_ProfileView) -> String {
    let name = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (name?.isEmpty == false ? name! : "@\(profile.handle.rawValue)")
  }

  /// The name a basic-profile row shows.
  public static func displayName(_ profile: Lexicons.App.Bsky.ActorDefs_ProfileViewBasic) -> String {
    let name = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (name?.isEmpty == false ? name! : "@\(profile.handle.rawValue)")
  }

  /// The handle line, with the leading `@` the RN rows use.
  public static func handle(_ profile: Lexicons.App.Bsky.ActorDefs_ProfileView) -> String {
    "@\(profile.handle.rawValue)"
  }

  /// The bio line, when the profile has one.
  public static func bio(_ profile: Lexicons.App.Bsky.ActorDefs_ProfileView) -> String? {
    let text = profile.description?.trimmingCharacters(in: .whitespacesAndNewlines)
    return text?.isEmpty == false ? text : nil
  }

  // MARK: - Feed generators

  /// The feed generator's display name.
  public static func title(_ feed: Lexicons.App.Bsky.FeedDefs_GeneratorView) -> String {
    feed.displayName
  }

  /// The feed's byline.
  public static func byline(_ feed: Lexicons.App.Bsky.FeedDefs_GeneratorView) -> String {
    SearchCopy.feedByline(creatorHandle: feed.creator.handle.rawValue)
  }

  /// The feed's description, when it has one.
  public static func description(_ feed: Lexicons.App.Bsky.FeedDefs_GeneratorView) -> String? {
    let text = feed.description?.trimmingCharacters(in: .whitespacesAndNewlines)
    return text?.isEmpty == false ? text : nil
  }

  // MARK: - Starter packs

  /// A starter pack's display name.
  ///
  /// `GraphDefs_StarterPackView` carries the name on its backing list rather
  /// than at the top level (the RN screen reads the same field), so the list
  /// name is the title and the record's name is only a fallback.
  public static func title(_ pack: Lexicons.App.Bsky.GraphDefs_StarterPackView) -> String {
    pack.list?.name ?? SearchCopy.starterPackTitleFallback
  }

  /// The starter pack's byline.
  public static func byline(_ pack: Lexicons.App.Bsky.GraphDefs_StarterPackView) -> String {
    SearchCopy.starterPackByline(creatorHandle: pack.creator.handle.rawValue)
  }

  // MARK: - Trending

  /// A trending topic's display name, falling back to the topic slug.
  public static func title(_ topic: Lexicons.App.Bsky.UnspeccedDefs_TrendingTopic) -> String {
    topic.displayName ?? topic.topic
  }

  /// A trending video's display name.
  public static func title(_ trend: Lexicons.App.Bsky.UnspeccedDefs_TrendView) -> String {
    trend.displayName
  }

  /// A trending video's post-count caption.
  public static func postCount(_ trend: Lexicons.App.Bsky.UnspeccedDefs_TrendView) -> String {
    SearchCopy.trendingPostCount(trend.postCount)
  }

  // MARK: - Posts

  /// The render data for a search-result post.
  ///
  /// Counts and relative time come from the lexicon view, unlike the engine's
  /// stand-in `PostView`; moderation is not run here because the search screen
  /// has no moderation options yet, which is the same posture the thread screen
  /// documents in ``PostModerationAdapter``.
  public static func feedItem(
    _ post: Lexicons.App.Bsky.FeedDefs_PostView,
    now: Date = Date(),
    locale: Locale = Locale(identifier: "en_US")
  ) -> FeedItemViewData {
    let author = post.author
    let handle = "@\(author.handle.rawValue)"
    let name = author.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let record = post.record.postRecord
    return FeedItemViewData(
      displayName: (name?.isEmpty == false ? name! : handle),
      handle: handle,
      relativeTime: relativeTimeString(
        indexedAt: post.indexedAt.rawValue, now: now, locale: locale),
      segments: record.map { RichText(text: $0.text).segments() } ?? [],
      text: record?.text ?? "",
      embed: nil,
      postEmbed: nil,
      replyCount: formatOptionalCount(post.replyCount, locale: locale),
      repostCount: formatOptionalCount(post.repostCount, locale: locale),
      likeCount: formatOptionalCount(post.likeCount, locale: locale),
      contextLine: nil,
      avatar: AvatarSource.resolve(
        avatar: author.avatar?.rawValue,
        handle: author.handle.rawValue,
        displayName: author.displayName),
      moderation: FeedItemModeration.project(ModerationDecision()))
  }
}

/// The `app.bsky.feed.post` record on an unknown value, when it is one.
///
/// Mirrors `UnknownATPValue.postRecord` in the PostThread feature; declared here
/// too so this package does not depend on that one for a three-line cast.
private extension UnknownATPValue {
  var postRecord: Lexicons.App.Bsky.FeedPost? {
    guard case .record(let record) = self else { return nil }
    return record as? Lexicons.App.Bsky.FeedPost
  }
}

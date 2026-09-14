import Foundation
import Lexicons
import SwiftAtproto

/// How the composer exposes reply permissions to the UI.
///
/// Ported from `ThreadgateAllowUISetting` in `state/queries/threadgate/types.ts`.
/// Note the historical encoding: an **undefined** `allow` array means "everybody",
/// and an **empty** array means "nobody". Neither is representable as a member
/// of the record's `allow` list, so both live here.
public enum ThreadgateAllowUISetting: Hashable, Sendable {
  /// Anyone can reply.
  case everybody
  /// No one can reply.
  case nobody
  /// Only accounts mentioned in the post can reply.
  case mention
  /// Only accounts the author follows can reply.
  case following
  /// Only the author's followers can reply.
  case followers
  /// Only members of the given list can reply.
  case list(uri: String)
}

/// Builders and converters for threadgate and postgate records.
///
/// Ported from `state/queries/threadgate/util.ts` and
/// `state/queries/postgate/util.ts`.
public enum ComposerGates {

  // MARK: - Threadgate

  /// `POSTGATE_COLLECTION` / the threadgate collection NSID.
  public static let threadgateCollection = "app.bsky.feed.threadgate"
  /// The postgate collection NSID.
  public static let postgateCollection = "app.bsky.feed.postgate"

  /// Converts a threadgate record's `allow` list into UI settings.
  ///
  /// Ported from `threadgateRecordToAllowUISetting`.
  ///
  /// - `nil` record, or `allow == nil`, means anyone can reply.
  /// - `allow == []` means no one can reply (the only lexicon representation
  ///   for "replies disabled").
  public static func allowUISettings(
    from record: App.Bsky.FeedThreadgate?
  ) -> [ThreadgateAllowUISetting] {
    guard let record, let allow = record.allow else { return [.everybody] }
    if allow.isEmpty { return [.nobody] }
    return allow.compactMap { element in
      switch element {
      case .feedThreadgateMentionRule: .mention
      case .feedThreadgateFollowingRule: .following
      case .feedThreadgateFollowerRule: .followers
      case .feedThreadgateListRule(let rule): .list(uri: rule.list.rawValue)
      case ._other: nil
      }
    }
  }

  /// Converts UI settings into the record's `allow` list.
  ///
  /// Ported from `threadgateAllowUISettingToAllowRecordValue`. Returns `nil`
  /// (meaning "everyone") when `.everybody` is present, and an empty array
  /// (meaning "nobody") when `.nobody` is present.
  public static func allowRecordValue(
    from settings: [ThreadgateAllowUISetting]
  ) -> [App.Bsky.FeedThreadgate_Allow_Elem]? {
    if settings.contains(.everybody) { return nil }
    var allow: [App.Bsky.FeedThreadgate_Allow_Elem] = []
    if !settings.contains(.nobody) {
      for setting in settings {
        switch setting {
        case .mention:
          allow.append(.feedThreadgateMentionRule(.init()))
        case .following:
          allow.append(.feedThreadgateFollowingRule(.init()))
        case .followers:
          allow.append(.feedThreadgateFollowerRule(.init()))
        case .list(let uri):
          allow.append(.feedThreadgateListRule(.init(list: FormatString<ATURI>(rawValue: uri))))
        case .everybody, .nobody:
          break
        }
      }
    }
    return allow
  }

  /// Builds a threadgate record. `post` is required, matching the RN guard.
  ///
  /// - Throws: ``ComposerGateError/missingPostUri`` when `post` is empty.
  public static func createThreadgateRecord(
    post: String,
    allow: [App.Bsky.FeedThreadgate_Allow_Elem]? = nil,
    hiddenReplies: [String] = [],
    createdAt: Date = Date()
  ) throws -> App.Bsky.FeedThreadgate {
    guard !post.isEmpty else { throw ComposerGateError.missingPostUri }
    return App.Bsky.FeedThreadgate(
      allow: allow,
      createdAt: FormatString<Date>(rawValue: isoString(createdAt)),
      hiddenReplies: hiddenReplies.map { FormatString<ATURI>(rawValue: $0) },
      post: FormatString<ATURI>(rawValue: post))
  }

  /// Merges two threadgate records, deduplicating `allow` by `$type` and
  /// unioning `hiddenReplies`.
  ///
  /// Ported from `mergeThreadgateRecords`. `allow` stays `nil` if both inputs
  /// are `nil`, because `nil` means "everyone" and must not collapse to `[]`.
  public static func mergeThreadgateRecords(
    prev: App.Bsky.FeedThreadgate,
    allow nextAllow: [App.Bsky.FeedThreadgate_Allow_Elem]? = nil,
    hiddenReplies nextHidden: [String] = [],
    createdAt: Date = Date()
  ) throws -> App.Bsky.FeedThreadgate {
    let allow: [App.Bsky.FeedThreadgate_Allow_Elem]?
    if prev.allow != nil || nextAllow != nil {
      var seen = Set<String>()
      var merged: [App.Bsky.FeedThreadgate_Allow_Elem] = []
      for element in (prev.allow ?? []) + (nextAllow ?? []) {
        let key = elementTypeKey(element)
        if seen.insert(key).inserted { merged.append(element) }
      }
      allow = merged
    } else {
      allow = nil
    }
    var seenHidden = Set<String>()
    var hidden: [String] = []
    for uri in (prev.hiddenReplies?.map(\.rawValue) ?? []) + nextHidden
    where seenHidden.insert(uri).inserted {
      hidden.append(uri)
    }
    return try createThreadgateRecord(
      post: prev.post.rawValue, allow: allow, hiddenReplies: hidden, createdAt: createdAt)
  }

  /// The `$type` of an allow element, used to deduplicate merges.
  static func elementTypeKey(_ element: App.Bsky.FeedThreadgate_Allow_Elem) -> String {
    switch element {
    case .feedThreadgateMentionRule: "app.bsky.feed.threadgate#mentionRule"
    case .feedThreadgateFollowerRule: "app.bsky.feed.threadgate#followerRule"
    case .feedThreadgateFollowingRule: "app.bsky.feed.threadgate#followingRule"
    case .feedThreadgateListRule: "app.bsky.feed.threadgate#listRule"
    case ._other(let value): value.type ?? "unknown"
    }
  }

  // MARK: - Postgate

  /// The `disableRule` value the composer writes when the author disables
  /// embedding: `app.bsky.feed.postgate#disableRule`.
  public static var disableRule: App.Bsky.FeedPostgate_EmbeddingRules_Elem {
    .feedPostgateDisableRule(.init())
  }

  /// Builds a postgate record.
  ///
  /// Ported from `createPostgateRecord`. `detachedEmbeddingUris` defaults to an
  /// empty array and `embeddingRules` to an empty array, matching the RN
  /// defaults (`postgate.detachedEmbeddingUris || []`).
  ///
  /// - Throws: ``ComposerGateError/missingPostUri`` when `post` is empty.
  public static func createPostgateRecord(
    post: String,
    embeddingRules: [App.Bsky.FeedPostgate_EmbeddingRules_Elem] = [],
    detachedEmbeddingUris: [String] = [],
    createdAt: Date = Date()
  ) throws -> App.Bsky.FeedPostgate {
    guard !post.isEmpty else { throw ComposerGateError.missingPostUri }
    return App.Bsky.FeedPostgate(
      createdAt: FormatString<Date>(rawValue: isoString(createdAt)),
      detachedEmbeddingUris: detachedEmbeddingUris.map { FormatString<ATURI>(rawValue: $0) },
      embeddingRules: embeddingRules,
      post: FormatString<ATURI>(rawValue: post))
  }

  /// Builds a postgate record for a not-yet-created post.
  ///
  /// The composer holds its postgate before the post has a URI, so this variant
  /// tolerates an empty `post` (the RN state carries `post: ''` until publish).
  public static func placeholderPostgateRecord(
    embeddingRules: [App.Bsky.FeedPostgate_EmbeddingRules_Elem] = [],
    detachedEmbeddingUris: [String] = [],
    createdAt: Date = Date()
  ) -> App.Bsky.FeedPostgate {
    App.Bsky.FeedPostgate(
      createdAt: FormatString<Date>(rawValue: isoString(createdAt)),
      detachedEmbeddingUris: detachedEmbeddingUris.map { FormatString<ATURI>(rawValue: $0) },
      embeddingRules: embeddingRules,
      post: FormatString<ATURI>(rawValue: ""))
  }

  /// Merges two postgate records, unioning both arrays and deduplicating
  /// embedding rules by `$type`.
  ///
  /// Ported from `mergePostgateRecords`.
  public static func mergePostgateRecords(
    prev: App.Bsky.FeedPostgate,
    embeddingRules nextRules: [App.Bsky.FeedPostgate_EmbeddingRules_Elem] = [],
    detachedEmbeddingUris nextDetached: [String] = [],
    createdAt: Date = Date()
  ) -> App.Bsky.FeedPostgate {
    var seenDetached = Set<String>()
    var detached: [String] = []
    for uri in (prev.detachedEmbeddingUris?.map(\.rawValue) ?? []) + nextDetached
    where seenDetached.insert(uri).inserted {
      detached.append(uri)
    }
    var seenTypes = Set<String>()
    var rules: [App.Bsky.FeedPostgate_EmbeddingRules_Elem] = []
    for rule in (prev.embeddingRules ?? []) + nextRules
    where seenTypes.insert(ruleTypeKey(rule)).inserted {
      rules.append(rule)
    }
    return App.Bsky.FeedPostgate(
      createdAt: FormatString<Date>(rawValue: isoString(createdAt)),
      detachedEmbeddingUris: detached.map { FormatString<ATURI>(rawValue: $0) },
      embeddingRules: rules,
      post: prev.post)
  }

  /// The `$type` of an embedding-rule element, used to deduplicate merges.
  static func ruleTypeKey(_ element: App.Bsky.FeedPostgate_EmbeddingRules_Elem) -> String {
    switch element {
    case .feedPostgateDisableRule: "app.bsky.feed.postgate#disableRule"
    case ._other(let value): value.type ?? "unknown"
    }
  }
}

/// Failures the gate builders can raise.
public enum ComposerGateError: Error, Sendable, Equatable {
  /// A record was requested without a post URI, which the RN helpers also
  /// reject (`Cannot create a threadgate record without a post URI`).
  case missingPostUri
}

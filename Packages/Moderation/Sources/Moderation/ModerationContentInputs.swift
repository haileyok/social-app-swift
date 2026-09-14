import Foundation

/// `app.bsky.feed.defs#postView`
public struct PostView: Sendable, Codable, Hashable {
  public var type: String?
  public var uri: String
  public var cid: String?
  public var author: ProfileViewBasic
  public var record: FeedPostRecord?
  public var embed: PostViewEmbed?
  public var labels: [Label]?
  public var indexedAt: String?

  public init(
    type: String? = "app.bsky.feed.defs#postView",
    uri: String,
    cid: String? = nil,
    author: ProfileViewBasic,
    record: FeedPostRecord? = nil,
    embed: PostViewEmbed? = nil,
    labels: [Label]? = nil,
    indexedAt: String? = nil
  ) {
    self.type = type
    self.uri = uri
    self.cid = cid
    self.author = author
    self.record = record
    self.embed = embed
    self.labels = labels
    self.indexedAt = indexedAt
  }

  enum CodingKeys: String, CodingKey {
    case type = "$type"
    case uri
    case cid
    case author
    case record
    case embed
    case labels
    case indexedAt
  }
}

/// `app.bsky.graph.defs#listView` minimal shape used by `moderateUserList`.
public struct ListView: Sendable, Codable, Hashable {
  public var type: String?
  public var uri: String
  public var cid: String?
  public var creator: ProfileViewBasic?
  public var name: String?
  public var purpose: String?
  public var viewer: ListViewerState?
  public var labels: [Label]?

  public init(
    type: String? = "app.bsky.graph.defs#listView",
    uri: String,
    cid: String? = nil,
    creator: ProfileViewBasic? = nil,
    name: String? = nil,
    purpose: String? = nil,
    viewer: ListViewerState? = nil,
    labels: [Label]? = nil
  ) {
    self.type = type
    self.uri = uri
    self.cid = cid
    self.creator = creator
    self.name = name
    self.purpose = purpose
    self.viewer = viewer
    self.labels = labels
  }

  enum CodingKeys: String, CodingKey {
    case type = "$type"
    case uri
    case cid
    case creator
    case name
    case purpose
    case viewer
    case labels
  }
}

/// `app.bsky.feed.defs#generatorView`
public struct FeedGeneratorView: Sendable, Codable, Hashable {
  public var type: String?
  public var uri: String
  public var cid: String?
  public var did: String
  public var displayName: String?
  public var creator: ProfileViewBasic
  public var viewer: GeneratorViewerState?
  public var labels: [Label]?

  public init(
    type: String? = "app.bsky.feed.defs#generatorView",
    uri: String,
    cid: String? = nil,
    did: String,
    displayName: String? = nil,
    creator: ProfileViewBasic,
    viewer: GeneratorViewerState? = nil,
    labels: [Label]? = nil
  ) {
    self.type = type
    self.uri = uri
    self.cid = cid
    self.did = did
    self.displayName = displayName
    self.creator = creator
    self.viewer = viewer
    self.labels = labels
  }

  enum CodingKeys: String, CodingKey {
    case type = "$type"
    case uri
    case cid
    case did
    case displayName
    case creator
    case viewer
    case labels
  }
}

/// `app.bsky.feed.defs#generatorViewerState`
public struct GeneratorViewerState: Sendable, Codable, Hashable {
  public var like: String?
}

/// `app.bsky.notification.listNotifications#notification`
public struct NotificationView: Sendable, Codable, Hashable {
  public var type: String?
  public var uri: String?
  public var cid: String?
  public var author: ProfileViewBasic
  public var reason: String?
  public var record: FeedPostRecord?
  public var labels: [Label]?
  public var indexedAt: String?

  public init(
    type: String? = nil,
    uri: String? = nil,
    cid: String? = nil,
    author: ProfileViewBasic,
    reason: String? = nil,
    record: FeedPostRecord? = nil,
    labels: [Label]? = nil,
    indexedAt: String? = nil
  ) {
    self.type = type
    self.uri = uri
    self.cid = cid
    self.author = author
    self.reason = reason
    self.record = record
    self.labels = labels
    self.indexedAt = indexedAt
  }

  enum CodingKeys: String, CodingKey {
    case type = "$type"
    case uri
    case cid
    case author
    case reason
    case record
    case labels
    case indexedAt
  }
}

/// `app.bsky.actor.defs#statusView`, restricted to what the engine reads.
public struct StatusView: Sendable, Codable, Hashable {
  public var type: String?
  public var did: String
  public var status: StatusLabels?

  public init(type: String? = nil, did: String, status: StatusLabels? = nil) {
    self.type = type
    self.did = did
    self.status = status
  }

  enum CodingKeys: String, CodingKey {
    case type = "$type"
    case did
    case status
  }
}

/// The `status` field of a status view: the engine reads only its labels.
public struct StatusLabels: Sendable, Codable, Hashable {
  public var labels: [Label]?
}

/// Where a muted word applies.
public enum MutedWordTarget: String, Sendable, Codable, Hashable {
  case content
  case tag
}

/// Whose content a muted word applies to.
public enum MutedWordActorTarget: String, Sendable, Codable, Hashable {
  case all
  case excludeFollowing = "exclude-following"
}

/// `app.bsky.actor.defs#mutedWord`
public struct MutedWord: Sendable, Codable, Hashable {
  public var value: String
  public var targets: [MutedWordTarget]
  public var actorTarget: MutedWordActorTarget?
  /// ISO-8601 expiry; ignored after this instant.
  public var expiresAt: String?

  public init(
    value: String,
    targets: [MutedWordTarget] = [.content],
    actorTarget: MutedWordActorTarget? = nil,
    expiresAt: String? = nil
  ) {
    self.value = value
    self.targets = targets
    self.actorTarget = actorTarget
    self.expiresAt = expiresAt
  }
}

/// A labeler the viewer has configured, with labeler-scoped preferences.
public struct LabelerPrefs: Sendable, Codable, Hashable {
  public var did: String
  public var labels: [String: LabelPreference]

  public init(did: String, labels: [String: LabelPreference] = [:]) {
    self.did = did
    self.labels = labels
  }
}

/// The viewer's moderation preferences. Missing fields decode to defaults so
/// partial fixtures remain usable.
public struct ModerationPrefs: Sendable, Codable, Hashable {
  public var adultContentEnabled: Bool
  public var labels: [String: LabelPreference]
  public var labelers: [LabelerPrefs]
  public var mutedWords: [MutedWord]
  public var hiddenPosts: [String]

  public init(
    adultContentEnabled: Bool = false,
    labels: [String: LabelPreference] = [:],
    labelers: [LabelerPrefs] = [],
    mutedWords: [MutedWord] = [],
    hiddenPosts: [String] = []
  ) {
    self.adultContentEnabled = adultContentEnabled
    self.labels = labels
    self.labelers = labelers
    self.mutedWords = mutedWords
    self.hiddenPosts = hiddenPosts
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    adultContentEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .adultContentEnabled) ?? false
    labels = try container.decodeIfPresent([String: LabelPreference].self, forKey: .labels) ?? [:]
    labelers = try container.decodeIfPresent([LabelerPrefs].self, forKey: .labelers) ?? []
    mutedWords = try container.decodeIfPresent([MutedWord].self, forKey: .mutedWords) ?? []
    hiddenPosts = try container.decodeIfPresent([String].self, forKey: .hiddenPosts) ?? []
  }
}

/// Options passed to every `moderate*` entry point.
public struct ModerationOpts: Sendable, Codable {
  public var userDid: String
  public var prefs: ModerationPrefs
  /// Interpreted label definitions, keyed by labeler DID.
  public var labelDefs: [String: [LabelValueDefinition]]

  public init(
    userDid: String,
    prefs: ModerationPrefs,
    labelDefs: [String: [LabelValueDefinition]] = [:]
  ) {
    self.userDid = userDid
    self.prefs = prefs
    self.labelDefs = labelDefs
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    userDid = try container.decode(String.self, forKey: .userDid)
    prefs = try container.decode(ModerationPrefs.self, forKey: .prefs)
    labelDefs =
      try container.decodeIfPresent([String: [LabelValueDefinition]].self, forKey: .labelDefs)
      ?? [:]
  }
}

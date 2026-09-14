import Foundation

/// Where a cause originated. Mirrors the SDK's `ModerationCauseSource` union.
public enum ModerationCauseSource: Sendable, Hashable {
  /// The viewer's own state (muting, blocking, labeler, and so on).
  case user
  /// A moderation list the viewer subscribes to.
  case list(ListViewBasic)
  /// A labeler service the viewer has configured.
  case labeler(did: String)

  /// The list this source refers to, when it is a list source.
  public var list: ListViewBasic? {
    if case .list(let list) = self { return list }
    return nil
  }
}

/// Which surface a label applies to.
public enum LabelTarget: String, Sendable, Codable, Hashable {
  /// The account as a whole.
  case account
  /// The account's profile (self-profile record).
  case profile
  /// A unit of content (post, list, feed generator, ...).
  case content
}

/// A single moderation behavior slot in a `ModerationBehavior` table. Absent
/// keys are `nil`; `"blur"`, `"alert"`, and `"inform"` map to the cases below.
public enum ModerationBehaviorValue: String, Sendable, Codable, Hashable {
  case blur
  case alert
  case inform
}

/// The UI contexts the engine can produce behavior for.
public enum ModerationContext: String, Sendable, Codable, CaseIterable, Hashable {
  case profileList
  case profileView
  case avatar
  case banner
  case displayName
  case contentList
  case contentView
  case contentMedia
}

/// Per-context behavior for one label target. Keys not present behave as
/// `nil` (no behavior).
public struct ModerationBehavior: Sendable, Codable, Hashable {
  public var profileList: ModerationBehaviorValue?
  public var profileView: ModerationBehaviorValue?
  public var avatar: ModerationBehaviorValue?
  public var banner: ModerationBehaviorValue?
  public var displayName: ModerationBehaviorValue?
  public var contentList: ModerationBehaviorValue?
  public var contentView: ModerationBehaviorValue?
  public var contentMedia: ModerationBehaviorValue?

  public init(
    profileList: ModerationBehaviorValue? = nil,
    profileView: ModerationBehaviorValue? = nil,
    avatar: ModerationBehaviorValue? = nil,
    banner: ModerationBehaviorValue? = nil,
    displayName: ModerationBehaviorValue? = nil,
    contentList: ModerationBehaviorValue? = nil,
    contentView: ModerationBehaviorValue? = nil,
    contentMedia: ModerationBehaviorValue? = nil
  ) {
    self.profileList = profileList
    self.profileView = profileView
    self.avatar = avatar
    self.banner = banner
    self.displayName = displayName
    self.contentList = contentList
    self.contentView = contentView
    self.contentMedia = contentMedia
  }

  /// Reads the behavior registered for `context`, mirroring
  /// `ModerationBehavior[context]` in the SDK (an absent key yields nil).
  public subscript(context: ModerationContext) -> ModerationBehaviorValue? {
    switch context {
    case .profileList: return profileList
    case .profileView: return profileView
    case .avatar: return avatar
    case .banner: return banner
    case .displayName: return displayName
    case .contentList: return contentList
    case .contentView: return contentView
    case .contentMedia: return contentMedia
    }
  }

  /// The `{}` sentinel used when a label definition has no behaviors for a
  /// target.
  public static let noop = ModerationBehavior()
}

/// Behaviors applied for a blocked account, by context.
public enum BlockBehavior {
  public static let table: [ModerationContext: ModerationBehaviorValue] = [
    .profileList: .blur,
    .profileView: .alert,
    .avatar: .blur,
    .banner: .blur,
    .contentList: .blur,
    .contentView: .blur,
  ]
}

/// Behaviors applied for a muted account, by context.
public enum MuteBehavior {
  public static let table: [ModerationContext: ModerationBehaviorValue] = [
    .profileList: .inform,
    .profileView: .alert,
    .contentList: .blur,
    .contentView: .inform,
  ]
}

/// Behaviors applied for a post matching a mute word, by context.
public enum MuteWordBehavior {
  public static let table: [ModerationContext: ModerationBehaviorValue] = [
    .contentList: .blur,
    .contentView: .blur,
  ]
}

/// Behaviors applied for a hidden post, by context.
public enum HideBehavior {
  public static let table: [ModerationContext: ModerationBehaviorValue] = [
    .contentList: .blur,
    .contentView: .blur,
  ]
}

/// Label severity as defined by a labeler.
public enum LabelSeverity: String, Sendable, Codable, Hashable {
  case alert
  case inform
  case none
}

/// How a label's target is obscured.
public enum LabelBlurs: String, Sendable, Codable, Hashable {
  case content
  case media
  case none
}

/// What a label means for the viewer.
public enum LabelPreference: String, Sendable, Codable, Hashable {
  case hide
  case warn
  case ignore
}

/// Flags carried by a label definition.
public enum LabelFlag: String, Sendable, Codable, Hashable {
  /// The label cannot be overridden by an explicit content warning.
  case noOverride = "no-override"
  /// The label is never applied to the viewer's own content.
  case noSelf = "no-self"
  /// The label only applies when the viewer is unauthenticated.
  case unauthed
  /// The label is adult content, and is subject to the adult-content toggle.
  case adult
}

/// The type of a moderation cause.
public enum ModerationCauseType: String, Sendable, Hashable {
  case blocking
  case blockedBy = "blocked-by"
  case blockOther = "block-other"
  case muted
  case muteWord = "mute-word"
  case hidden
  case label
}

/// Which field of a labeler's definition defaults to `warn` when unspecified.
/// See `interpretLabelValueDefinition`.
public struct RawLabelValueDefinition: Sendable, Codable, Hashable {
  public var identifier: String
  public var severity: LabelSeverity
  public var blurs: LabelBlurs
  public var defaultSetting: LabelPreference?
  public var adultOnly: Bool
  public var noOverride: Bool

  public init(
    identifier: String,
    severity: LabelSeverity = .none,
    blurs: LabelBlurs = .none,
    defaultSetting: LabelPreference? = nil,
    adultOnly: Bool = false,
    noOverride: Bool = false
  ) {
    self.identifier = identifier
    self.severity = severity
    self.blurs = blurs
    self.defaultSetting = defaultSetting
    self.adultOnly = adultOnly
    self.noOverride = noOverride
  }
}

/// A label definition after interpretation: everything the engine needs to
/// evaluate a label, including the derived behavior table.
public struct LabelValueDefinition: Sendable, Codable, Hashable {
  public var identifier: String
  public var severity: LabelSeverity
  public var blurs: LabelBlurs
  public var defaultSetting: LabelPreference
  public var flags: [LabelFlag]
  public var behaviors: LabelTargetBehaviors
  public var definedBy: String
  public var configurable: Bool

  public init(
    identifier: String,
    severity: LabelSeverity,
    blurs: LabelBlurs,
    defaultSetting: LabelPreference,
    flags: [LabelFlag],
    behaviors: LabelTargetBehaviors,
    definedBy: String,
    configurable: Bool = true
  ) {
    self.identifier = identifier
    self.severity = severity
    self.blurs = blurs
    self.defaultSetting = defaultSetting
    self.flags = flags
    self.behaviors = behaviors
    self.definedBy = definedBy
    self.configurable = configurable
  }
}

/// Behavior tables for all three label targets.
public struct LabelTargetBehaviors: Sendable, Codable, Hashable {
  public var account: ModerationBehavior
  public var profile: ModerationBehavior
  public var content: ModerationBehavior

  public init(
    account: ModerationBehavior = .noop,
    profile: ModerationBehavior = .noop,
    content: ModerationBehavior = .noop
  ) {
    self.account = account
    self.profile = profile
    self.content = content
  }

  public subscript(target: LabelTarget) -> ModerationBehavior {
    switch target {
    case .account: return account
    case .profile: return profile
    case .content: return content
    }
  }
}

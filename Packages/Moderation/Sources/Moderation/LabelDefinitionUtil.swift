import Foundation

/// Custom (labeler-defined) label values must be lowercase words or
/// hyphenated lowercase words, e.g. `self-ghi`. A computed property because
/// `Regex` is not `Sendable` and cannot be a global constant.
public var customLabelValueRegex: Regex<Substring> { /^[a-z-]+$/ }

/// A `com.atproto.label.defs#labelValueDefinition` decoded from a labeler's
/// service policies. Kept separate from ``LabelValueDefinition`` because the
/// raw shape is optional-heavy and needs validation before interpretation.
public struct LabelValueDefinitionRaw: Sendable, Codable, Hashable {
  public var identifier: String?
  public var severity: LabelSeverity?
  public var blurs: LabelBlurs?
  public var defaultSetting: LabelPreference?
  public var adultOnly: Bool?
  public var noOverride: Bool?

  public init(
    identifier: String? = nil,
    severity: LabelSeverity? = nil,
    blurs: LabelBlurs? = nil,
    defaultSetting: LabelPreference? = nil,
    adultOnly: Bool? = nil,
    noOverride: Bool? = nil
  ) {
    self.identifier = identifier
    self.severity = severity
    self.blurs = blurs
    self.defaultSetting = defaultSetting
    self.adultOnly = adultOnly
    self.noOverride = noOverride
  }

  /// Mirrors `com.atproto.label.defs.labelValueDefinition.matches`: required
  /// fields must be present so an unrelated object is not silently accepted.
  public var isValid: Bool {
    identifier != nil && severity != nil && blurs != nil
  }
}

/// Interprets a labeler's definition into the shape the engine evaluates.
/// `adultOnly` and `noOverride` only affect the `adult` flag here; both the
/// adult-content toggle and `no-override` are re-checked at decision time.
public func interpretLabelValueDefinition(
  _ def: LabelValueDefinitionRaw,
  definedBy: String
) -> LabelValueDefinition {
  let behaviors = interpreterBehaviors(
    blurs: def.blurs,
    alertOrInform: alertOrInform(for: def.severity ?? .none),
    adultOnly: def.adultOnly ?? false
  )

  // Defaults to `warn` unless the labeler explicitly asked for `hide`/`ignore`.
  var defaultSetting: LabelPreference = .warn
  if let setting = def.defaultSetting, setting == .hide || setting == .ignore {
    defaultSetting = setting
  }

  var flags: [LabelFlag] = [.noSelf]
  if def.adultOnly ?? false {
    flags.append(.adult)
  }

  return LabelValueDefinition(
    identifier: def.identifier ?? "",
    severity: def.severity ?? .none,
    blurs: def.blurs ?? .none,
    defaultSetting: defaultSetting,
    flags: flags,
    behaviors: behaviors,
    definedBy: definedBy,
    configurable: true
  )
}

/// Maps a definition's severity onto the alert/inform behavior slot.
private func alertOrInform(for severity: LabelSeverity) -> ModerationBehaviorValue? {
  switch severity {
  case .alert: return .alert
  case .inform: return .inform
  default: return nil
  }
}

/// Builds the per-target behavior table implied by how a label blurs.
private func interpreterBehaviors(
  blurs: LabelBlurs?,
  alertOrInform: ModerationBehaviorValue?,
  adultOnly: Bool
) -> LabelTargetBehaviors {
  var behaviors = LabelTargetBehaviors()
  guard let blurs else { return behaviors }
  switch blurs {
  case .content:
    // target=account, blurs=content
    behaviors.account.profileList = alertOrInform
    behaviors.account.profileView = alertOrInform
    behaviors.account.contentList = .blur
    behaviors.account.contentView = adultOnly ? .blur : alertOrInform
    // target=profile, blurs=content
    behaviors.profile.profileList = alertOrInform
    behaviors.profile.profileView = alertOrInform
    // target=content, blurs=content
    behaviors.content.contentList = .blur
    behaviors.content.contentView = adultOnly ? .blur : alertOrInform
  case .media:
    // target=account, blurs=media
    behaviors.account.profileList = alertOrInform
    behaviors.account.profileView = alertOrInform
    behaviors.account.avatar = .blur
    behaviors.account.banner = .blur
    // target=profile, blurs=media
    behaviors.profile.profileList = alertOrInform
    behaviors.profile.profileView = alertOrInform
    behaviors.profile.avatar = .blur
    behaviors.profile.banner = .blur
    // target=content, blurs=media
    behaviors.content.contentMedia = .blur
  case .none:
    // target=account, blurs=none
    behaviors.account.profileList = alertOrInform
    behaviors.account.profileView = alertOrInform
    behaviors.account.contentList = alertOrInform
    behaviors.account.contentView = alertOrInform
    // target=profile, blurs=none
    behaviors.profile.profileList = alertOrInform
    behaviors.profile.profileView = alertOrInform
    // target=content, blurs=none
    behaviors.content.contentList = alertOrInform
    behaviors.content.contentView = alertOrInform
  }
  return behaviors
}

/// Interprets every valid definition in a labeler's raw definition list.
public func interpretLabelValueDefinitions(
  _ defs: [LabelValueDefinitionRaw],
  definedBy: String
) -> [LabelValueDefinition] {
  defs.filter(\.isValid).map { interpretLabelValueDefinition($0, definedBy: definedBy) }
}

/// A labeler view's policies, which carry the labeler's custom definitions.
public struct LabelerViewPolicies: Sendable, Codable, Hashable {
  public var labelValueDefinitions: [LabelValueDefinitionRaw]?

  public init(labelValueDefinitions: [LabelValueDefinitionRaw]? = nil) {
    self.labelValueDefinitions = labelValueDefinitions
  }
}

/// The subset of a labeler view the engine reads.
public struct LabelerView: Sendable, Codable, Hashable {
  public var creator: ProfileViewBasic
  public var policies: LabelerViewPolicies?

  public init(creator: ProfileViewBasic, policies: LabelerViewPolicies? = nil) {
    self.creator = creator
    self.policies = policies
  }

  /// Interprets this labeler's custom label definitions.
  public var interpretedLabelValueDefinitions: [LabelValueDefinition] {
    interpretLabelValueDefinitions(
      policies?.labelValueDefinitions ?? [],
      definedBy: creator.did
    )
  }
}

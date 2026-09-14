import Foundation

/// One reason a piece of content is moderated, with its source and priority
/// (lower sorts first).
public struct ModerationCause: Sendable, Hashable {
  public var type: ModerationCauseType
  public var source: ModerationCauseSource
  public var priority: Int
  /// Set when ``ModerationDecision/downgrade()`` has been applied, which
  /// demotes the cause to a filter-only signal.
  public var downgraded: Bool?
  /// Present on `label` causes.
  public var label: Label?
  public var labelDef: LabelValueDefinition?
  public var target: LabelTarget?
  public var setting: LabelPreference?
  public var behavior: ModerationBehavior?
  public var noOverride: Bool?
  /// Present on `mute-word` causes.
  public var matches: [MutedWordMatch]?

  public init(
    type: ModerationCauseType,
    source: ModerationCauseSource,
    priority: Int,
    downgraded: Bool? = nil,
    label: Label? = nil,
    labelDef: LabelValueDefinition? = nil,
    target: LabelTarget? = nil,
    setting: LabelPreference? = nil,
    behavior: ModerationBehavior? = nil,
    noOverride: Bool? = nil,
    matches: [MutedWordMatch]? = nil
  ) {
    self.type = type
    self.source = source
    self.priority = priority
    self.downgraded = downgraded
    self.label = label
    self.labelDef = labelDef
    self.target = target
    self.setting = setting
    self.behavior = behavior
    self.noOverride = noOverride
    self.matches = matches
  }
}

/// Relative severity of a label's behavior table, used to pick a priority.
private enum ModerationBehaviorSeverity {
  case high
  case medium
  case low
}

/// The result of running the engine over one subject: the subject's identity
/// plus every cause found.
public struct ModerationDecision: Sendable {
  public var did = ""
  public var isMe = false
  public var causes: [ModerationCause] = []

  public init() {}

  /// Merges several decisions into one. Identity comes from the first
  /// decision; causes are concatenated in the order the decisions were given.
  public static func merge(_ decisions: [ModerationDecision?]) -> ModerationDecision {
    let decisions = decisions.compactMap { $0 }
    var decision = ModerationDecision()
    if let first = decisions.first {
      decision.did = first.did
      decision.isMe = first.isMe
    }
    decision.causes = decisions.flatMap(\.causes)
    return decision
  }

  /// Marks every cause as downgraded and returns the decision.
  @discardableResult
  public mutating func downgrade() -> ModerationDecision {
    for index in causes.indices {
      causes[index].downgraded = true
    }
    return self
  }

  /// Non-mutating variant: returns a copy with every cause downgraded. Used
  /// where a decision is produced inline and immediately merged.
  public func downgraded() -> ModerationDecision {
    var copy = self
    return copy.downgrade()
  }

  /// Whether the subject is blocked (or blocks the viewer).
  public var blocked: Bool { blockCause != nil }
  /// Whether the subject is muted.
  public var muted: Bool { muteCause != nil }

  public var blockCause: ModerationCause? {
    causes.first {
      $0.type == .blocking || $0.type == .blockedBy || $0.type == .blockOther
    }
  }

  public var muteCause: ModerationCause? {
    causes.first { $0.type == .muted }
  }

  public var labelCauses: [ModerationCause] {
    causes.filter { $0.type == .label }
  }

  /// Projects the decision for one UI context.
  public func ui(_ context: ModerationContext) -> ModerationUI {
    var ui = ModerationUI()
    for cause in causes {
      switch cause.type {
      case .blocking, .blockedBy, .blockOther:
        applyBlockCause(cause, context: context, to: &ui)
      case .muted:
        if isMe { continue }
        if context == .profileList || context == .contentList {
          ui.filters.append(cause)
        }
        if cause.downgraded != true {
          apply(behavior: MuteBehavior.table[context], cause: cause, to: &ui)
        }
      case .muteWord:
        if isMe { continue }
        if context == .contentList {
          ui.filters.append(cause)
        }
        if cause.downgraded != true {
          apply(behavior: MuteWordBehavior.table[context], cause: cause, to: &ui)
        }
      case .hidden:
        if context == .profileList || context == .contentList {
          ui.filters.append(cause)
        }
        if cause.downgraded != true {
          apply(behavior: HideBehavior.table[context], cause: cause, to: &ui)
        }
      case .label:
        applyLabelCause(cause, context: context, to: &ui)
      }
    }
    ui.filters.sort { $0.priority < $1.priority }
    ui.blurs.sort { $0.priority < $1.priority }
    return ui
  }

  /// Block causes filter list contexts and, unless downgraded, blur or alert
  /// on the surfaces `BLOCK_BEHAVIOR` assigns.
  private func applyBlockCause(
    _ cause: ModerationCause,
    context: ModerationContext,
    to ui: inout ModerationUI
  ) {
    if isMe { return }
    if context == .profileList || context == .contentList {
      ui.filters.append(cause)
    }
    guard cause.downgraded != true else { return }
    switch BlockBehavior.table[context] {
    case .blur:
      ui.noOverride = true
      ui.blurs.append(cause)
    case .alert:
      ui.alerts.append(cause)
    case .inform:
      ui.informs.append(cause)
    default:
      break
    }
  }

  /// Label causes filter list contexts when their setting is `hide`, and
  /// otherwise blur/alert/inform per the label definition's behavior table.
  private func applyLabelCause(
    _ cause: ModerationCause,
    context: ModerationContext,
    to ui: inout ModerationUI
  ) {
    if context == .profileList, cause.target == .account {
      if cause.setting == .hide, !isMe {
        ui.filters.append(cause)
      }
    } else if context == .contentList, cause.target == .account || cause.target == .content {
      if cause.setting == .hide, !isMe {
        ui.filters.append(cause)
      }
    }
    guard cause.downgraded != true else { return }
    let behavior = cause.behavior?[context]
    if behavior == .blur {
      ui.blurs.append(cause)
      if cause.noOverride == true, !isMe {
        ui.noOverride = true
      }
    } else if behavior == .alert {
      ui.alerts.append(cause)
    } else if behavior == .inform {
      ui.informs.append(cause)
    }
  }

  private func apply(
    behavior: ModerationBehaviorValue?,
    cause: ModerationCause,
    to ui: inout ModerationUI
  ) {
    switch behavior {
    case .blur: ui.blurs.append(cause)
    case .alert: ui.alerts.append(cause)
    case .inform: ui.informs.append(cause)
    default: break
    }
  }

  public mutating func setDid(_ did: String) {
    self.did = did
  }

  public mutating func setIsMe(_ isMe: Bool) {
    self.isMe = isMe
  }

  public mutating func addHidden(_ hidden: Bool) {
    if hidden {
      causes.append(ModerationCause(type: .hidden, source: .user, priority: 6))
    }
  }

  public mutating func addMutedWord(_ matches: [MutedWordMatch]?) {
    if let matches, !matches.isEmpty {
      causes.append(
        ModerationCause(type: .muteWord, source: .user, priority: 6, matches: matches))
    }
  }

  public mutating func addBlocking(_ blocking: Bool?) {
    if blocking == true {
      causes.append(ModerationCause(type: .blocking, source: .user, priority: 3))
    }
  }

  public mutating func addBlockingByList(_ list: ListViewBasic?) {
    guard let list else { return }
    causes.append(ModerationCause(type: .blocking, source: .list(list), priority: 3))
  }

  public mutating func addBlockedBy(_ blockedBy: Bool?) {
    if blockedBy == true {
      causes.append(ModerationCause(type: .blockedBy, source: .user, priority: 4))
    }
  }

  public mutating func addBlockOther(_ blockOther: Bool?) {
    if blockOther == true {
      causes.append(ModerationCause(type: .blockOther, source: .user, priority: 4))
    }
  }

  /// Adds a label cause if the label is understood, configured, and not
  /// ignored by the viewer's preferences.
  public mutating func addLabel(
    target: LabelTarget,
    label: Label,
    opts: ModerationOpts
  ) {
    let knownLabelDef = labels[label.val]
    let labelDef: LabelValueDefinition?
    if label.val.wholeMatch(of: customLabelValueRegex) != nil {
      labelDef =
        opts.labelDefs[label.src]?.first { $0.identifier == label.val } ?? knownLabelDef
    } else {
      labelDef = knownLabelDef
    }
    guard let labelDef, let resolution = resolveLabeler(
      label: label, labelDef: labelDef, opts: opts
    ) else { return }
    let (isSelf, labeler, labelPref) = resolution

    // ignore labels the user has asked to ignore
    if labelPref == .ignore {
      return
    }
    // ignore 'unauthed' labels when the user is authed
    if labelDef.flags.contains(.unauthed), !opts.userDid.isEmpty {
      return
    }

    let adultContentDisabled =
      labelDef.flags.contains(.adult) && !opts.prefs.adultContentEnabled
    let priority = labelPriority(
      labelDef: labelDef,
      target: target,
      labelPref: labelPref,
      adultContentDisabled: adultContentDisabled
    )
    let noOverride = labelDef.flags.contains(.noOverride) || adultContentDisabled

    causes.append(
      ModerationCause(
        type: .label,
        source: isSelf || labeler == nil ? .user : .labeler(did: labeler?.did ?? ""),
        priority: priority,
        label: label,
        labelDef: labelDef,
        target: target,
        setting: labelPref,
        behavior: labelDef.behaviors[target],
        noOverride: noOverride
      ))
  }

  /// Applies the labeler-configuration and preference rules, returning the
  /// source fields and resolved preference, or nil when the label is skipped.
  private func resolveLabeler(
    label: Label,
    labelDef: LabelValueDefinition,
    opts: ModerationOpts
  ) -> (isSelf: Bool, labeler: LabelerPrefs?, labelPref: LabelPreference)? {
    let isSelf = label.src == did
    let labeler = isSelf ? nil : opts.prefs.labelers.first { $0.did == label.src }
    if !isSelf, labeler == nil {
      // skip labelers not configured by the user
      return nil
    }
    if isSelf, labelDef.flags.contains(.noSelf) {
      // skip self-labels that aren't supported
      return nil
    }

    // establish the label preference for interpretation
    var labelPref: LabelPreference = labelDef.defaultSetting
    if !labelDef.configurable {
      labelPref = labelDef.defaultSetting
    } else if labelDef.flags.contains(.adult), !opts.prefs.adultContentEnabled {
      labelPref = .hide
    } else if let scoped = labeler?.labels[labelDef.identifier] {
      labelPref = scoped
    } else if let global = opts.prefs.labels[labelDef.identifier] {
      labelPref = global
    }
    return (isSelf, labeler, labelPref)
  }

  /// Lower priorities sort first. `no-override` labels and adult labels while
  /// adult content is disabled are most severe, then explicit `hide`
  /// preferences, then the label's own behavior severity.
  private func labelPriority(
    labelDef: LabelValueDefinition,
    target: LabelTarget,
    labelPref: LabelPreference,
    adultContentDisabled: Bool
  ) -> Int {
    if labelDef.flags.contains(.noOverride) || adultContentDisabled {
      return 1
    }
    if labelPref == .hide {
      return 2
    }
    switch measureModerationBehaviorSeverity(labelDef.behaviors[target]) {
    case .high:
      // blurring profile view or content view
      return 5
    case .medium:
      // blurring content list or content media
      return 7
    case .low:
      // blurring avatar, adding alerts
      return 8
    }
  }

  public mutating func addMuted(_ muted: Bool?) {
    if muted == true {
      causes.append(ModerationCause(type: .muted, source: .user, priority: 6))
    }
  }

  public mutating func addMutedByList(_ list: ListViewBasic?) {
    guard let list else { return }
    causes.append(ModerationCause(type: .muted, source: .list(list), priority: 6))
  }
}

/// Ranks a behavior table so `addLabel` can pick a priority.
private func measureModerationBehaviorSeverity(
  _ behavior: ModerationBehavior
) -> ModerationBehaviorSeverity {
  if behavior.profileView == .blur || behavior.contentView == .blur {
    return .high
  }
  if behavior.contentList == .blur || behavior.contentMedia == .blur {
    return .medium
  }
  return .low
}

import Foundation

import Moderation

/// One configurable content-label row.
///
/// Port of the derivation in
/// `src/components/moderation/LabelPreference.tsx`
/// (`LabelerLabelPreference`), which is where the app turns a label definition
/// plus the viewer's stored preferences into what the toggle group shows.
///
/// The row carries the *derived* pref, not the stored one: an adult label with
/// adult content disabled is forced to `hide`, and a label that cannot warn
/// (`blurs: none` + `severity: none`) with a stored `warn` is coerced to
/// `ignore`. Those coercions are what the RN component renders, so the port
/// derives them here rather than in the view.
public struct ContentLabelRow: Sendable, Hashable {
  /// The label's identifier, e.g. `porn` or a labeler-defined value.
  public let identifier: String
  /// The definition this row configures.
  public let definition: LabelValueDefinition
  /// The labeler this row is scoped to, or nil for a global label.
  public let labelerDid: String?
  /// The viewer's stored pref, before any forcing.
  public let savedPreference: LabelPreference?
  /// The pref the row should render.
  public let preference: LabelPreference
  /// Whether the row is configurable here at all.
  public let configurable: Bool
  /// True when the row is disabled because adult content is off.
  public let adultDisabled: Bool
  /// True when the label is a global (app-defined) label, which is configured
  /// on the moderation screen rather than on a labeler's page.
  public let isGlobalLabel: Bool
  /// Whether the "warn" option should be offered.
  public let canWarn: Bool
  /// True when the row is shown but read-only, with an explanatory notice.
  public let showsStaticValue: Bool

  public init(
    identifier: String, definition: LabelValueDefinition, labelerDid: String?,
    savedPreference: LabelPreference?, preference: LabelPreference, configurable: Bool,
    adultDisabled: Bool, isGlobalLabel: Bool, canWarn: Bool, showsStaticValue: Bool
  ) {
    self.identifier = identifier
    self.definition = definition
    self.labelerDid = labelerDid
    self.savedPreference = savedPreference
    self.preference = preference
    self.configurable = configurable
    self.adultDisabled = adultDisabled
    self.isGlobalLabel = isGlobalLabel
    self.canWarn = canWarn
    self.showsStaticValue = showsStaticValue
  }

  /// The values the toggle group offers for this row.
  public var options: [LabelPreference] {
    canWarn ? [.ignore, .warn, .hide] : [.ignore, .hide]
  }
}

/// One section of the content-labels screen: a labeler and its rows.
public struct ContentLabelSection: Sendable, Hashable {
  /// The labeler's did.
  public let labelerDid: String
  /// The labeler's display title.
  public let title: String
  /// The labeler's handle, when known.
  public let handle: String?
  /// True when the viewer is subscribed. Unsubscribed labelers' label rows are
  /// rendered disabled.
  public let isSubscribed: Bool
  /// The labeler's own custom definitions, interpreted.
  public let customDefinitions: [LabelValueDefinition]
  /// The rows, in the order the labeler declared its label values.
  public let rows: [ContentLabelRow]

  public init(
    labelerDid: String, title: String, handle: String? = nil, isSubscribed: Bool,
    customDefinitions: [LabelValueDefinition], rows: [ContentLabelRow]
  ) {
    self.labelerDid = labelerDid
    self.title = title
    self.handle = handle
    self.isSubscribed = isSubscribed
    self.customDefinitions = customDefinitions
    self.rows = rows
  }
}

/// Derives the content-label settings model.
///
/// Port of the label-list construction in
/// `src/screens/Profile/Sections/Labels.tsx` (`labelValues`) combined with the
/// per-row derivation in `LabelPreference.tsx`. The RN screen builds the list
/// from `labelerInfo.policies.labelValues` (deduped), looks each up against the
/// labeler's custom definitions and the global `LABELS` table, and keeps only
/// configurable definitions; the port does the same and additionally exposes
/// the pre-adjustment saved pref so a caller can render "changed from default".
public enum ContentLabels {

  /// Builds the rows for one labeler.
  ///
  /// - Parameters:
  ///   - labelerDid: the labeler whose rows these are.
  ///   - labelValues: the values the labeler declares it publishes, in order.
  ///     Deduped before lookup, exactly as RN does with `arr.indexOf(val) === i`.
  ///   - customDefinitions: the labeler's interpreted custom definitions.
  ///   - isSubscribed: whether the viewer is subscribed; when false, rows are
  ///     rendered non-configurable.
  ///   - prefs: the viewer's moderation preferences.
  public static func rows(
    labelerDid: String,
    labelValues: [String],
    customDefinitions: [LabelValueDefinition],
    isSubscribed: Bool = true,
    prefs: ModerationPrefs
  ) -> [ContentLabelRow] {
    var seen = Set<String>()
    let ordered = labelValues.filter { seen.insert($0).inserted }
    return ordered.compactMap { value in
      guard let definition = lookupLabelValueDefinition(value, customDefinitions: customDefinitions),
        definition.configurable
      else { return nil }
      return row(
        definition: definition, labelerDid: labelerDid, isSubscribed: isSubscribed, prefs: prefs)
    }
  }

  /// Derives a single row.
  ///
  /// - Note: the RN component distinguishes "global" labels by
  ///   `!labelDefinition.definedBy`. The Swift `LabelValueDefinition` always
  ///   carries a `definedBy` (the global table sets it to `"app.bsky"`), so the
  ///   port treats a definition whose `definedBy` is the app as global. This is
  ///   the one place the port had to re-express the RN test rather than copy
  ///   it.
  public static func row(
    definition: LabelValueDefinition,
    labelerDid: String?,
    isSubscribed: Bool = true,
    prefs: ModerationPrefs
  ) -> ContentLabelRow {
    let identifier = definition.identifier
    let isGlobalLabel = definition.definedBy == "app.bsky"

    let savedPreference = savedPreference(
      identifier: identifier, labelerDid: labelerDid, isGlobalLabel: isGlobalLabel, prefs: prefs)

    // RN: `pref = mutateVariables?.visibility ?? savedPref ?? defaultSetting ?? 'warn'`.
    // The Swift port has no in-flight mutation variables, so the fallback chain
    // stops at the definition's default.
    let pref = savedPreference ?? definition.defaultSetting

    let canWarn = !(definition.blurs == .none && definition.severity == .none)
    let adultOnly = definition.flags.contains(.adult)
    let adultDisabled = adultOnly && !prefs.adultContentEnabled

    // Global labels are configured on the moderation screen, and an adult label
    // with adult content off cannot be changed here.
    let cantConfigure = isGlobalLabel || adultDisabled
    let configurable = isSubscribed && !cantConfigure

    var adjusted = pref
    if adultDisabled {
      adjusted = .hide
    } else if !canWarn && pref == .warn {
      adjusted = .ignore
    }

    return ContentLabelRow(
      identifier: identifier,
      definition: definition,
      labelerDid: labelerDid,
      savedPreference: savedPreference,
      preference: adjusted,
      configurable: configurable,
      adultDisabled: adultDisabled,
      isGlobalLabel: isGlobalLabel,
      canWarn: canWarn,
      // RN shows a static value (no toggle buttons) when the row cannot be
      // configured but is still visible, which is `cantConfigure`.
      showsStaticValue: cantConfigure)
  }

  /// Reads the stored pref for a label.
  ///
  /// Port of the `savedPref` lookup: a non-global label scoped to a labeler
  /// reads that labeler's `labels` map, everything else reads the global map.
  public static func savedPreference(
    identifier: String, labelerDid: String?, isGlobalLabel: Bool, prefs: ModerationPrefs
  ) -> LabelPreference? {
    if let labelerDid, !isGlobalLabel {
      return prefs.labelers.first { $0.did == labelerDid }?.labels[identifier]
    }
    return prefs.labels[identifier]
  }

  /// The global content labels the moderation screen shows, in RN's order
  /// (`porn`, `sexual`, `graphic-media`, `nudity`).
  ///
  /// Port of the `GlobalLabelPreference` list in
  /// `src/screens/Moderation/index.tsx`.
  public static let globalLabelIdentifiers = ["porn", "sexual", "graphic-media", "nudity"]

  /// Builds the global rows, which are shown only while adult content is on.
  public static func globalRows(prefs: ModerationPrefs) -> [ContentLabelRow] {
    globalLabelIdentifiers.compactMap { identifier in
      guard let definition = labels[identifier] else { return nil }
      return row(definition: definition, labelerDid: nil, prefs: prefs)
    }
  }

  /// Whether the global content label block should render at all.
  ///
  /// Port of the `adultContentEnabled &&` guard around the global label rows.
  public static func showsGlobalRows(prefs: ModerationPrefs) -> Bool {
    prefs.adultContentEnabled
  }

  /// Looks a label value up against a labeler's custom definitions, then the
  /// global table. Port of `lookupLabelValueDefinition`: a `!`-prefixed value
  /// is never looked up in the custom set.
  public static func lookupLabelValueDefinition(
    _ value: String, customDefinitions: [LabelValueDefinition]?
  ) -> LabelValueDefinition? {
    if !value.hasPrefix("!"), let customDefinitions,
      let match = customDefinitions.first(where: { $0.identifier == value })
    {
      return match
    }
    return labels[value]
  }

  /// The labels that are user-facing: system labels (`!`-prefixed) and the
  /// viewer's own `bot` self-label are filtered out.
  ///
  /// Port of `filterUserFacingLabels`.
  public static func filterUserFacingLabels(
    _ values: [Label], currentAccountDid: String?
  ) -> [Label] {
    values.filter { label in
      guard !label.val.hasPrefix("!") else { return false }
      if label.val == "bot", label.src == currentAccountDid { return false }
      return true
    }
  }
}

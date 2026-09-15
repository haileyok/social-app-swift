import Foundation
import Moderation
import Preferences

/// The label definitions the app ships, re-exported under one name.
///
/// `Moderation` declares this as a module-level `labels` constant; naming it
/// here keeps the call sites readable and gives the matrix one import. Not
/// `private` because it is a default argument value, which is evaluated at the
/// call site.
public let globalLabelDefinitions: [String: LabelValueDefinition] = labels

/// The inputs the label matrix derivation reads.
///
/// The engine's interpreted `Preferences` type has no public initializer
/// (it is built only by the hydration path), so the matrix takes exactly the
/// two values it needs. That also states the dependency plainly: the row set is
/// a function of the adult-content flag and the stored visibility map.
public struct ContentLabelInputs: Sendable, Equatable {
  /// `moderationPrefs.adultContentEnabled` - gates the whole row set.
  public let adultContentEnabled: Bool
  /// `moderationPrefs.labels`, keyed by label value.
  public let labels: [String: String]
  /// Per-labeler overrides, keyed by labeler DID.
  public let labelerLabels: [String: [String: String]]

  public init(
    adultContentEnabled: Bool,
    labels: [String: String] = [:],
    labelerLabels: [String: [String: String]] = [:]
  ) {
    self.adultContentEnabled = adultContentEnabled
    self.labels = labels
    self.labelerLabels = labelerLabels
  }

  /// Extracts the inputs from the engine's interpreted preferences.
  public static func from(_ preferences: Preferences) -> ContentLabelInputs {
    var labelerLabels: [String: [String: String]] = [:]
    for labeler in preferences.moderationPrefs.labelers {
      labelerLabels[labeler.did] = labeler.labels
    }
    return ContentLabelInputs(
      adultContentEnabled: preferences.moderationPrefs.adultContentEnabled,
      labels: preferences.moderationPrefs.labels,
      labelerLabels: labelerLabels)
  }
}

/// One row of the content & media label matrix.
///
/// Port of `GlobalLabelPreference` in `components/moderation/LabelPreference.tsx`
/// reduced to data: the label's identity, the copy the row shows, the current
/// visibility, and the three options the segmented control offers.
///
/// The matrix is derived as `label definitions x current prefs`, which is the
/// whole point of the derivation: the set of rows is the *permitted* global
/// labels, and each row's selection is the stored preference or the label's
/// default.
public struct LabelPreferenceRow: Sendable, Equatable, Hashable {
  /// The label value, e.g. `porn`. This is the `key` written to
  /// `setContentLabelPref`.
  public let identifier: String
  /// The row's display name.
  public let name: String
  /// The row's description.
  public let description: String
  /// The currently selected visibility.
  public let selected: LabelVisibility
  /// Whether the toggle is disabled (adult content off).
  public let isDisabled: Bool

  public init(
    identifier: String,
    name: String,
    description: String,
    selected: LabelVisibility,
    isDisabled: Bool = false
  ) {
    self.identifier = identifier
    self.name = name
    self.description = description
    self.selected = selected
    self.isDisabled = isDisabled
  }
}

/// The three visibility settings a label preference can take.
///
/// The stored wire values are `ignore`, `warn` and `hide`; RN's UI labels them
/// "Show", "Warn" and "Hide", and the `show` value is a legacy spelling the
/// engine normalizes to `ignore` on read.
public enum LabelVisibility: String, Sendable, Equatable, CaseIterable {
  case ignore
  case warn
  case hide

  /// The label RN renders on the segmented control.
  public var title: String {
    switch self {
    case .ignore: return "Show"
    case .warn: return "Warn"
    case .hide: return "Hide"
    }
  }

  /// The wire value written to the preference. `show` is the legacy spelling
  /// RN's mutations still send for `ignore`.
  public var storedValue: String {
    switch self {
    case .ignore: return "show"
    case .warn: return "warn"
    case .hide: return "hide"
    }
  }

  /// Normalizes a stored value onto a case.
  ///
  /// Mirrors the engine's `normalizeVisibility` (`show` -> `ignore`) and
  /// degrades anything unknown to `warn`, which is RN's fallback for an
  /// unset preference.
  public static func normalize(_ stored: String) -> LabelVisibility {
    switch stored {
    case "ignore", "show": return .ignore
    case "hide": return .hide
    default: return .warn
    }
  }
}

/// The label matrix derivation, ported from the moderation screen's label list.
///
/// The rows RN renders are, in order, `porn`, `sexual`, `graphic-media`,
/// `nudity` (see `screens/Moderation/index.tsx`), and they are shown only when
/// adult content is enabled. Each row's selection is the stored global
/// preference, falling back to the label definition's `defaultSetting`.
public enum LabelPreferenceMatrix {

  /// The label values the content & media screen offers, in screen order.
  ///
  /// The values match the `LABELS` keys RN indexes
  /// (`LABELS.porn`, `LABELS.sexual`, `LABELS['graphic-media']`,
  /// `LABELS.nudity`).
  public static let configurableIdentifiers = ["porn", "sexual", "graphic-media", "nudity"]

  /// The copy RN shows for each configurable label, from
  /// `useGlobalLabelStrings`.
  public static let strings: [String: (name: String, description: String)] = [
    "porn": ("Adult Content", "Explicit sexual images."),
    "sexual": ("Sexually Suggestive", "Does not include nudity."),
    "nudity": ("Non-sexual Nudity", "E.g. artistic nudes."),
    "graphic-media": ("Graphic Media", "Explicit or potentially disturbing media."),
  ]

  /// Derives the matrix rows.
  ///
  /// - Parameters:
  ///   - inputs: the adult-content flag and the stored visibility map.
  ///   - definitions: the label definitions to draw defaults from. Defaults to
  ///     the engine's global definitions.
  /// - Returns: the rows, in screen order. Empty when adult content is off,
  ///   which is exactly what RN renders (`{adultContentEnabled && ...}`).
  public static func rows(
    for inputs: ContentLabelInputs,
    definitions: [String: LabelValueDefinition] = globalLabelDefinitions
  ) -> [LabelPreferenceRow] {
    guard inputs.adultContentEnabled else { return [] }
    return configurableIdentifiers.compactMap { identifier in
      guard let definition = definitions[identifier] else { return nil }
      let copy = strings[identifier]
        ?? (name: identifier, description: "Labeled \"\(identifier)\"")
      let stored = inputs.labels[identifier]
      let selected = stored.map(LabelVisibility.normalize)
        ?? LabelVisibility.normalize(definition.defaultSetting.rawValue)
      return LabelPreferenceRow(
        identifier: identifier,
        name: copy.name,
        description: copy.description,
        selected: selected)
    }
  }

  /// Convenience over the engine's interpreted preferences.
  public static func rows(
    for preferences: Preferences,
    definitions: [String: LabelValueDefinition] = globalLabelDefinitions
  ) -> [LabelPreferenceRow] {
    rows(for: ContentLabelInputs.from(preferences), definitions: definitions)
  }

  /// The rows for a specific labeler's definitions, which is how the per-labeler
  /// screen builds the same matrix.
  ///
  /// Only definitions the labeler marks `configurable` are offered, mirroring
  /// `interpretLabelValueDefinitions`'s filter.
  public static func labelerRows(
    for inputs: ContentLabelInputs,
    labelerDID: String,
    definitions: [LabelValueDefinition]
  ) -> [LabelPreferenceRow] {
    let overrides = inputs.labelerLabels[labelerDID] ?? [:]
    let isDisabled = !inputs.adultContentEnabled
    return definitions
      .filter { $0.configurable && $0.identifier != "!hide" && $0.identifier != "!warn" }
      .map { definition in
        let stored = overrides[definition.identifier]
        return LabelPreferenceRow(
          identifier: definition.identifier,
          name: definition.identifier,
          description: "Labeled \"\(definition.identifier)\"",
          selected: stored.map(LabelVisibility.normalize)
            ?? LabelVisibility.normalize(definition.defaultSetting.rawValue),
          isDisabled: isDisabled)
      }
  }

  /// The full label preference change a row toggle produces: the label key,
  /// the wire visibility, and the labeler scope (`nil` for the global matrix).
  public struct Change: Sendable, Equatable {
    public let key: String
    public let visibility: String
    public let labelerDID: String?

    public init(key: String, visibility: String, labelerDID: String? = nil) {
      self.key = key
      self.visibility = visibility
      self.labelerDID = labelerDID
    }
  }

  /// Builds the change for a global row selection.
  ///
  /// `setContentLabelPref` also double-writes the legacy aliases
  /// (`nsfw`/`gore`/`suggestive`); that is the engine's job and is asserted
  /// through the engine in the tests, not re-implemented here.
  public static func globalChange(
    identifier: String, visibility: LabelVisibility
  ) -> Change {
    Change(
      key: identifier, visibility: visibility.storedValue, labelerDID: nil)
  }

  /// The display-only option list for a row: Show, Warn, Hide.
  public static let options: [LabelVisibility] = [.ignore, .warn, .hide]
}

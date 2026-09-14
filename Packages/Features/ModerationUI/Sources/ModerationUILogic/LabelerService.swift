import Foundation

import ATProtoClient
import Lexicons
import Moderation
import QueryStore
// A plain module import is used for the Preferences helpers. The module also
// exports a `Preferences` struct and its own `LabelPreference` typealias
// (`String`), so the Moderation `LabelPreference` enum is qualified explicitly
// at each use site rather than left ambiguous.
import Preferences
import SwiftAtproto

/// True when `did` is a per-country regional moderation authority the app
/// configures automatically and the viewer cannot configure (port of
/// `isNonConfigurableModerationAuthority`).
///
/// The Swift port derives the set from ``CountryLabelers``, which already
/// carries every regional did the RN list holds.
public func isNonConfigurableModerationAuthority(_ did: String) -> Bool {
  regionalModerationAuthorities.contains(did)
}

/// Every regional moderation authority did, derived from the country map.
///
/// `CountryLabelers.labelers(forCountry:)` is the public accessor; asking it
/// for each supported country collects the full set without the package
/// needing the (internal) all-country constant.
let regionalModerationAuthorities: Set<String> = {
  let countries = [
    "BR", "RU", "GB", "AU", "TR", "JP", "PK", "IN", "DE", "ES",
    "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "GR",
    "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO",
    "SK", "SI", "SE",
  ]
  return Set(countries.flatMap { CountryLabelers.labelers(forCountry: $0) })
}()

/// The viewer's labeler subscriptions and the labeler detail reads behind them.
///
/// Port of `src/state/queries/labeler.ts` plus the subscription flow in
/// `src/screens/Profile/Header/ProfileHeaderLabeler.tsx`. Three things live
/// here:
///
/// 1. The `app.bsky.labeler.getServices` reads (`useLabelerInfoQuery`,
///    `useLabelersInfoQuery`, `useLabelersDetailedInfoQuery`).
/// 2. The subscription write (`useLabelerSubscriptionMutation`), including the
///    invalid-labeler cleanup and the `MAX_LABELERS` gate.
/// 3. The derived label-definition map (`useLabelDefinitionsQuery`), which is
///    what the moderation engine consumes as `ModerationOpts.labelDefs`.
public enum LabelerService {

  /// The RN app's cap (`MAX_LABELERS` in `src/lib/constants.ts`).
  public static let maxLabelers = 20

  /// Query-key roots, matching the RN ones.
  public static let labelerInfoRoot = "labeler-info"
  public static let labelersInfoRoot = "labelers-info"
  public static let labelersDetailedInfoRoot = "labelers-detailed-info"

  /// The persisted version RN sets on the detailed-info query.
  public static let detailedInfoPersistedVersion = 1

  /// The key for one labeler's detailed view.
  public static func labelerInfoKey(did: String) -> QueryKey {
    QueryKey(labelerInfoRoot, LabelerInfoArgs(did: did))
  }

  /// The key for a batch of labeler views. RN sorts the dids into the key, so
  /// two call sites requesting the same set share a cache entry.
  public static func labelersInfoKey(dids: [String]) -> QueryKey {
    QueryKey(labelersInfoRoot, LabelersInfoArgs(dids: dids.sorted()))
  }

  /// The key for a batch of labeler detailed views (persisted).
  public static func labelersDetailedInfoKey(dids: [String]) -> QueryKey {
    QueryKey(
      labelersDetailedInfoRoot, LabelersInfoArgs(dids: dids.sorted()),
      options: QueryOptions(persistedVersion: detailedInfoPersistedVersion))
  }

  /// Args for a single-labeler read.
  public struct LabelerInfoArgs: QueryArgs {
    public var did: String
    public init(did: String) { self.did = did }
  }

  /// Args for a batch labeler read.
  public struct LabelersInfoArgs: QueryArgs {
    public var dids: [String]
    public init(dids: [String]) { self.dids = dids }
  }

  /// Reads one labeler's detailed view.
  public static func labelerInfo(
    store: QueryStore, client: XrpcClient, did: String, detailed: Bool = true
  ) async throws -> App.Bsky.LabelerDefs_LabelerViewDetailed? {
    let output: App.Bsky.LabelerGetServices_Output = try await client.get(
      App.Bsky.LabelerGetServices.id,
      params: [("dids", did), ("detailed", detailed ? "true" : "false")]
    )
    for view in output.views {
      if case .labelerDefsLabelerViewDetailed(let detailedView) = view {
        return detailedView
      }
    }
    return nil
  }

  /// Reads a batch of labeler detailed views, dropping views of the wrong
  /// shape.
  public static func labelersDetailedInfo(
    client: XrpcClient, dids: [String]
  ) async throws -> [App.Bsky.LabelerDefs_LabelerViewDetailed] {
    guard !dids.isEmpty else { return [] }
    let output: App.Bsky.LabelerGetServices_Output = try await client.get(
      App.Bsky.LabelerGetServices.id,
      params: [("dids", dids.joined(separator: ",")), ("detailed", "true")]
    )
    return output.views.compactMap { view in
      if case .labelerDefsLabelerViewDetailed(let detailedView) = view { return detailedView }
      return nil
    }
  }

  /// The dids to read: the app's own labelers first, then the viewer's
  /// subscriptions, deduped. Port of `useMyLabelersQuery`.
  ///
  /// - Parameter excludeNonConfigurableAuthorities: drop the per-country
  ///   regional authorities, which the moderation screen can list but not
  ///   configure.
  public static func subscribedDids(
    appLabelers: [String], preferences: ModerationPrefs,
    excludeNonConfigurableAuthorities: Bool = false
  ) -> [String] {
    var seen = Set<String>()
    var dids = (appLabelers + preferences.labelers.map(\.did)).filter {
      seen.insert($0).inserted
    }
    if excludeNonConfigurableAuthorities {
      dids = dids.filter { !isNonConfigurableModerationAuthority($0) }
    }
    return dids
  }

  /// The interpreted label definitions keyed by labeler did.
  ///
  /// Port of `useLabelDefinitionsQuery`. This is the value fed to
  /// `ModerationOpts.labelDefs`.
  public static func labelDefinitions(
    _ labelers: [App.Bsky.LabelerDefs_LabelerViewDetailed]
  ) -> [String: [LabelValueDefinition]] {
    var out: [String: [LabelValueDefinition]] = [:]
    for labeler in labelers {
      let did = labeler.creator.did.rawValue
      out[did] = interpretLabelValueDefinitions(
        rawDefinitions(labeler), definedBy: did)
    }
    return out
  }

  /// Narrows a labeler's generated policy definitions into the engine's raw
  /// shape, then interprets them.
  static func rawDefinitions(
    _ labeler: App.Bsky.LabelerDefs_LabelerViewDetailed
  ) -> [LabelValueDefinitionRaw] {
    // Every case is spelled with its full type name: a bare `.none` in a
    // function returning an Optional resolves to `Optional.none` rather than to
    // the enum's own `none` case, which would silently drop the definition.
    func severity(
      _ value: Com.Atproto.LabelDefs_LabelValueDefinition_Severity
    ) -> LabelSeverity? {
      switch value {
      case .inform: return LabelSeverity.inform
      case .alert: return LabelSeverity.alert
      case .none: return LabelSeverity.none
      case ._other: return nil
      }
    }
    func blurs(_ value: Com.Atproto.LabelDefs_LabelValueDefinition_Blurs) -> LabelBlurs? {
      switch value {
      case .content: return LabelBlurs.content
      case .media: return LabelBlurs.media
      case .none: return LabelBlurs.none
      case ._other: return nil
      }
    }
    func defaultSetting(
      _ value: Com.Atproto.LabelDefs_LabelValueDefinition_DefaultSetting?
    ) -> Moderation.LabelPreference? {
      switch value {
      case .ignore: return Moderation.LabelPreference.ignore
      case .warn: return Moderation.LabelPreference.warn
      case .hide: return Moderation.LabelPreference.hide
      case ._other, .none: return nil
      }
    }

    return (labeler.policies.labelValueDefinitions ?? []).map { definition in
      // `noOverride` is not a field of the generated definition; the lexicon
      // carries it on the record's `adultOnly` sibling in some labeler setups,
      // so it is left unset here and re-derived by the interpreter.
      LabelValueDefinitionRaw(
        identifier: definition.identifier,
        severity: severity(definition.severity),
        blurs: blurs(definition.blurs),
        defaultSetting: defaultSetting(definition.defaultSetting),
        adultOnly: definition.adultOnly,
        noOverride: nil)
    }
  }

  /// The capabilities the report dialog needs off a detailed labeler view.
  public static func reportLabeler(
    _ labeler: App.Bsky.LabelerDefs_LabelerViewDetailed
  ) -> ReportLabeler {
    ReportLabeler(
      did: labeler.creator.did.rawValue,
      displayName: labeler.creator.displayName,
      handle: labeler.creator.handle.rawValue,
      reasonTypes: labeler.reasonTypes?.map(\.rawValue),
      subjectCollections: labeler.subjectCollections?.map(\.rawValue),
      subjectTypes: labeler.subjectTypes?.map(\.rawValue))
  }

  /// Whether the viewer is subscribed to `did`.
  ///
  /// Port of `isLabelerSubscribed`: the app's own labelers are always
  /// subscribed.
  public static func isSubscribed(
    did: String, appLabelers: [String], preferences: ModerationPrefs
  ) -> Bool {
    if appLabelers.contains(did) { return true }
    return preferences.labelers.contains { $0.did == did }
  }

  /// The subscribed dids that no longer resolve to a live labeler.
  ///
  /// Port of the `unavailableDids` derivation in `src/screens/Moderation/index.tsx`:
  /// subscribed dids absent from the returned labeler set, excluding the app's
  /// own and the regional authorities.
  public static func unavailableDids(
    subscribed: [String], returned: [String], appLabelers: [String]
  ) -> [String] {
    let returnedSet = Set(returned)
    return subscribed.filter { did in
      !returnedSet.contains(did)
        && !appLabelers.contains(did)
        && !isNonConfigurableModerationAuthority(did)
    }
  }

  /// The outcome of a subscription toggle's preflight.
  public enum SubscriptionPreflight: Sendable, Equatable {
    /// Proceed.
    case proceed
    /// Refuse because the cap is reached.
    case maxLabelersReached
  }

  /// Decides whether a subscribe may proceed, after the invalid-labeler
  /// cleanup.
  ///
  /// Port of the preflight inside `useLabelerSubscriptionMutation`: the cleanup
  /// removes invalid labelers first, and only then is `MAX_LABELERS` checked
  /// against what remains.
  public static func preflight(
    subscribe: Bool, currentDids: [String], invalidDids: [String],
    maxLabelers: Int = LabelerService.maxLabelers
  ) -> SubscriptionPreflight {
    guard subscribe else { return .proceed }
    let remaining = currentDids.count - invalidDids.count
    return remaining >= maxLabelers ? .maxLabelersReached : .proceed
  }

  /// The sentinel error the RN mutation throws when the cap is hit, so the
  /// caller can show the "Unable to subscribe" prompt.
  public struct MaxLabelersError: Error, Sendable {
    public init() {}
  }

  /// The profile shape the invalid-labeler cleanup reads.
  public struct ProfileAssociations: Sendable, Hashable {
    public var did: String
    /// `associated.labeler` (whether the account declares a labeler service).
    public var isLabeler: Bool

    public init(did: String, isLabeler: Bool) {
      self.did = did
      self.isLabeler = isLabeler
    }
  }

  /// Which subscribed labelers are invalid and should be cleaned up.
  ///
  /// Port of the `invalidLabelers` loop: a did that came back with a profile
  /// but no `associated.labeler` is invalid, and a did that came back with no
  /// profile at all is invalid (deactivated or taken down). A profile list that
  /// did not return at all leaves everything untouched.
  public static func invalidLabelers(
    subscribed: [String], profiles: [ProfileAssociations]?
  ) -> [String] {
    guard let profiles else { return [] }
    return subscribed.filter { did in
      guard let profile = profiles.first(where: { $0.did == did }) else { return true }
      return !profile.isLabeler
    }
  }

  /// Removes labelers from the viewer's preferences.
  ///
  /// Port of `useRemoveLabelersMutation`, which issues one `removeLabeler` per
  /// did. Each action is applied through the preferences engine in sequence.
  @discardableResult
  public static func removeLabelers(
    _ engine: PreferencesEngine, dids: [String]
  ) async throws -> [UpdateResult] {
    var results: [UpdateResult] = []
    for did in dids {
      results.append(try await engine.update(try PreferencesAction.removeLabeler(did: did).patch(tids: SequentialTids())))
    }
    return results
  }

  /// Adds a labeler to the viewer's preferences.
  @discardableResult
  public static func addLabeler(
    _ engine: PreferencesEngine, did: String
  ) async throws -> UpdateResult {
    try await engine.update(try PreferencesAction.addLabeler(did: did).patch(tids: SequentialTids()))
  }

  /// Sets one label's preference for a labeler (or globally).
  @discardableResult
  public static func setContentLabelPreference(
    _ engine: PreferencesEngine, label: String, visibility: Moderation.LabelPreference,
    labelerDid: String?
  ) async throws -> UpdateResult {
    try await engine.update(
      try PreferencesAction.setContentLabelPref(
        key: label, value: visibility.rawValue, labelerDid: labelerDid
      ).patch(tids: SequentialTids()))
  }
}

/// A minimal TID source for the helper wrappers above.
///
/// The labeler actions never mint ids, so any generator will do; this one
/// exists so the wrappers do not need a caller-supplied generator.
struct SequentialTids: TidGenerator {
  private let base = SequentialTidGenerator()
  func next() -> String { base.next() }
}

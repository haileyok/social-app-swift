import ATSyntax
import Foundation
import Lexicons

/// Whether the viewer is in a pack, and how that is derived.
///
/// Two sources say the same thing, and RN uses both:
///
/// - `getStarterPacksWithMembership` returns a `listItem` per pack the viewer is
///   in. That is what the profile dialog's add/remove control reads
///   (`!!starterPackWithMembership.listItem`).
/// - `getStarterPack`'s `list.viewer.referenceListOptOut` says whether the viewer
///   has opted *out* of appearing in a pack. That is a separate, per-list record.
///
/// This type covers both, so a screen can ask one question.
public struct StarterPackMembership: Sendable, Equatable {
  /// The pack's AT URI.
  public let packURI: String
  /// Whether the viewer is a member.
  public let isMember: Bool
  /// The viewer's membership record URI, when member.
  public let listItemURI: String?
  /// The viewer's reference-list opt-out record URI, when they opted out.
  public let referenceListOptOutURI: String?
  /// Whether the viewer has opted out of appearing in this pack.
  public let hasOptedOut: Bool

  /// Creates a membership.
  public init(
    packURI: String,
    isMember: Bool,
    listItemURI: String? = nil,
    referenceListOptOutURI: String? = nil
  ) {
    self.packURI = packURI
    self.isMember = isMember
    self.listItemURI = listItemURI
    self.referenceListOptOutURI = referenceListOptOutURI
    self.hasOptedOut = referenceListOptOutURI != nil
  }
}

/// Derives membership from the reads that report it.
///
/// Port of the derivations in `StarterPackDialog` (`isInPack`) and
/// `useReferenceListOptOutMutation`.
public enum StarterPackMembershipDerivation {
  /// Derives membership from a pack view's list viewer state.
  ///
  /// The viewer state does not say "member"; membership is the presence of the
  /// list item the *other* read returns. What it does carry is the opt-out URI,
  /// so this reports `isMember: false` and fills the opt-out.
  public static func fromPackView(
    _ view: App.Bsky.GraphDefs_StarterPackView
  ) -> StarterPackMembership {
    StarterPackMembership(
      packURI: view.uri.rawValue,
      isMember: false,
      referenceListOptOutURI: view.list?.viewer?.referenceListOptOut?.rawValue)
  }

  /// Derives membership from a `WithMembership` row.
  ///
  /// Port of `const isInPack = !!starterPackWithMembership.listItem`.
  public static func fromRow(
    _ row: App.Bsky.GraphGetStarterPacksWithMembership_StarterPackWithMembership
  ) -> StarterPackMembership {
    StarterPackMembership(
      packURI: row.starterPack.uri.rawValue,
      isMember: row.listItem != nil,
      listItemURI: row.listItem?.uri.rawValue,
      referenceListOptOutURI: row.starterPack.list?.viewer?.referenceListOptOut?.rawValue)
  }

  /// Derives one pack's membership from a full page of rows.
  ///
  /// Returns nil when the page has no row for the pack, which is how RN's dialog
  /// treats a pack the actor has no relationship with.
  public static func fromRows(
    _ rows: [App.Bsky.GraphGetStarterPacksWithMembership_StarterPackWithMembership],
    packURI: String
  ) -> StarterPackMembership? {
    rows.first { $0.starterPack.uri.rawValue == packURI }.map(fromRow)
  }

  /// The state of a pack's opt-out, as the menu labels it.
  ///
  /// Port of the `referenceListOptOut ? l\`Undo opt-out\` : l\`Opt out\`` choice:
  /// the menu offers the inverse of the current state.
  public static func optOutMenuAction(hasOptedOut: Bool) -> StarterPackOptOutAction {
    hasOptedOut ? .undo : .optOut
  }
}

/// What an opt-out control does next.
public enum StarterPackOptOutAction: Sendable, Equatable {
  /// Create a `referencelistoptout` record.
  case optOut
  /// Delete the existing `referencelistoptout` record.
  case undo

  /// The collection an opt-out record lives under.
  public static let collection = "app.bsky.graph.referencelistoptout"
}

/// The repo writes an opt-out toggle makes.
///
/// Port of the write half of `useReferenceListOptOutMutation`: opting out
/// creates a record with the list as its subject; undoing deletes the record the
/// viewer state named.
public enum StarterPackOptOutPlanner {
  /// The `referencelistoptout` record an opt-out writes.
  ///
  /// The record is `{$type, subject, createdAt}`; `subject` is the *list* URI,
  /// not the pack URI.
  public static func optOutRecord(listURI: String, createdAt: String) -> StarterPackJSON {
    .object([
      "$type": .string(StarterPackOptOutAction.collection),
      "subject": .string(listURI),
      "createdAt": .string(createdAt),
    ])
  }

  /// The plan that applies an opt-out action.
  ///
  /// - Parameters:
  ///   - action: whether to opt out or undo.
  ///   - listURI: the pack's backing list URI.
  ///   - repo: the viewer's DID.
  ///   - existingOptOutURI: the opt-out record URI the viewer state named.
  ///   - createdAt: the timestamp for a new record.
  /// - Returns: the write plan, or nil when undoing without a record to delete.
  public static func plan(
    action: StarterPackOptOutAction,
    listURI: String,
    repo: String,
    existingOptOutURI: String?,
    createdAt: String
  ) -> StarterPackOptOutPlan? {
    switch action {
    case .optOut:
      return .create(
        repo: repo,
        record: optOutRecord(listURI: listURI, createdAt: createdAt))
    case .undo:
      guard let existingOptOutURI, let rkey = StarterPackURI.parseRecordRkey(existingOptOutURI)
      else { return nil }
      return .delete(repo: repo, rkey: rkey)
    }
  }
}

/// The opt-out write to make.
public enum StarterPackOptOutPlan: Sendable, Equatable {
  /// Create the opt-out record.
  case create(repo: String, record: StarterPackJSON)
  /// Delete the opt-out record.
  case delete(repo: String, rkey: String)
}

extension StarterPackURI {
  /// The record key of an `at://` URI, whatever collection it names.
  ///
  /// I needed this for the opt-out record, whose collection is not a pack's, so
  /// it is a sibling of ``parse(_:)`` rather than a specialization of it.
  public static func parseRecordRkey(_ uri: String) -> String? {
    guard uri.hasPrefix("at://"), let parsed = try? AtUri(uri) else { return nil }
    let rkey = parsed.rkeySafe
    return rkey.isEmpty ? nil : rkey
  }
}

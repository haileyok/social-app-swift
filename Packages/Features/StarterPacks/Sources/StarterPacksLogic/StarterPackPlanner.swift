import ATSyntax
import Foundation
import Lexicons

/// A planned repo write, in the order it must be sent.
///
/// Each case maps to one XRPC call. The plan is data so a test can assert the
/// whole sequence, including how writes are chunked and in what order the calls
/// run.
public enum StarterPackWritePlanStep: Sendable, Equatable {
  /// `createRecord` of the backing list. `rkey` is nil, so the PDS mints one.
  case createList(collection: String, record: StarterPackJSON)
  /// One `applyWrites` batch.
  case applyWrites(repo: String, writes: [StarterPackJSON])
  /// `createRecord` of the pack itself.
  case createStarterPack(collection: String, record: StarterPackJSON)
  /// `putRecord` of the pack itself.
  case putStarterPack(collection: String, rkey: String, record: StarterPackJSON)
  /// `deleteRecord` of a record.
  case deleteRecord(collection: String, rkey: String)
}

/// The full plan for a create, edit or delete.
public struct StarterPackWritePlan: Sendable, Equatable {
  /// The steps, in the order they must run.
  public let steps: [StarterPackWritePlanStep]
  /// The pack's record key, for an edit or delete. Nil for a create, which the
  /// server keys.
  public let rkey: String?
  /// The placeholder URI a create plan used for the backing list, when the plan
  /// was built before that URI was known.
  ///
  /// ``StarterPackPlanExecutor`` replaces every occurrence of this string with
  /// the URI `createList` returned. Naming the placeholder on the plan keeps the
  /// substitution exact, rather than guessing which strings look like one.
  public let listPlaceholder: String?

  /// Creates a plan.
  public init(
    steps: [StarterPackWritePlanStep], rkey: String? = nil, listPlaceholder: String? = nil
  ) {
    self.steps = steps
    self.rkey = rkey
    self.listPlaceholder = listPlaceholder
  }

  /// The plan with the backing list's URI resolved.
  ///
  /// - Parameter listURI: the URI `createList` returned.
  public func resolvingListURI(_ listURI: String) -> StarterPackWritePlan {
    guard let placeholder = listPlaceholder else { return self }
    let rewritten = steps.map { step -> StarterPackWritePlanStep in
      switch step {
      case .createList:
        return step
      case .applyWrites(let repo, let writes):
        return .applyWrites(
          repo: repo,
          writes: writes.map { StarterPackPlanner.substituting(placeholder, with: listURI, in: $0) })
      case .createStarterPack(let collection, let record):
        return .createStarterPack(
          collection: collection,
          record: StarterPackPlanner.substituting(placeholder, with: listURI, in: record))
      case .putStarterPack(let collection, let rkey, let record):
        return .putStarterPack(
          collection: collection, rkey: rkey,
          record: StarterPackPlanner.substituting(placeholder, with: listURI, in: record))
      case .deleteRecord:
        return step
      }
    }
    return StarterPackWritePlan(steps: rewritten, rkey: rkey, listPlaceholder: nil)
  }
}

/// The plan set the wizard's submit path produces.
///
/// Port of `useCreateStarterPackMutation` and `useEditStarterPackMutation`
/// together with `createStarterPackList`, expressed as data rather than as a
/// sequence of calls, so the exact payloads and ordering can be asserted.
///
/// ## Create
///
/// RN's create path is:
///
/// 1. `createStarterPackList` -> `createRecord(app.bsky.graph.list, {...})`.
/// 2. `applyWrites` with one `#create` per selected profile. RN does **not**
///    chunk this call, unlike the edit path: a fresh pack's member list is
///    bounded by the wizard's own cap and is sent in one batch.
/// 3. `createRecord(app.bsky.graph.starterpack, {...})` with the list URI the
///    first call returned.
///
/// ## Edit
///
/// RN's edit path is:
///
/// 1. `applyWrites` of the removed members, chunked at 50.
/// 2. `applyWrites` of the added members, chunked at 50.
/// 3. `putRecord(app.bsky.graph.starterpack, rkey, {...})`, carrying
///    `createdAt` over and setting `updatedAt`.
///
/// The removed list is computed first and the added list second, and a profile
/// the viewer *is* is never removed (`i.subject.did !== pdsClient.did`).
public enum StarterPackPlanner {
  /// The inputs a create needs.
  public struct CreateInput: Sendable {
    /// The pack name, already defaulted and trimmed by the caller.
    public let name: String
    /// The description, trimmed.
    public let description: String?
    /// The description facets, when the caller resolved them.
    public let descriptionFacets: [StarterPackJSON]?
    /// The selected member DIDs, in selection order.
    public let memberDIDs: [String]
    /// The selected feed URIs, in selection order.
    public let feedURIs: [String]
    /// The repo the records go into: the author's DID.
    public let repo: String
    /// The `createdAt` timestamp for every new record.
    public let createdAt: String

    /// Creates the input.
    public init(
      name: String,
      description: String?,
      descriptionFacets: [StarterPackJSON]? = nil,
      memberDIDs: [String],
      feedURIs: [String],
      repo: String,
      createdAt: String
    ) {
      self.name = name
      self.description = description
      self.descriptionFacets = descriptionFacets
      self.memberDIDs = memberDIDs
      self.feedURIs = feedURIs
      self.repo = repo
      self.createdAt = createdAt
    }
  }

  /// Builds the create plan.
  ///
  /// The list URI the pack record must reference is not known before the first
  /// call runs, so the plan carries a placeholder and
  /// ``StarterPackPlanExecutor`` substitutes the resolved URI. An input with no
  /// members produces an empty plan: RN's `createStarterPackList` throws
  /// `No profiles given` before writing anything.
  public static func create(_ input: CreateInput) -> StarterPackWritePlan {
    guard !input.memberDIDs.isEmpty else {
      return StarterPackWritePlan(steps: [])
    }
    let placeholder = listPlaceholderURI(documentID: input.name)

    let writes = input.memberDIDs.map { did in
      StarterPackRecords.listItemWrite(
        subject: did, listURI: placeholder, createdAt: input.createdAt)
    }

    return StarterPackWritePlan(
      steps: [
        .createList(
          collection: StarterPackURI.listCollection,
          record: StarterPackRecords.listRecord(
            name: input.name,
            description: input.description,
            descriptionFacets: input.descriptionFacets,
            createdAt: input.createdAt)),
        .applyWrites(repo: input.repo, writes: writes),
        .createStarterPack(
          collection: StarterPackURI.collection,
          record: StarterPackRecords.createRecord(
            StarterPackRecords.StarterPackCreateRecordInput(
              name: input.name,
              description: input.description,
              descriptionFacets: input.descriptionFacets,
              listURI: placeholder,
              feedURIs: input.feedURIs,
              createdAt: input.createdAt))),
      ],
      listPlaceholder: placeholder)
  }

  /// Builds the create plan with the backing list's URI already resolved.
  ///
  /// Use this when the caller created the list itself and knows its URI.
  public static func create(_ input: CreateInput, listURI: String) -> StarterPackWritePlan {
    create(input).resolvingListURI(listURI)
  }

  /// The inputs an edit needs.
  public struct EditInput: Sendable {
    /// The pack's AT URI.
    public let packURI: String
    /// The repo the writes go into: the author's DID.
    public let repo: String
    /// The author's DID, which is never removed from the list.
    public let authorDID: String
    /// The pack's backing list URI.
    public let listURI: String
    /// The current members, as list-item views.
    public let currentItems: [App.Bsky.GraphDefs_ListItemView]
    /// The selected members after the edit.
    public let selectedProfiles: [WizardProfile]
    /// The selected feeds after the edit, as the values the edit path writes.
    public let feedValues: [StarterPackJSON]
    /// The name after the edit.
    public let name: String
    /// The description after the edit.
    public let description: String?
    /// The description facets after the edit.
    public let descriptionFacets: [StarterPackJSON]?
    /// The existing record's `createdAt`, carried over verbatim.
    public let createdAt: String
    /// The `updatedAt` to write.
    public let updatedAt: String

    /// Creates the input.
    public init(
      packURI: String,
      repo: String,
      authorDID: String,
      listURI: String,
      currentItems: [App.Bsky.GraphDefs_ListItemView],
      selectedProfiles: [WizardProfile],
      feedValues: [StarterPackJSON],
      name: String,
      description: String?,
      descriptionFacets: [StarterPackJSON]? = nil,
      createdAt: String,
      updatedAt: String
    ) {
      self.packURI = packURI
      self.repo = repo
      self.authorDID = authorDID
      self.listURI = listURI
      self.currentItems = currentItems
      self.selectedProfiles = selectedProfiles
      self.feedValues = feedValues
      self.name = name
      self.description = description
      self.descriptionFacets = descriptionFacets
      self.createdAt = createdAt
      self.updatedAt = updatedAt
    }
  }

  /// The list items an edit removes.
  ///
  /// Port of the `removedItems` filter: an item is removed when its subject is
  /// not the author and is not among the selected profiles.
  public static func removedItems(_ input: EditInput) -> [App.Bsky.GraphDefs_ListItemView] {
    input.currentItems.filter { item in
      let subjectDID = item.subject.did.rawValue
      if subjectDID == input.authorDID { return false }
      let selected = input.selectedProfiles.contains { profile in
        profile.did == subjectDID && !profile.did.isEmpty
      }
      return !selected
    }
  }

  /// The profiles an edit adds: selected profiles not already in the list.
  ///
  /// Port of the `addedProfiles` filter, which matches on the item's subject DID.
  public static func addedProfiles(_ input: EditInput) -> [WizardProfile] {
    let existing = Set(input.currentItems.map { $0.subject.did.rawValue })
    return input.selectedProfiles.filter { !existing.contains($0.did) }
  }

  /// Builds the edit plan.
  ///
  /// The rkey is derived from the pack URI exactly as RN derives it
  /// (`parseStarterPackUri(currentStarterPack.uri)!.rkey`). A URI that does not
  /// parse yields no plan, since RN would throw on the same input.
  public static func edit(_ input: EditInput) -> StarterPackWritePlan? {
    guard let parsed = StarterPackURI.parse(input.packURI) else { return nil }

    var steps: [StarterPackWritePlanStep] = []

    let removed = removedItems(input)
    if !removed.isEmpty {
      let writes = removed.map { item in
        let rkey = (try? AtUri(item.uri.rawValue))?.rkeySafe ?? ""
        return StarterPackRecords.listItemDeleteWrite(rkey: rkey)
      }
      for chunk in StarterPackRecords.chunk(writes) {
        steps.append(.applyWrites(repo: input.repo, writes: chunk))
      }
    }

    let added = addedProfiles(input)
    if !added.isEmpty {
      let writes = added.map { profile in
        StarterPackRecords.listItemWrite(
          subject: profile.did, listURI: input.listURI, createdAt: input.updatedAt)
      }
      for chunk in StarterPackRecords.chunk(writes) {
        steps.append(.applyWrites(repo: input.repo, writes: chunk))
      }
    }

    steps.append(
      .putStarterPack(
        collection: StarterPackURI.collection,
        rkey: parsed.rkey,
        record: StarterPackRecords.editRecord(
          StarterPackRecords.StarterPackEditRecordInput(
            name: input.name,
            description: input.description,
            descriptionFacets: input.descriptionFacets,
            listURI: input.listURI,
            feeds: input.feedValues,
            createdAt: input.createdAt,
            updatedAt: input.updatedAt))))

    return StarterPackWritePlan(steps: steps, rkey: parsed.rkey)
  }

  /// The delete plan for a pack, in RN's order.
  ///
  /// Port of `useDeleteStarterPackMutation`: the backing list is deleted first
  /// when there is one, then the pack. The order matters, because the appview
  /// keeps serving a pack whose list is gone (`InvalidStarterPack`).
  public static func delete(listURI: String?, rkey: String) -> StarterPackWritePlan {
    var steps: [StarterPackWritePlanStep] = []
    if let listURI, let parsed = try? AtUri(listURI) {
      steps.append(.deleteRecord(collection: StarterPackURI.listCollection, rkey: parsed.rkeySafe))
    }
    steps.append(.deleteRecord(collection: StarterPackURI.collection, rkey: rkey))
    return StarterPackWritePlan(steps: steps, rkey: rkey)
  }

  // MARK: - Placeholders

  /// The sentinel authority a placeholder list URI uses.
  public static let placeholderAuthority = "at://pending.invalid"

  /// The placeholder backing-list URI for a create plan.
  ///
  /// The URI is only known once `createRecord` returns, so the plan is built
  /// against a placeholder and ``StarterPackWritePlan/resolvingListURI(_:)``
  /// substitutes the real one. The placeholder is a well-formed `at://` URI under
  /// a sentinel authority, so an unsubstituted plan is still valid JSON and
  /// obviously wrong.
  public static func listPlaceholderURI(documentID: String) -> String {
    "\(placeholderAuthority)/\(StarterPackURI.listCollection)/\(sanitizeRkey(documentID))"
  }

  /// True when `uri` is an unsubstituted placeholder.
  public static func isPlaceholder(_ uri: String) -> Bool {
    uri.hasPrefix(placeholderAuthority + "/")
  }

  /// Replaces every exact occurrence of `from` with `to` throughout a JSON value.
  static func substituting(
    _ from: String, with to: String, in value: StarterPackJSON
  ) -> StarterPackJSON {
    switch value {
    case .string(let string):
      return string == from ? .string(to) : value
    case .array(let items):
      return .array(items.map { substituting(from, with: to, in: $0) })
    case .object(let members):
      return .object(members.mapValues { substituting(from, with: to, in: $0) })
    default:
      return value
    }
  }

  /// Reduces a document name to a valid record key.
  private static func sanitizeRkey(_ value: String) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
    let lowered = value.lowercased().unicodeScalars.filter { allowed.contains($0) }
    let result = String(String.UnicodeScalarView(lowered))
    return result.isEmpty ? "pending" : String(result.prefix(64))
  }
}

/// Runs a ``StarterPackWritePlan`` against a ``StarterPackXrpc``.
///
/// The executor exists because a create plan's list URI is only known after the
/// first call returns. It creates the list, resolves the placeholder in every
/// later step, and then runs them in order.
public struct StarterPackPlanExecutor: Sendable {
  /// The write surface.
  public let xrpc: any StarterPackXrpc
  /// The repo the writes target.
  public let repo: String

  /// Creates an executor.
  public init(xrpc: any StarterPackXrpc, repo: String) {
    self.xrpc = xrpc
    self.repo = repo
  }

  /// Runs a plan, returning the pack's `{uri, cid}` when the plan creates or
  /// updates one.
  ///
  /// `createList` is always the first step of a create plan, so when it runs the
  /// remaining steps are re-read from the resolved plan before they are sent.
  /// Nothing unsubstituted reaches the wire.
  @discardableResult
  public func run(_ plan: StarterPackWritePlan) async throws -> StarterPackRecordRef? {
    var current = plan
    var packRef: StarterPackRecordRef?
    var index = 0

    while index < current.steps.count {
      switch current.steps[index] {
      case .createList(let collection, let record):
        let ref = try await xrpc.createRecord(
          repo: repo, collection: collection, rkey: nil, record: record)
        current = current.resolvingListURI(ref.uri)
      case .applyWrites(_, let writes):
        try await xrpc.applyWrites(repo: repo, writes: writes)
      case .createStarterPack(let collection, let record):
        packRef = try await xrpc.createRecord(
          repo: repo, collection: collection, rkey: nil, record: record)
      case .putStarterPack(let collection, let rkey, let record):
        packRef = try await xrpc.putRecord(
          repo: repo, collection: collection, rkey: rkey, record: record)
      case .deleteRecord(let collection, let rkey):
        try await xrpc.deleteRecord(repo: repo, collection: collection, rkey: rkey)
      }
      index += 1
    }
    return packRef
  }
}

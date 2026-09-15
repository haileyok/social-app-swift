import Foundation

/// The record payloads the create/edit/delete paths write, as exact JSON.
///
/// Every builder returns the object RN's lex client would send, field for field,
/// so a payload table can pin the bytes. Ports:
/// - `src/lib/generate-starterpack.ts` (`createStarterPackList`, `createListItem`)
/// - `src/state/queries/starter-packs.ts` (`useCreateStarterPackMutation`,
///   `useEditStarterPackMutation`, `useDeleteStarterPackMutation`)
public enum StarterPackRecords {
  /// The `$type` of a starter pack record.
  public static let starterPackType = StarterPackURI.collection
  /// The `$type` of the backing list record.
  public static let listType = StarterPackURI.listCollection
  /// The `$type` of a list-membership record.
  public static let listItemType = StarterPackURI.listItemCollection

  /// The reference-list purpose, RN's `app.bsky.graph.defs#referencelist`.
  public static let referenceListPurpose = "app.bsky.graph.defs#referencelist"

  /// The `applyWrites#create` write `$type`.
  public static let createWriteType = "com.atproto.repo.applyWrites#create"
  /// The `applyWrites#delete` write `$type`.
  public static let deleteWriteType = "com.atproto.repo.applyWrites#delete"

  // MARK: - Records

  /// The `app.bsky.graph.list` record RN's `createStarterPackList` writes.
  ///
  /// RN spreads `avatar: undefined`, which the lex encoder drops, so the member
  /// is simply absent here. `descriptionFacets` is omitted when there are none,
  /// matching the same "undefined means absent" rule.
  public static func listRecord(
    name: String,
    description: String?,
    descriptionFacets: [StarterPackJSON]?,
    createdAt: String
  ) -> StarterPackJSON {
    var record: [String: StarterPackJSON] = [
      "$type": .string(listType),
      "name": .string(name),
      "purpose": .string(referenceListPurpose),
      "createdAt": .string(createdAt),
    ]
    if let description, !description.isEmpty {
      record["description"] = .string(description)
    }
    if let descriptionFacets {
      record["descriptionFacets"] = .array(descriptionFacets)
    }
    return .object(record)
  }

  /// The `app.bsky.graph.starterpack` record the create path writes.
  ///
  /// Port of the `pdsClient.create(app.bsky.graph.starterpack, {...})` call in
  /// `useCreateStarterPackMutation`. `feeds` is `[{uri}]` for each selected
  /// generator, and is omitted entirely when no feeds were chosen (RN's
  /// `feeds?.map(...)` yields `undefined`).
  public static func createRecord(_ input: StarterPackCreateRecordInput) -> StarterPackJSON {
    var record: [String: StarterPackJSON] = [
      "$type": .string(starterPackType),
      "name": .string(input.name),
      "list": .string(input.listURI),
      "createdAt": .string(input.createdAt),
    ]
    if let description = input.description, !description.isEmpty {
      record["description"] = .string(description)
    }
    if let descriptionFacets = input.descriptionFacets {
      record["descriptionFacets"] = .array(descriptionFacets)
    }
    if !input.feedURIs.isEmpty {
      record["feeds"] = .array(input.feedURIs.map { .object(["uri": .string($0)]) })
    }
    return .object(record)
  }

  /// The members of a created starter-pack record.
  public struct StarterPackCreateRecordInput: Sendable, Equatable {
    /// The pack name.
    public let name: String
    /// The description, when set.
    public let description: String?
    /// The description facets, when resolved.
    public let descriptionFacets: [StarterPackJSON]?
    /// The backing list's URI.
    public let listURI: String
    /// The selected feed URIs, in order.
    public let feedURIs: [String]
    /// The timestamp for the new record.
    public let createdAt: String

    /// Creates the input.
    public init(
      name: String,
      description: String?,
      descriptionFacets: [StarterPackJSON]? = nil,
      listURI: String,
      feedURIs: [String],
      createdAt: String
    ) {
      self.name = name
      self.description = description
      self.descriptionFacets = descriptionFacets
      self.listURI = listURI
      self.feedURIs = feedURIs
      self.createdAt = createdAt
    }
  }

  /// The record the edit path sends to `putRecord`.
  ///
  /// Port of `useEditStarterPackMutation`'s `putRecord` body. Three details are
  /// preserved verbatim because they are what the app actually writes:
  ///
  /// 1. `createdAt` is carried over from the existing record and `updatedAt` is
  ///    set to now. `updatedAt` is not in the lexicon, and RN writes it anyway.
  /// 2. `feeds` carries whole generator views rather than `{uri}` refs - a
  ///    long-standing RN quirk (the create path writes refs, the edit path
  ///    writes views). ``StarterPackEditRecordInput/feeds`` passes those values
  ///    through unmodified.
  /// 3. `list` is the existing pack's list URI and is written whenever it is
  ///    present; RN spreads a possibly-undefined value, which the lex encoder
  ///    would drop, and omitting the member here is the same wire result.
  public static func editRecord(_ input: StarterPackEditRecordInput) -> StarterPackJSON {
    var record: [String: StarterPackJSON] = [
      "$type": .string(starterPackType),
      "name": .string(input.name),
      "createdAt": .string(input.createdAt),
      "updatedAt": .string(input.updatedAt),
      "feeds": .array(input.feeds),
    ]
    if let description = input.description, !description.isEmpty {
      record["description"] = .string(description)
    }
    if let descriptionFacets = input.descriptionFacets {
      record["descriptionFacets"] = .array(descriptionFacets)
    }
    if let listURI = input.listURI {
      record["list"] = .string(listURI)
    }
    return .object(record)
  }

  /// The members of an edited starter-pack record.
  public struct StarterPackEditRecordInput: Sendable, Equatable {
    /// The pack name.
    public let name: String
    /// The description, when set.
    public let description: String?
    /// The description facets, when resolved.
    public let descriptionFacets: [StarterPackJSON]?
    /// The backing list's URI, when the pack has one.
    public let listURI: String?
    /// The feed values to write, passed through unmodified.
    public let feeds: [StarterPackJSON]
    /// The existing record's `createdAt`, carried over.
    public let createdAt: String
    /// The `updatedAt` to write.
    public let updatedAt: String

    /// Creates the input.
    public init(
      name: String,
      description: String?,
      descriptionFacets: [StarterPackJSON]? = nil,
      listURI: String?,
      feeds: [StarterPackJSON],
      createdAt: String,
      updatedAt: String
    ) {
      self.name = name
      self.description = description
      self.descriptionFacets = descriptionFacets
      self.listURI = listURI
      self.feeds = feeds
      self.createdAt = createdAt
      self.updatedAt = updatedAt
    }
  }

  // MARK: - Writes

  /// An `applyWrites#create` write for a list item.
  ///
  /// Port of `createListItem`. RN's create path does not pass an explicit rkey,
  /// so the PDS mints one; ``listItemWrite(subject:listURI:rkey:createdAt:)``
  /// takes one for callers that need the resulting URI up front.
  public static func listItemWrite(
    subject: String, listURI: String, createdAt: String
  ) -> StarterPackJSON {
    listItemWrite(subject: subject, listURI: listURI, rkey: nil, createdAt: createdAt)
  }

  /// An `applyWrites#create` write for a list item, with an explicit rkey.
  public static func listItemWrite(
    subject: String, listURI: String, rkey: String?, createdAt: String
  ) -> StarterPackJSON {
    var value: [String: StarterPackJSON] = [
      "$type": .string(listItemType),
      "subject": .string(subject),
      "list": .string(listURI),
      "createdAt": .string(createdAt),
    ]
    var write: [String: StarterPackJSON] = [
      "$type": .string(createWriteType),
      "collection": .string(listItemType),
      "value": .object(value),
    ]
    if let rkey {
      write["rkey"] = .string(rkey)
    }
    return .object(write)
  }

  /// An `applyWrites#delete` write for a list item, addressed by its record key.
  ///
  /// Port of the delete branch in `useEditStarterPackMutation`, which derives the
  /// rkey from the item's URI (`new AtUri(i.uri).rkeySafe`).
  public static func listItemDeleteWrite(rkey: String) -> StarterPackJSON {
    .object([
      "$type": .string(deleteWriteType),
      "collection": .string(listItemType),
      "rkey": .string(rkey),
    ])
  }

  // MARK: - Chunking

  /// Splits writes into RN-sized batches (`chunk(writes, 50)`).
  public static func chunk(
    _ writes: [StarterPackJSON],
    size: Int = StarterPackConstants.writeChunkSize
  ) -> [[StarterPackJSON]] {
    guard size > 0 else { return writes.isEmpty ? [] : [writes] }
    guard writes.count > size else { return writes.isEmpty ? [] : [writes] }
    return stride(from: 0, to: writes.count, by: size).map {
      Array(writes[$0..<min($0 + size, writes.count)])
    }
  }
}

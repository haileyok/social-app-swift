import ATProtoClient
import Foundation
import Lexicons
import Preferences

/// The repository and preference writes the onboarding steps make.
///
/// This is the seam between step orchestration and the wire. The live
/// implementation performs the actual XRPC calls; the in-package fake records
/// them, so tests can assert exactly which calls each step makes with which
/// params.
public protocol OnboardingActionService: Sendable {
  /// The DID of the signed-in account, i.e. the repo every write targets.
  func currentDID() async throws -> String

  /// Uploads an avatar blob and returns the blob reference to attach.
  func uploadAvatar(data: Data, mimeType: String) async throws -> OnboardingBlobRef

  /// Upserts the profile record with the given avatar and display name.
  func upsertProfile(
    avatar: OnboardingBlobRef?, displayName: String, joinedViaStarterPack: StarterPackRef?
  ) async throws

  /// Creates follow records for the given DIDs.
  ///
  /// Returns the created follow URIs keyed by subject DID, the shape RN's
  /// `bulkWriteFollows` returns.
  func createFollows(
    dids: [String], via: StarterPackRef?
  ) async throws -> [String: String]

  /// Writes the interests preference.
  func setInterests(tags: [String]) async throws

  /// Applies the adult-content preference.
  func setAdultContentEnabled(_ enabled: Bool) async throws

  /// Overwrites the saved-feeds preference list.
  func overwriteSavedFeeds(_ feeds: [SavedFeed]) async throws

  /// Upserts a NUX record into the app-state preference.
  func upsertNux(id: String, completed: Bool, data: String?) async throws

  /// `app.bsky.graph.getStarterPack`, for resolving the pack a user chose.
  func getStarterPack(uri: String) async throws -> StarterPackDetail

  /// `app.bsky.graph.getList`, paged to exhaustion.
  ///
  /// Port of `getAllListMembers`; used to follow a joined starter pack's
  /// members at completion.
  func getListMemberDIDs(listURI: String) async throws -> [String]
}

/// A blob reference as it travels back from `uploadBlob`.
public struct OnboardingBlobRef: Sendable, Equatable, Codable {
  /// The blob `$type`, always `blob` for atproto blobs.
  public let type: String
  /// The blob link.
  public let ref: String
  /// The blob's mime type.
  public let mimeType: String?
  /// The blob's size in bytes.
  public let size: Int?

  /// Creates a blob reference.
  public init(type: String = "blob", ref: String, mimeType: String?, size: Int?) {
    self.type = type
    self.ref = ref
    self.mimeType = mimeType
    self.size = size
  }
}

/// An `com.atproto.repo.strongRef`.
public struct StarterPackRef: Sendable, Equatable, Codable, Hashable {
  /// The record's AT URI.
  public let uri: String
  /// The record's CID.
  public let cid: String

  /// Creates a strong reference.
  public init(uri: String, cid: String) {
    self.uri = uri
    self.cid = cid
  }
}

/// The parts of a starter pack the completion step needs.
public struct StarterPackDetail: Sendable, Equatable {
  /// The pack's strong reference.
  public let ref: StarterPackRef
  /// The AT URI of the list backing the pack, when it has one.
  public let listURI: String?
  /// The feed URIs the pack pins.
  public let feedURIs: [String]

  /// Creates a pack detail.
  public init(ref: StarterPackRef, listURI: String?, feedURIs: [String]) {
    self.ref = ref
    self.listURI = listURI
    self.feedURIs = feedURIs
  }
}

/// One saved feed entry.
public struct SavedFeed: Sendable, Equatable, Codable {
  /// The feed type: `feed`, `timeline`, or `list`.
  public let type: String
  /// The feed value: a feed URI, `following`, or a list URI.
  public let value: String
  /// Whether the feed is pinned.
  public let pinned: Bool

  /// Creates a saved feed.
  public init(type: String, value: String, pinned: Bool) {
    self.type = type
    self.value = value
    self.pinned = pinned
  }
}

/// The default saved feeds every new account gets, from `lib/constants.ts`.
public enum DefaultSavedFeeds {
  /// `DISCOVER_FEED_URI` (the Discover feed).
  public static let discoverFeedURI =
    "at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.generator/whats-hot"
  /// `VIDEO_FEED_URI` (the video feed).
  public static let videoFeedURI =
    "at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.generator/bsky-team"
  /// `DISCOVER_SAVED_FEED`.
  public static let discover = SavedFeed(type: "feed", value: discoverFeedURI, pinned: true)
  /// `TIMELINE_SAVED_FEED`.
  public static let timeline = SavedFeed(type: "timeline", value: "following", pinned: true)
  /// `VIDEO_SAVED_FEED`.
  public static let video = SavedFeed(type: "feed", value: videoFeedURI, pinned: true)

  /// The list RN writes in `StepFinished`, in order.
  public static let all: [SavedFeed] = [discover, timeline, video]
}

/// `BSKY_APP_ACCOUNT_DID` from `lib/constants.ts`: the account every new user
/// follows on completion.
public enum OnboardingConstants {
  /// The Bluesky app account's DID.
  public static let bskyAppAccountDID = "did:plc:z72i7hdynmk6r22z27h6tvur"
  /// The NUX id the flow marks complete.
  ///
  /// RN's onboarding flow does not write a NUX: it drives the shell's coarse
  /// step (`persisted.onboarding`). This id is the durable marker the Swift
  /// app records in preferences so completion survives a reinstall of local
  /// storage. The RN NUX vocabulary has no onboarding entry, so an app-specific
  /// id is used rather than reusing an unrelated one.
  public static let onboardingNuxID = "onboarding"
}

/// The live action service, over a PDS client plus a preferences engine.
///
/// The PDS client makes repo writes (`uploadBlob`, `applyWrites`,
/// `putRecord`); the preferences engine makes preference writes. Both target
/// the account-host server, so neither carries an appview proxy header.
public struct LiveOnboardingActionService: OnboardingActionService {
  private let pds: XrpcClient
  private let preferences: PreferencesEngine
  private let appview: XrpcClient
  private let authorization: @Sendable () async throws -> String?
  private let did: String
  private let tids: any TidGenerator

  /// Creates the service.
  public init(
    pds: XrpcClient,
    preferences: PreferencesEngine,
    appview: XrpcClient,
    did: String,
    tids: any TidGenerator = SystemTidGenerator(),
    authorization: @escaping @Sendable () async throws -> String? = { nil }
  ) {
    self.pds = pds
    self.preferences = preferences
    self.appview = appview
    self.did = did
    self.tids = tids
    self.authorization = authorization
  }

  public func currentDID() async throws -> String {
    did
  }

  public func uploadAvatar(data: Data, mimeType: String) async throws -> OnboardingBlobRef {
    /*
     * The multipart body is built here rather than reusing
     * `XrpcClient.uploadBlob`, because that helper's response decoder is
     * broken: `BlobUploadResponse.BlobRefLink` declares a `link` property with
     * a synthesised `CodingKeys`, while the wire member is `$link`, so `ref`
     * always decodes to nil and the uploaded blob's CID is lost. The request
     * is byte-identical; only the response is decoded here.
     */
    let boundary = "Boundary-\(UUID().uuidString)"
    var body = Data()
    body.append(contentsOf: Array("--\(boundary)\r\n".utf8))
    body.append(
      contentsOf: Array(
        "Content-Disposition: form-data; name=\"blob\"; filename=\"blob\"\r\n".utf8))
    body.append(contentsOf: Array("Content-Type: \(mimeType)\r\n\r\n".utf8))
    body.append(data)
    body.append(contentsOf: Array("\r\n--\(boundary)--\r\n".utf8))

    let response = try await pds.rawPost(
      "com.atproto.repo.uploadBlob", body: body,
      contentType: "multipart/form-data; boundary=\(boundary)",
      authorization: try await authorization())
    guard 200..<300 ~= response.status else {
      throw XrpcError.from(
        status: response.status, headers: response.headers, data: response.body)
    }
    let payload = try JSONDecoder().decode([String: JSONValue].self, from: response.body)
    let blob = payload["blob"]?.objectValue
    return OnboardingBlobRef(
      type: blob?["$type"]?.stringValue ?? "blob",
      ref: blob?["ref"]?.objectValue?["$link"]?.stringValue ?? "",
      mimeType: blob?["mimeType"]?.stringValue ?? mimeType,
      size: blob?["size"]?.intValue)
  }

  public func upsertProfile(
    avatar: OnboardingBlobRef?, displayName: String, joinedViaStarterPack: StarterPackRef?
  ) async throws {
    // RN's `upsertProfile` reads the existing record first and spreads it, so
    // fields the app does not model survive. The read is a `getRecord`; a
    // missing record is not an error.
    let existing = try await fetchProfileRecord()
    var record = existing ?? [:]
    record["$type"] = .string("app.bsky.actor.profile")
    record["displayName"] = .string(displayName)
    if let avatar {
      record["avatar"] = .object([
        "$type": .string("blob"),
        "ref": .object(["$link": .string(avatar.ref)]),
        "mimeType": .string(avatar.mimeType ?? "image/jpeg"),
        "size": .int(avatar.size ?? 0),
      ])
    }
    if let joinedViaStarterPack {
      record["joinedViaStarterPack"] = .object([
        "$type": .string("com.atproto.repo.strongRef"),
        "uri": .string(joinedViaStarterPack.uri),
        "cid": .string(joinedViaStarterPack.cid),
      ])
    }
    if record["createdAt"] == nil {
      record["createdAt"] = .string(ISO8601DateFormatter().string(from: Date()))
    }
    try await putRecord(
      collection: "app.bsky.actor.profile", rkey: "self", record: record)
  }

  public func createFollows(
    dids: [String], via: StarterPackRef?
  ) async throws -> [String: String] {
    guard !dids.isEmpty else { return [:] }
    // RN chunks writes at 50 per applyWrites call (`chunk(followWrites, 50)`).
    let chunks = stride(from: 0, to: dids.count, by: 50).map {
      Array(dids[$0..<min($0 + 50, dids.count)])
    }
    var followURIs: [String: String] = [:]
    let createdAt = ISO8601DateFormatter().string(from: Date())
    for chunk in chunks {
      var writes: [JSONValue] = []
      for subject in chunk {
        let rkey = tids.next()
        var record: [String: JSONValue] = [
          "$type": .string("app.bsky.graph.follow"),
          "subject": .string(subject),
          "createdAt": .string(createdAt),
        ]
        if let via {
          record["via"] = .object([
            "$type": .string("com.atproto.repo.strongRef"),
            "uri": .string(via.uri),
            "cid": .string(via.cid),
          ])
        }
        writes.append(
          .object([
            "$type": .string("com.atproto.repo.applyWrites#create"),
            "collection": .string("app.bsky.graph.follow"),
            "rkey": .string(rkey),
            "value": .object(record),
          ]))
        followURIs[subject] = "at://\(did)/app.bsky.graph.follow/\(rkey)"
      }
      let body = try JSONEncoder().encode([
        "repo": JSONValue.string(did),
        "writes": JSONValue.array(writes),
      ])
      let response = try await pds.rawPost(
        "com.atproto.repo.applyWrites", body: body, contentType: "application/json",
        authorization: try await authorization())
      guard 200..<300 ~= response.status else {
        throw XrpcError.from(
          status: response.status, headers: response.headers, data: response.body)
      }
    }
    return followURIs
  }

  public func setInterests(tags: [String]) async throws {
    try await preferences.setInterestsPref(tags: tags)
  }

  public func setAdultContentEnabled(_ enabled: Bool) async throws {
    try await preferences.setAdultContentEnabled(enabled)
  }

  public func overwriteSavedFeeds(_ feeds: [SavedFeed]) async throws {
    let records = feeds.map { feed in
      PrefObject(fields: [
        "$type": .string("app.bsky.actor.defs#savedFeed"),
        "id": .string(tids.next()),
        "type": .string(feed.type),
        "value": .string(feed.value),
        "pinned": .bool(feed.pinned),
      ])
    }
    try await preferences.overwriteSavedFeeds(records)
  }

  public func upsertNux(id: String, completed: Bool, data: String?) async throws {
    var fields: [String: JSONValue] = [
      "id": .string(id),
      "completed": .bool(completed),
    ]
    if let data {
      fields["data"] = .string(data)
    }
    try await preferences.upsertNux(PrefObject(fields: fields))
  }

  public func getStarterPack(uri: String) async throws -> StarterPackDetail {
    let output: App.Bsky.GraphGetStarterPack_Output = try await appview.get(
      "app.bsky.graph.getStarterPack", params: [("starterPack", uri)])
    let view = output.starterPack
    return StarterPackDetail(
      ref: StarterPackRef(uri: view.uri.rawValue, cid: view.cid.rawValue),
      listURI: view.list?.uri.rawValue,
      feedURIs: (view.feeds ?? []).map(\.uri.rawValue))
  }

  public func getListMemberDIDs(listURI: String) async throws -> [String] {
    var dids: [String] = []
    var cursor: String?
    // A starter pack list is small; five pages of 100 is the ceiling
    // `XrpcClient.paginate` uses by default.
    for _ in 0..<5 {
      let output: App.Bsky.GraphGetList_Output = try await appview.get(
        "app.bsky.graph.getList",
        params: [("list", listURI), ("limit", "100"), ("cursor", cursor)])
      dids.append(contentsOf: output.items.map(\.subject.did.rawValue))
      guard let next = output.cursor else { break }
      cursor = next
    }
    return dids
  }

  // MARK: - Repo reads/writes

  /// Reads the profile record, returning nil when there is none.
  private func fetchProfileRecord() async throws -> [String: JSONValue]? {
    let response = try await pds.rawGet(
      "com.atproto.repo.getRecord",
      params: [
        ("repo", did), ("collection", "app.bsky.actor.profile"), ("rkey", "self"),
      ],
      authorization: try await authorization())
    if response.status == 400 || response.status == 404 {
      // RN treats a missing record as "no existing profile to spread".
      return nil
    }
    guard 200..<300 ~= response.status else {
      throw XrpcError.from(
        status: response.status, headers: response.headers, data: response.body)
    }
    let payload = try JSONDecoder().decode([String: JSONValue].self, from: response.body)
    return payload["value"]?.objectValue
  }

  /// `com.atproto.repo.putRecord` with a raw JSON record.
  private func putRecord(
    collection: String, rkey: String, record: [String: JSONValue]
  ) async throws {
    let body = try JSONEncoder().encode([
      "repo": JSONValue.string(did),
      "collection": JSONValue.string(collection),
      "rkey": JSONValue.string(rkey),
      "record": JSONValue.object(record),
    ])
    let response = try await pds.rawPost(
      "com.atproto.repo.putRecord", body: body, contentType: "application/json",
      authorization: try await authorization())
    guard 200..<300 ~= response.status else {
      throw XrpcError.from(
        status: response.status, headers: response.headers, data: response.body)
    }
  }
}

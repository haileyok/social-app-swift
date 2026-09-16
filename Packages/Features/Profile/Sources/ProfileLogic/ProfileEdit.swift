import ATProtoClient
import Foundation
import Lexicons
import QueryStore
import SwiftAtproto

/// The limits the edit-profile form enforces.
///
/// Port of `MAX_DISPLAY_NAME` / `MAX_DESCRIPTION` in `src/lib/constants.ts`. The
/// generated ``App/Bsky/ActorProfile`` record enforces the same numbers in its
/// `make` initialiser, so the form and the record agree; these constants exist so
/// the form can show the message before a request is attempted.
public enum ProfileLimits {
  /// `MAX_DISPLAY_NAME = 64`.
  public static let maxDisplayName = 64
  /// `MAX_DESCRIPTION = 256`.
  public static let maxDescription = 256
  /// The byte cap the lexicon applies to `displayName` (UTF-8).
  public static let maxDisplayNameBytes = 640
  /// The byte cap the lexicon applies to `description` (UTF-8).
  public static let maxDescriptionBytes = 2560
}

/// Why a proposed profile edit cannot be saved.
public enum ProfileEditValidationError: Error, Sendable, Equatable {
  /// The display name exceeds ``ProfileLimits/maxDisplayName`` graphemes.
  case displayNameTooLong(limit: Int)
  /// The description exceeds ``ProfileLimits/maxDescription`` graphemes.
  case descriptionTooLong(limit: Int)
  /// An image could not be read from disk.
  case unreadableImage(path: String)
  /// The chosen avatar or banner exceeds the lexicon's blob size cap.
  case imageTooLarge(path: String, limit: Int)

  /// The message the form shows, in the RN dialog's wording.
  public var message: String {
    switch self {
    case .displayNameTooLong(let limit):
      "Display name is too long. The maximum number of characters is \(limit)."
    case .descriptionTooLong(let limit):
      "Description is too long. The maximum number of characters is \(limit)."
    case .unreadableImage(let path):
      "Could not read the selected image: \(path)"
    case .imageTooLarge(_, let limit):
      "The selected image is too large. The maximum size is \(limit) bytes."
    }
  }
}

/// A chosen image, resolved to bytes.
public struct ProfileImageUpload: Sendable, Equatable {
  /// The file the image came from, for error messages.
  public let path: String
  /// The MIME type sent as the blob's content type.
  public let mimeType: String
  /// The raw bytes.
  public let data: Data

  public init(path: String, mimeType: String, data: Data) {
    self.path = path
    self.mimeType = mimeType
    self.data = data
  }
}

/// The avatar and banner inputs of an edit.
///
/// The three cases are the three states RN's dialog distinguishes: not touched
/// (`undefined`), cleared (`null`), and replaced (an `ImageMeta`).
public enum ProfileImageChange: Sendable, Equatable {
  /// Leave the current image alone. RN: `undefined`.
  case unchanged
  /// Remove the image. RN: `null`.
  case cleared
  /// Replace the image.
  case replaced(ProfileImageUpload)
}

/// A proposed edit to a profile.
public struct ProfileEdit: Sendable {
  /// The profile being edited.
  public let profile: App.Bsky.ActorDefs_ProfileViewDetailed
  /// The new display name, already trimmed at the end as the dialog does.
  public let displayName: String
  /// The new description, already trimmed at the end.
  public let description: String
  /// The new avatar, if it changed.
  public let avatar: ProfileImageChange
  /// The new banner, if it changed.

  public let banner: ProfileImageChange

  public init(
    profile: App.Bsky.ActorDefs_ProfileViewDetailed,
    displayName: String,
    description: String,
    avatar: ProfileImageChange = .unchanged,
    banner: ProfileImageChange = .unchanged
  ) {
    // RN trims trailing whitespace at save time (`displayName.trimEnd()`), not
    // while typing, so the trim belongs to the model rather than the field.
    self.profile = profile
    self.displayName = Self.trimEnd(displayName)
    self.description = Self.trimEnd(description)
    self.avatar = avatar
    self.banner = banner
  }

  /// True when nothing differs from the profile, so the dialog's save button is
  /// disabled. RN computes the same thing from its `useState` values.
  public var isDirty: Bool {
    displayName != Self.trimEnd(profile.displayName ?? "")
      || description != Self.trimEnd(profile.description ?? "")
      || avatar != .unchanged
      || banner != .unchanged
  }

  /// Validates the text fields.
  ///
  /// Port of the `isOverMaxGraphemeCount` checks the dialog runs, which count
  /// *graphemes* (Swift's `Character`), not scalars - an emoji family counts as
  /// one. The byte caps are checked too, because the lexicon enforces both and a
  /// string can pass the grapheme check while exceeding the byte cap.
  public func validate() throws {
    if displayName.count > ProfileLimits.maxDisplayName {
      throw ProfileEditValidationError.displayNameTooLong(limit: ProfileLimits.maxDisplayName)
    }
    if displayName.utf8.count > ProfileLimits.maxDisplayNameBytes {
      throw ProfileEditValidationError.displayNameTooLong(limit: ProfileLimits.maxDisplayName)
    }
    if description.count > ProfileLimits.maxDescription {
      throw ProfileEditValidationError.descriptionTooLong(limit: ProfileLimits.maxDescription)
    }
    if description.utf8.count > ProfileLimits.maxDescriptionBytes {
      throw ProfileEditValidationError.descriptionTooLong(limit: ProfileLimits.maxDescription)
    }
    try validateImage(avatar)
    try validateImage(banner)
  }

  private func validateImage(_ change: ProfileImageChange) throws {
    guard case .replaced(let upload) = change else { return }
    // avatar and banner share the lexicon's 1,000,000-byte cap.
    guard upload.data.count <= ProfileManager.maxImageBytes else {
      throw ProfileEditValidationError.imageTooLarge(
        path: upload.path, limit: ProfileManager.maxImageBytes)
    }
  }

  /// The lexicon record the edit produces.
  ///
  /// Port of the `upsertProfile` callback: start from the existing record and
  /// overwrite only the fields the edit touches. RN assigns
  /// `updates.displayName || undefined`, so an empty string clears the field
  /// rather than storing `""`.
  public func record(
    existing: App.Bsky.ActorProfile = App.Bsky.ActorProfile(),
    avatarBlob: LexBlob? = nil,
    bannerBlob: LexBlob? = nil
  ) -> App.Bsky.ActorProfile {
    App.Bsky.ActorProfile(
      avatar: resolvedBlob(avatar, replacing: existing.avatar, with: avatarBlob),
      banner: resolvedBlob(banner, replacing: existing.banner, with: bannerBlob),
      createdAt: existing.createdAt,
      description: description.isEmpty ? nil : description,
      displayName: displayName.isEmpty ? nil : displayName,
      joinedViaStarterPack: existing.joinedViaStarterPack,
      labels: existing.labels,
      pinnedPost: existing.pinnedPost,
      pronouns: existing.pronouns,
      website: existing.website)
  }

  private func resolvedBlob(
    _ change: ProfileImageChange, replacing current: LexBlob?, with uploaded: LexBlob?
  ) -> LexBlob? {
    switch change {
    case .unchanged: current
    case .cleared: nil
    case .replaced: uploaded
    }
  }

  /// `String.prototype.trimEnd`: strips trailing whitespace only.
  static func trimEnd(_ text: String) -> String {
    var result = Substring(text)
    while let last = result.last, last.isWhitespace {
      result = result.dropLast()
    }
    return String(result)
  }
}

/// Orchestrates the edit-profile write.
///
/// Port of `useProfileUpdateMutation` in `src/state/queries/profile.ts`:
/// upload any new images, read the current profile record, apply the edit, write
/// it back with `putRecord`, then poll `getProfile` until the appview has caught
/// up. The polling is the part that makes this more than a single request - the
/// PDS write is visible immediately but the appview's index lags behind it.
public struct ProfileManager: Sendable {
  /// The XRPC client used for PDS writes.
  public let client: XrpcClient
  /// The client used for the appview read-back.
  public let appView: ProfileClient
  /// How many times ``write(_:repo:viewerDid:)`` re-reads the profile.
  public let commitAttempts: Int
  /// Delay between commit checks. RN: `1e3` ms, so 1 second.
  public let commitInterval: Duration
  /// The lexicon's per-image size cap: `1_000_000` bytes for avatar and banner.
  public static let maxImageBytes = 1_000_000

  public init(
    client: XrpcClient,
    appView: ProfileClient,
    commitAttempts: Int = 5,
    commitInterval: Duration = .seconds(1)
  ) {
    self.client = client
    self.appView = appView
    self.commitAttempts = commitAttempts
    self.commitInterval = commitInterval
  }

  /// The `app.bsky.actor.profile` record key. RN's `upsertProfile` always writes
  /// the singleton `self`.
  public static let profileRecordKey = "self"

  /// Validates an edit without performing it. The form calls this on every
  /// keystroke.
  public static func validate(_ edit: ProfileEdit) throws {
    try edit.validate()
  }

  /// The avatar/banner blobs an edit needs, or `nil` for types that do not
  /// upload.
  public func uploadImages(
    _ edit: ProfileEdit, authorization: String? = nil
  ) async throws -> (avatar: LexBlob?, banner: LexBlob?, avatarLink: String?, bannerLink: String?) {
    var avatar: LexBlob?
    var banner: LexBlob?
    var avatarLink: String?
    var bannerLink: String?
    if case .replaced(let avatarUpload) = edit.avatar {
      let uploaded = try await uploadBlob(avatarUpload, authorization: authorization)
      avatar = uploaded.blob
      avatarLink = uploaded.link
    }
    if case .replaced(let bannerUpload) = edit.banner {
      let uploaded = try await uploadBlob(bannerUpload, authorization: authorization)
      banner = uploaded.blob
      bannerLink = uploaded.link
    }
    return (avatar, banner, avatarLink, bannerLink)
  }

  /// Uploads one image with `com.atproto.repo.uploadBlob`.
  ///
  /// The endpoint accepts the image bytes directly rather than multipart form
  /// data. The response is decoded through the generated ``LexBlob`` shape so
  /// its `$link` metadata survives when the profile record is written.
  func uploadBlob(_ upload: ProfileImageUpload, authorization: String?)
    async throws -> (blob: LexBlob, link: String) {
    let response = try await client.rawPost(
      "com.atproto.repo.uploadBlob", body: upload.data,
      contentType: upload.mimeType,
      authorization: authorization)
    guard 200..<300 ~= response.status else {
      throw XrpcError.from(status: response.status, headers: response.headers, data: response.body)
    }
    guard
      let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
      let blob = object["blob"] as? [String: Any],
      let ref = blob["ref"] as? [String: Any],
      let link = ref["$link"] as? String
    else {
      throw ProfileWriteError.unreadableImage(upload.path)
    }
    var json: [String: Any] = [
      "$type": "blob",
      "ref": ["$link": link],
      "mimeType": blob["mimeType"] as? String ?? upload.mimeType,
      "size": blob["size"] as? Int ?? upload.data.count,
    ]
    if let type = blob["$type"] as? String { json["$type"] = type }
    let decoded = try JSONDecoder().decode(
      LexBlob.self, from: try JSONSerialization.data(withJSONObject: json))
    return (decoded, link)
  }

  /// Applies an edit: validate, upload, read the current record, write it back,
  /// then wait for the appview to reflect it.
  ///
  /// - Parameters:
  ///   - edit: the proposed edit.
  ///   - repo: the signed-in account's DID, whose repo holds the record.
  ///   - authorization: the access token, if the client does not carry one.
  /// - Returns: the profile as the appview reports it once committed, or `nil`
  ///   when the commit check never saw the change inside its attempt budget.
  @discardableResult
  public func write(
    _ edit: ProfileEdit, repo: String, authorization: String? = nil
  ) async throws -> App.Bsky.ActorDefs_ProfileViewDetailed? {
    try edit.validate()
    let blobs = try await uploadImages(edit, authorization: authorization)
    let existing = try await currentRecord(repo: repo, authorization: authorization)
    let record = edit.record(
      existing: existing, avatarBlob: blobs.avatar, bannerBlob: blobs.banner)
    let body = ProfileRecordBody(
      record: record, avatarLink: blobs.avatarLink, bannerLink: blobs.bannerLink)
    _ = try await client.putRecord(
      repo: repo, collection: App.Bsky.ActorProfile.nsId, rkey: Self.profileRecordKey,
      record: body, authorization: authorization)
    return try await waitForCommit(edit, actor: edit.profile.did.rawValue, authorization: authorization)
  }

  /// Reads the current `app.bsky.actor.profile` record, or an empty record when
  /// the account has none yet.
  func currentRecord(repo: String, authorization: String?) async throws
    -> App.Bsky.ActorProfile {
    do {
      let output: Com.Atproto.RepoGetRecord_Output = try await client.get(
        "com.atproto.repo.getRecord",
        params: [
          ("collection", App.Bsky.ActorProfile.nsId),
          ("repo", repo),
          ("rkey", Self.profileRecordKey),
        ],
        authorization: authorization)
      if case .record(let record) = output.value,
        let profile = record as? App.Bsky.ActorProfile {
        return profile
      }
      return App.Bsky.ActorProfile()
    } catch let error as XrpcError where error.rawCode == "RecordNotFound" {
      // No profile record yet; the put creates it.
      return App.Bsky.ActorProfile()
    }
  }

  /// Polls the appview until the edit is visible.
  ///
  /// Port of `whenAppViewReady` with the dialog's `checkCommitted` predicate:
  /// give up after `commitAttempts` reads spaced by `commitInterval`, and treat a
  /// missing profile as "not yet".
  func waitForCommit(
    _ edit: ProfileEdit, actor: String, authorization: String?
  ) async throws -> App.Bsky.ActorDefs_ProfileViewDetailed? {
    var latest: App.Bsky.ActorDefs_ProfileViewDetailed?
    for attempt in 0..<commitAttempts {
      if attempt > 0 {
        try await Task.sleep(for: commitInterval)
      }
      guard let fresh = try? await appView.getProfile(actor: actor, authorization: authorization)
      else { continue }
      latest = fresh
      if Self.hasCommitted(edit, fresh: fresh) { return fresh }
    }
    return latest
  }

  /// The `checkCommitted` predicate the dialog installs.
  ///
  /// The image checks are deliberately asymmetric: a cleared image must come
  /// back absent, a replaced one must come back *different* from what the profile
  /// showed before the edit (an unchanged URL means the appview has not caught
  /// up), and an untouched field is not checked at all.
  public static func hasCommitted(
    _ edit: ProfileEdit, fresh: App.Bsky.ActorDefs_ProfileViewDetailed
  ) -> Bool {
    switch edit.avatar {
    case .unchanged:
      break
    case .cleared:
      if fresh.avatar != nil { return false }
    case .replaced:
      if fresh.avatar?.rawValue == edit.profile.avatar?.rawValue { return false }
    }
    switch edit.banner {
    case .unchanged:
      break
    case .cleared:
      if fresh.banner != nil { return false }
    case .replaced:
      if fresh.banner?.rawValue == edit.profile.banner?.rawValue { return false }
    }
    return normalized(fresh.displayName) == normalized(edit.displayName)
      && normalized(fresh.description) == normalized(edit.description)
  }

  /// Trims trailing space, then maps an empty string to `nil`.
  ///
  /// RN compares `fresh.displayName === updates.displayName` where the edit side
  /// was already `trimEnd`-ed and an empty value was written as `undefined`, so
  /// a `nil` and an empty `String` compare equal here too.
  static func normalized(_ text: String?) -> String? {
    guard let trimmed = text.map({ ProfileEdit.trimEnd($0) }), !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }
}

/// The `app.bsky.actor.profile` record body, in JSON wire form.
///
/// Hand-built rather than taken from ``App/Bsky/ActorProfile`` for two reasons,
/// both confirmed against the generated encoder and pinned by
/// `ProfileEditWriteTests.writeUploadsReadsPutsAndPolls`:
///
/// 1. The generated record's encoder omits `$type`, which the PDS requires.
/// 2. Its `LexBlob`/`LexLink` fields encode through `LexLink.encode(to:)`, which
///    writes CBOR byte strings rather than the JSON `{"$link": "..."}` shape the
///    PDS expects on a JSON record body.
///
/// The field set and their order match the lexicon, and every optional field is
/// omitted when absent so the record stays minimal.
struct ProfileRecordBody: Encodable, Sendable {
  var type: String
  var avatar: ProfileBlobBody?
  var banner: ProfileBlobBody?
  var createdAt: String?
  var description: String?
  var displayName: String?
  var joinedViaStarterPack: Com.Atproto.RepoStrongRef?
  var labels: App.Bsky.ActorProfile_Labels?
  var pinnedPost: Com.Atproto.RepoStrongRef?
  var pronouns: String?
  var website: String?

  enum CodingKeys: String, CodingKey {
    case type = "$type"
    case avatar
    case banner
    case createdAt
    case description
    case displayName
    case joinedViaStarterPack
    case labels
    case pinnedPost
    case pronouns
    case website
  }

  /// Builds a body from the generated record and the uploaded blob links.
  ///
  /// The blob *content* comes from the upload; the field values come from the
  /// generated record, which is where ``ProfileEdit/record(existing:avatarBlob:bannerBlob:)``
  /// has already applied the edit.
  init(record: App.Bsky.ActorProfile, avatarLink: String?, bannerLink: String?) {
    self.type = App.Bsky.ActorProfile.nsId
    self.avatar = avatarLink.map {
      ProfileBlobBody(ref: ProfileLinkBody(link: $0), mimeType: record.avatar?.mimeType ?? "image/jpeg",
        size: Int(record.avatar?.size ?? 0))
    }
    self.banner = bannerLink.map {
      ProfileBlobBody(ref: ProfileLinkBody(link: $0), mimeType: record.banner?.mimeType ?? "image/jpeg",
        size: Int(record.banner?.size ?? 0))
    }
    self.createdAt = record.createdAt?.rawValue
    self.description = record.description
    self.displayName = record.displayName
    self.joinedViaStarterPack = record.joinedViaStarterPack
    self.labels = record.labels
    self.pinnedPost = record.pinnedPost
    self.pronouns = record.pronouns
    self.website = record.website?.rawValue
  }
}

extension ProfileManager {
  /// Invalidates the caches an edit affects, after a successful write.
  ///
  /// Port of the `onSuccess` block of `useProfileUpdateMutation`: the single
  /// profile key and the multi-profile key for this DID.
  public func invalidateProfileCaches(store: QueryStore, did: String, scope: String?) async {
    await store.invalidate(ProfileQueryKeys.profile(did: did, scope: scope))
    await store.invalidate(
      ProfileQueryKeys.profiles(handles: [did], scope: scope))
  }
}

/// A blob reference in the JSON wire form.
///
/// File-scope rather than nested, and hand-built for the reason given on
/// ``ProfileRecordBody``: the generated ``LexBlob`` encodes its link as a CBOR
/// byte string, which is not the `{"$link": "..."}` shape a JSON record body
/// needs.
struct ProfileBlobBody: Encodable, Sendable {
  var type = "blob"
  var ref: ProfileLinkBody
  var mimeType: String
  var size: Int

  enum CodingKeys: String, CodingKey {
    case type = "$type"
    case ref
    case mimeType
    case size
  }
}

/// A CID link in the JSON wire form.
struct ProfileLinkBody: Encodable, Sendable {
  var link: String

  enum CodingKeys: String, CodingKey {
    case link = "$link"
  }
}

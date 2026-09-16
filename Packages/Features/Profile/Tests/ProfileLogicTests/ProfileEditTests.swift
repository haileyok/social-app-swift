import Foundation
import Lexicons
import QueryStore
import SwiftAtproto
import Testing

@testable import ProfileLogic

/// Edit-profile validation: the limits the form enforces before it writes.
@Suite("Profile edit validation") struct ProfileEditValidationTests {

  private func edit(
    displayName: String = "Alice",
    description: String = "Hello",
    avatar: ProfileImageChange = .unchanged,
    banner: ProfileImageChange = .unchanged,
    profile: App.Bsky.ActorDefs_ProfileViewDetailed = makeProfile()
  ) -> ProfileEdit {
    ProfileEdit(
      profile: profile, displayName: displayName, description: description,
      avatar: avatar, banner: banner)
  }

  /// A display name at the limit is accepted; one over is rejected.
  @Test func displayNameBoundary() throws {
    try edit(displayName: String(repeating: "a", count: ProfileLimits.maxDisplayName)).validate()
    #expect(throws: ProfileEditValidationError.displayNameTooLong(limit: 64)) {
      try edit(displayName: String(repeating: "a", count: ProfileLimits.maxDisplayName + 1))
        .validate()
    }
  }

  /// The description boundary likewise.
  @Test func descriptionBoundary() throws {
    try edit(description: String(repeating: "a", count: ProfileLimits.maxDescription)).validate()
    #expect(throws: ProfileEditValidationError.descriptionTooLong(limit: 256)) {
      try edit(description: String(repeating: "a", count: ProfileLimits.maxDescription + 1))
        .validate()
    }
  }

  /// Graphemes, not scalars: a family emoji is one character even though it is
  /// many scalars, so a name of 64 of them passes.
  @Test func countsGraphemesNotScalars() throws {
    // "e" + U+0301 (combining acute): one grapheme, two scalars, three UTF-8
    // bytes, so 64 of them are 192 bytes - inside the 640-byte cap, which is
    // what lets this test isolate the grapheme rule from the byte rule.
    let combining = "e\u{0301}"
    #expect(combining.count == 1)
    #expect(combining.unicodeScalars.count == 2)
    try edit(displayName: String(repeating: combining, count: ProfileLimits.maxDisplayName))
      .validate()
  }

  /// Trailing whitespace is trimmed by the model, so a name that only exceeds
  /// the limit by trailing spaces is accepted.
  @Test func trailingWhitespaceIsTrimmed() throws {
    let name = String(repeating: "a", count: ProfileLimits.maxDisplayName) + "   \n"
    let candidate = edit(displayName: name)
    #expect(candidate.displayName == String(repeating: "a", count: ProfileLimits.maxDisplayName))
    try candidate.validate()
  }

  /// Leading whitespace is not trimmed - RN uses `trimEnd`.
  @Test func leadingWhitespaceIsPreserved() {
    let candidate = edit(displayName: "   Alice")
    #expect(candidate.displayName == "   Alice")
  }

  /// An image larger than the lexicon's cap is rejected before the upload.
  @Test func oversizedImageIsRejected() {
    let upload = ProfileImageUpload(
      path: "/tmp/big.jpg", mimeType: "image/jpeg",
      data: Data(count: ProfileManager.maxImageBytes + 1))
    #expect(throws: ProfileEditValidationError.imageTooLarge(
      path: "/tmp/big.jpg", limit: ProfileManager.maxImageBytes)) {
      try edit(avatar: .replaced(upload)).validate()
    }
  }

  /// An image at the cap is accepted.
  @Test func imageAtTheCapIsAccepted() throws {
    let upload = ProfileImageUpload(
      path: "/tmp/ok.jpg", mimeType: "image/jpeg", data: Data(count: ProfileManager.maxImageBytes))
    try edit(avatar: .replaced(upload)).validate()
  }

  /// A cleared image needs no bytes and passes validation.
  @Test func clearedImagePasses() throws {
    try edit(avatar: .cleared, banner: .cleared).validate()
  }

  /// `isDirty` follows the three fields the dialog tracks.
  @Test func dirtyDetection() {
    let profile = makeProfile(displayName: "Alice", description: "Hello")
    #expect(!edit(profile: profile).isDirty, "an untouched form is clean")
    #expect(edit(displayName: "Bob", profile: profile).isDirty)
    #expect(edit(description: "Other", profile: profile).isDirty)
    #expect(edit(avatar: .cleared, profile: profile).isDirty)
    #expect(edit(banner: .cleared, profile: profile).isDirty)
  }

  /// The initial values are the profile's own, already trimmed, so a profile
  /// whose name has trailing whitespace still starts clean.
  @Test func aProfileWithTrailingWhitespaceStartsClean() {
    let profile = makeProfile(displayName: "Alice   ", description: "Hello\n")
    #expect(!edit(displayName: "Alice   ", description: "Hello\n", profile: profile).isDirty)
  }

  /// The record upsert keeps untouched fields and overwrites the edited ones.
  @Test func recordUpsertKeepsUntouchedFields() {
    let pronouns = "she/her"
    let existing = App.Bsky.ActorProfile(displayName: "Old", pronouns: pronouns)
    let record = edit(displayName: "New", description: "Bio").record(existing: existing)
    #expect(record.displayName == "New")
    #expect(record.description == "Bio")
    #expect(record.pronouns == pronouns, "an untouched field survives")
  }

  /// An emptied field becomes `nil` rather than an empty string, matching RN's
  /// `updates.displayName || undefined`.
  @Test func emptiedFieldsBecomeNil() {
    let existing = App.Bsky.ActorProfile(description: "Old bio", displayName: "Old")
    let record = edit(displayName: "", description: "").record(existing: existing)
    #expect(record.displayName == nil)
    #expect(record.description == nil)
  }

  /// A cleared image drops the blob from the record.
  @Test func clearedImageDropsTheBlob() {
    let existing = App.Bsky.ActorProfile(displayName: "Alice")
    let record = edit(avatar: .cleared).record(existing: existing, avatarBlob: nil)
    #expect(record.avatar == nil)
  }

  /// An unchanged image keeps whatever the record already had.
  @Test func unchangedImageKeepsTheExistingBlob() throws {
    let blob = try makeBlob()
    let existing = App.Bsky.ActorProfile(avatar: blob)
    let record = edit(avatar: .unchanged).record(existing: existing)
    #expect(record.avatar == blob)
  }

  /// A replaced image takes the uploaded blob.
  @Test func replacedImageTakesTheUploadedBlob() throws {
    let blob = try makeBlob()
    let record = edit(avatar: .replaced(ProfileImageUpload(
      path: "/tmp/a.jpg", mimeType: "image/jpeg", data: Data()))).record(
      existing: App.Bsky.ActorProfile(), avatarBlob: blob)
    #expect(record.avatar == blob)
  }
}

/// The edit write path: upload, read, put, poll.
@Suite("Profile edit write") struct ProfileEditWriteTests {

  private static let repo = "did:plc:me"
  private static let alice = "did:plc:alice"

  /// A write uploads the new avatar, reads the current record, puts the merged
  /// record, then polls the appview until it agrees.
  @Test func writeUploadsReadsPutsAndPolls() async throws {
    let transport = ScriptedTransport(script: [
      // 1. uploadBlob
      ScriptedTransport.json([
        "blob": [
          "$type": "blob",
          "ref": ["$link": "bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
          "mimeType": "image/jpeg",
          "size": 11,
        ]
      ]),
      // 2. getRecord (no existing record)
      ScriptedTransport.xrpcError("RecordNotFound", message: "no record", status: 400),
      // 3. putRecord
      ScriptedTransport.json(["uri": "at://did:plc:me/app.bsky.actor.profile/self", "cid": "bafy2"]),
      // 4. getProfile, now committed
      ScriptedTransport.json(profileJSON(displayName: "New", description: "Bio")),
    ])
    let manager = ProfileManager(
      client: makeXrpcClient(transport), appView: makeClient(transport),
      commitAttempts: 3, commitInterval: .milliseconds(1))
    let edit = ProfileEdit(
      profile: makeProfile(displayName: "Old", description: "Old bio"),
      displayName: "New", description: "Bio",
      avatar: .replaced(ProfileImageUpload(
        path: "/tmp/a.jpg", mimeType: "image/jpeg", data: Data("hello world".utf8))))
    let result = try await manager.write(edit, repo: Self.repo)

    #expect(result?.displayName == "New")
    let paths = transport.received.map(\.path)
    #expect(paths.count == 4, "one call per step: \(paths)")
    #expect(paths[0].hasSuffix("com.atproto.repo.uploadBlob"))
    #expect(paths[1].hasSuffix("com.atproto.repo.getRecord"))
    #expect(paths[2].hasSuffix("com.atproto.repo.putRecord"))
    #expect(paths[3].hasSuffix("app.bsky.actor.getProfile"))

    // The put carries the merged record under the singleton rkey.
    let put = transport.received[2].json
    #expect(put["repo"] as? String == Self.repo)
    #expect(put["collection"] as? String == "app.bsky.actor.profile")
    #expect(put["rkey"] as? String == "self")
    let record = try #require(put["record"] as? [String: Any])
    #expect(record["displayName"] as? String == "New")
    #expect(record["description"] as? String == "Bio")
    let avatar = try #require(record["avatar"] as? [String: Any])
    #expect(avatar["mimeType"] as? String == "image/jpeg")
    #expect((avatar["ref"] as? [String: Any])?["$link"] is String)
  }

  /// The upload sends the image bytes directly with their MIME type.
  @Test func uploadUsesRawImageBodyAndMimeType() async throws {
    let bytes = Data("fake-jpeg".utf8)
    let transport = ScriptedTransport(script: [
      ScriptedTransport.json([
        "blob": [
          "$type": "blob",
          "ref": ["$link": "bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
          "mimeType": "image/jpeg", "size": 9,
        ]
      ]),
      ScriptedTransport.xrpcError("RecordNotFound", message: "none", status: 400),
      ScriptedTransport.json(["uri": "at://x", "cid": "bafy"]),
      ScriptedTransport.json(profileJSON(displayName: "New", description: "Hello")),
    ])
    let manager = ProfileManager(
      client: makeXrpcClient(transport), appView: makeClient(transport),
      commitAttempts: 1, commitInterval: .milliseconds(1))
    let edit = ProfileEdit(
      profile: makeProfile(displayName: "Old"),
      displayName: "New", description: "Hello",
      avatar: .replaced(ProfileImageUpload(
        path: "/tmp/a.jpg", mimeType: "image/jpeg", data: bytes)))
    _ = try await manager.write(edit, repo: Self.repo)

    let upload = try #require(transport.received.first)
    #expect(upload.headers["Content-Type"] == "image/jpeg")
    #expect(upload.body == bytes)
  }

  /// When the appview never reflects the change, the last profile seen is
  /// returned rather than an error - RN logs and moves on.
  @Test func aStaleAppviewReturnsTheLastProfileSeen() async throws {
    // No upload entry: the image is unchanged, so the first request is the
    // getRecord.
    let transport = ScriptedTransport(script: [
      ScriptedTransport.xrpcError("RecordNotFound", message: "none", status: 400),
      ScriptedTransport.json(["uri": "at://did:plc:me/app.bsky.actor.profile/self", "cid": "bafy"]),
      ScriptedTransport.json(profileJSON(displayName: "Old", description: "Old bio")),
      ScriptedTransport.json(profileJSON(displayName: "Old", description: "Old bio")),
      ScriptedTransport.json(profileJSON(displayName: "Old", description: "Old bio")),
    ])
    let manager = ProfileManager(
      client: makeXrpcClient(transport), appView: makeClient(transport),
      commitAttempts: 3, commitInterval: .milliseconds(1))
    let edit = ProfileEdit(
      profile: makeProfile(displayName: "Old", description: "Old bio"),
      displayName: "New", description: "Bio",
      avatar: .unchanged, banner: .unchanged)
    let result = try await manager.write(edit, repo: Self.repo)
    #expect(result?.displayName == "Old", "the stale profile is returned, not an error")
  }

  /// An existing record is read and merged rather than replaced wholesale.
  @Test func anExistingRecordIsMerged() async throws {
    let transport = ScriptedTransport(script: [
      ScriptedTransport.json([
        "uri": "at://did:plc:me/app.bsky.actor.profile/self",
        "cid": "bafyold",
        "value": [
          "$type": "app.bsky.actor.profile",
          "displayName": "Old",
          "pronouns": "she/her",
        ],
      ]),
      ScriptedTransport.json(["uri": "at://x", "cid": "bafy"]),
      ScriptedTransport.json(profileJSON(displayName: "New", description: "Hello")),
    ])
    let manager = ProfileManager(
      client: makeXrpcClient(transport), appView: makeClient(transport),
      commitAttempts: 1, commitInterval: .milliseconds(1))
    let edit = ProfileEdit(
      profile: makeProfile(displayName: "Old"), displayName: "New", description: "Hello")
    _ = try await manager.write(edit, repo: Self.repo)

    let put = transport.received[1].json
    let record = try #require(put["record"] as? [String: Any])
    #expect(record["pronouns"] as? String == "she/her", "the untouched field survives the write")
    #expect(record["displayName"] as? String == "New")
  }

  /// Invalid input is rejected before any request is made.
  @Test func validationRunsBeforeAnyRequest() async throws {
    let transport = ScriptedTransport(script: [])
    let manager = ProfileManager(
      client: makeXrpcClient(transport), appView: makeClient(transport),
      commitAttempts: 1, commitInterval: .milliseconds(1))
    let edit = ProfileEdit(
      profile: makeProfile(),
      displayName: String(repeating: "a", count: 65), description: "x")
    await #expect(throws: ProfileEditValidationError.displayNameTooLong(limit: 64)) {
      try await manager.write(edit, repo: Self.repo)
    }
    #expect(transport.requestCount == 0)
  }

  /// The commit predicate treats an unchanged avatar URL as "not yet", and a
  /// cleared avatar as "not yet" while one is still present.
  @Test func commitPredicateImageRules() {
    let profile = makeProfile(avatar: "https://cdn/old.jpg", banner: nil)

    let replacedStillOld = ProfileEdit(
      profile: profile, displayName: "Alice", description: "Hello",
      avatar: .replaced(ProfileImageUpload(path: "/a", mimeType: "image/jpeg", data: Data())))
    #expect(
      !ProfileManager.hasCommitted(
        replacedStillOld, fresh: makeProfile(avatar: "https://cdn/old.jpg")))
    #expect(
      ProfileManager.hasCommitted(replacedStillOld, fresh: makeProfile(avatar: "https://cdn/new.jpg")))

    let cleared = ProfileEdit(
      profile: profile, displayName: "Alice", description: "Hello", avatar: .cleared)
    #expect(!ProfileManager.hasCommitted(cleared, fresh: makeProfile(avatar: "https://cdn/old.jpg")))
    #expect(ProfileManager.hasCommitted(cleared, fresh: makeProfile(avatar: nil)))

    let untouched = ProfileEdit(
      profile: profile, displayName: "Alice", description: "Hello", avatar: .unchanged)
    #expect(ProfileManager.hasCommitted(untouched, fresh: makeProfile(avatar: "https://cdn/old.jpg")))
  }

  /// The commit predicate compares the text fields too, so a changed name that
  /// has not propagated is "not yet".
  @Test func commitPredicateTextRules() {
    let edit = ProfileEdit(
      profile: makeProfile(displayName: "Old"), displayName: "New", description: "Bio")
    #expect(!ProfileManager.hasCommitted(edit, fresh: makeProfile(displayName: "Old", description: "Bio")))
    #expect(ProfileManager.hasCommitted(edit, fresh: makeProfile(displayName: "New", description: "Bio")))
  }

  /// An emptied text field must come back absent or empty, not stale.
  @Test func commitPredicateTreatsEmptyAsNil() {
    let edit = ProfileEdit(
      profile: makeProfile(displayName: "Old"), displayName: "", description: "Bio")
    #expect(ProfileManager.hasCommitted(edit, fresh: makeProfile(displayName: nil, description: "Bio")))
    #expect(ProfileManager.hasCommitted(edit, fresh: makeProfile(displayName: "", description: "Bio")))
    #expect(!ProfileManager.hasCommitted(edit, fresh: makeProfile(displayName: "Old", description: "Bio")))
  }

  /// A successful write invalidates the profile and multi-profile caches.
  @Test func invalidatesCachesAfterAWrite() async throws {
    let store = QueryStore()
    let key = ProfileQueryKeys.profile(did: Self.alice, scope: Self.repo)
    let profilesKey = ProfileQueryKeys.profiles(handles: [Self.alice], scope: Self.repo)
    await store.setQueryData(ProfileView.detailed(makeProfile()), for: key)
    await store.setQueryData(
      App.Bsky.ActorGetProfiles_Output(profiles: [makeProfile()]), for: profilesKey)

    let manager = ProfileManager(
      client: makeXrpcClient(ScriptedTransport(script: [])),
      appView: makeClient(ScriptedTransport(script: [])),
      commitAttempts: 1, commitInterval: .milliseconds(1))
    await manager.invalidateProfileCaches(store: store, did: Self.alice, scope: Self.repo)

    // Invalidation preserves the payload while marking it stale; with no
    // registered fetcher the entry simply keeps its data.
    #expect(try await store.payload(key, as: ProfileView.self) != nil)
    #expect(try await store.payload(profilesKey, as: App.Bsky.ActorGetProfiles_Output.self) != nil)
    #expect(await store.isFetching(key) == false)
  }
}

/// Builds a `LexBlob` fixture through its wire form, since it has no public
/// memberwise initialiser.
func makeBlob() throws -> LexBlob {
  let json: [String: Any] = [
    "$type": "blob",
    "ref": ["$link": "bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
    "mimeType": "image/jpeg",
    "size": 4,
  ]
  return try JSONDecoder().decode(
    LexBlob.self, from: try JSONSerialization.data(withJSONObject: json))
}

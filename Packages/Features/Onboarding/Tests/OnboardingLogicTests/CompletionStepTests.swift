import ATProtoClient
import Foundation
import Lexicons
import Preferences
import Testing

@testable import OnboardingLogic

@Suite("Completion step orchestration")
struct CompletionStepTests {

  private func makeRunner(
    actions: FakeOnboardingActionService = FakeOnboardingActionService(),
    joinedPack: String? = nil,
    interests: [String] = []
  ) -> (OnboardingStepRunner, FakeOnboardingActionService) {
    var wizard = OnboardingWizard()
    wizard.setInterestsResult(InterestsStepResult(selectedInterests: interests))
    wizard.setStarterPacksResult(StarterPacksStepResult(joinedStarterPackURI: joinedPack))
    let preferences = InMemoryPreferencesServer().engine()
    return (
      OnboardingStepRunner(wizard: wizard, actions: actions, preferences: preferences), actions
    )
  }

  @Test("the completion sequence is follows, interests, feeds, profile, nux")
  func completionSequence() async {
    let (runner, actions) = makeRunner(interests: ["art"])

    let outcome = await runner.runCompletionStep(displayName: "Alice")

    #expect(outcome == .advanced)
    #expect(
      actions.calls == [
        .createFollows(dids: [OnboardingConstants.bskyAppAccountDID], viaURI: nil),
        .setInterests(tags: ["art"]),
        .overwriteSavedFeeds(DefaultSavedFeeds.all),
        .upsertProfile(displayName: "Alice", avatarRef: nil, viaURI: nil),
        .upsertNux(id: OnboardingConstants.onboardingNuxID, completed: true, data: nil),
      ])
    #expect(runner.currentWizard.activeStep == .finished)
    #expect(runner.currentWizard.completion.isSettled(.finished))
  }

  @Test("the app account is always followed, even with no other selection")
  func followsAppAccount() async {
    let (runner, actions) = makeRunner()
    _ = await runner.runCompletionStep()
    #expect(
      actions.followCalls == [
        .createFollows(dids: [OnboardingConstants.bskyAppAccountDID], viaURI: nil)
      ])
  }

  @Test("a joined starter pack contributes its members and feeds")
  func joinedStarterPack() async {
    let actions = FakeOnboardingActionService()
    actions.configure(
      starterPack: Fixtures.starterPack(
        feedURIs: ["at://did:plc:creator/app.bsky.feed.generator/f"]),
      listMembers: ["did:plc:member1", "did:plc:member2"])
    let (runner, _) = makeRunner(
      actions: actions,
      joinedPack: "at://did:plc:creator/app.bsky.graph.starterpack/1")

    _ = await runner.runCompletionStep()

    #expect(
      actions.calls.contains(
        .getStarterPack(uri: "at://did:plc:creator/app.bsky.graph.starterpack/1")))
    #expect(
      actions.calls.contains(
        .getListMemberDIDs(listURI: "at://did:plc:test/app.bsky.graph.list/1")))
    #expect(
      actions.followCalls == [
        .createFollows(
          dids: [
            OnboardingConstants.bskyAppAccountDID, "did:plc:member1", "did:plc:member2",
          ],
          viaURI: "at://did:plc:test/app.bsky.graph.starterpack/1")
      ])
    // The pack's feed is pinned after the defaults.
    let expectedFeeds =
      DefaultSavedFeeds.all
      + [
        SavedFeed(
          type: "feed", value: "at://did:plc:creator/app.bsky.feed.generator/f",
          pinned: true)
      ]
    #expect(actions.savedFeedsWrites == [.overwriteSavedFeeds(expectedFeeds)])
    // The profile write carries the pack reference.
    #expect(
      actions.profileWrites == [
        .upsertProfile(
          displayName: "", avatarRef: nil,
          viaURI: "at://did:plc:test/app.bsky.graph.starterpack/1")
      ])
  }

  @Test("an unresolvable starter pack does not block the remaining writes")
  func unresolvableStarterPack() async {
    let actions = FakeOnboardingActionService()
    actions.configure(starterPackError: Fixtures.networkError())
    let (runner, _) = makeRunner(
      actions: actions, joinedPack: "at://did:plc:creator/app.bsky.graph.starterpack/1")

    let outcome = await runner.runCompletionStep()

    // The error is reported, but every other write still ran.
    guard case .failed = outcome else {
      Issue.record("expected the pack failure to be reported, got \(outcome)")
      return
    }
    #expect(actions.interestsWrites.count == 1)
    #expect(actions.savedFeedsWrites.count == 1)
    #expect(actions.profileWrites.count == 1)
    #expect(actions.nuxWrites.count == 1)
    #expect(
      actions.followCalls == [
        .createFollows(dids: [OnboardingConstants.bskyAppAccountDID], viaURI: nil)
      ])
  }

  @Test("a follow failure does not stop the other writes")
  func followFailureBestEffort() async {
    let actions = FakeOnboardingActionService()
    actions.configure(followError: Fixtures.networkError())
    let (runner, _) = makeRunner(actions: actions)

    let outcome = await runner.runCompletionStep()

    guard case .failed(.followFailed) = outcome else {
      Issue.record("expected a follow failure, got \(outcome)")
      return
    }
    #expect(actions.interestsWrites.count == 1)
    #expect(actions.savedFeedsWrites.count == 1)
    #expect(actions.profileWrites.count == 1)
    #expect(actions.nuxWrites.count == 1)
  }

  @Test("an avatar passed to completion is uploaded before the profile write")
  func avatarUploaded() async {
    let (runner, actions) = makeRunner()
    _ = await runner.runCompletionStep(
      avatarImageData: Data([9, 9]), avatarMimeType: "image/png")

    #expect(
      actions.calls.contains(.uploadAvatar(mimeType: "image/png", byteCount: 2)))
    #expect(
      actions.profileWrites == [
        .upsertProfile(displayName: "", avatarRef: "bafkreifakeblobref", viaURI: nil)
      ])
  }

  @Test("the NUX write can be suppressed")
  func nuxSuppressed() async {
    let (runner, actions) = makeRunner()
    _ = await runner.runCompletionStep(markNuxComplete: false)
    #expect(actions.nuxWrites.isEmpty)
  }

  @Test("a NUX write failure is best-effort and still settles the step")
  func nuxFailureBestEffort() async {
    let actions = FakeOnboardingActionService()
    actions.configure(nuxError: Fixtures.networkError())
    let (runner, _) = makeRunner(actions: actions)

    let outcome = await runner.runCompletionStep()

    guard case .failed = outcome else {
      Issue.record("expected the NUX failure to be reported, got \(outcome)")
      return
    }
    #expect(runner.currentWizard.activeStep == .finished)
    #expect(runner.currentWizard.completion.isSettled(.finished))
  }

  @Test("the default saved feeds match the RN constants, in order")
  func defaultSavedFeeds() {
    #expect(DefaultSavedFeeds.all.count == 3)
    #expect(
      DefaultSavedFeeds.all[0]
        == SavedFeed(type: "feed", value: DefaultSavedFeeds.discoverFeedURI, pinned: true))
    #expect(
      DefaultSavedFeeds.all[1] == SavedFeed(type: "timeline", value: "following", pinned: true))
    #expect(
      DefaultSavedFeeds.all[2]
        == SavedFeed(type: "feed", value: DefaultSavedFeeds.videoFeedURI, pinned: true))
  }
}

@Suite("Live action service wire behaviour")
struct LiveActionServiceTests {

  private func makeService(
    transport: ScriptedTransport, preferences: InMemoryPreferencesServer
  ) -> LiveOnboardingActionService {
    LiveOnboardingActionService(
      pds: XrpcClient(baseURL: "https://pds.test", transport: transport),
      preferences: preferences.engine(),
      appview: XrpcClient(baseURL: "https://pds.test", transport: transport),
      did: "did:plc:me",
      tids: SequentialTidGenerator(prefix: "3", startingAt: 0, width: 13))
  }

  @Test("follows are written via applyWrites with one create per subject")
  func applyWritesShape() async throws {
    let transport = ScriptedTransport(ScriptedTransport.json([:]))
    let service = makeService(transport: transport, preferences: InMemoryPreferencesServer())

    let uris = try await service.createFollows(dids: ["did:plc:one", "did:plc:two"], via: nil)

    let request = try #require(transport.lastRequest)
    #expect(request.method == "POST")
    #expect(request.xrpcMethod == "com.atproto.repo.applyWrites")
    let body = request.json
    #expect(body["repo"] as? String == "did:plc:me")
    let writes = try #require(body["writes"] as? [[String: Any]])
    #expect(writes.count == 2)
    #expect(
      writes[0]["$type"] as? String == "com.atproto.repo.applyWrites#create")
    #expect(writes[0]["collection"] as? String == "app.bsky.graph.follow")
    let value = try #require(writes[0]["value"] as? [String: Any])
    #expect(value["$type"] as? String == "app.bsky.graph.follow")
    #expect(value["subject"] as? String == "did:plc:one")
    #expect(value["via"] == nil)
    #expect(uris["did:plc:one"]?.hasPrefix("at://did:plc:me/app.bsky.graph.follow/") == true)
  }

  @Test("a starter pack reference is attached as `via`")
  func viaReference() async throws {
    let transport = ScriptedTransport(ScriptedTransport.json([:]))
    let service = makeService(transport: transport, preferences: InMemoryPreferencesServer())

    _ = try await service.createFollows(
      dids: ["did:plc:one"],
      via: StarterPackRef(uri: "at://did:plc:creator/app.bsky.graph.starterpack/1", cid: "cid1"))

    let writes = try #require(transport.lastRequest?.json["writes"] as? [[String: Any]])
    let value = try #require(writes[0]["value"] as? [String: Any])
    let via = try #require(value["via"] as? [String: Any])
    #expect(via["uri"] as? String == "at://did:plc:creator/app.bsky.graph.starterpack/1")
    #expect(via["cid"] as? String == "cid1")
  }

  @Test("follows are chunked at 50 writes per call")
  func chunking() async throws {
    let transport = ScriptedTransport.sticky(ScriptedTransport.json([:]))
    let service = makeService(transport: transport, preferences: InMemoryPreferencesServer())

    let dids = (0..<120).map { "did:plc:\($0)" }
    _ = try await service.createFollows(dids: dids, via: nil)

    let calls = transport.received.filter {
      $0.xrpcMethod == "com.atproto.repo.applyWrites"
    }
    #expect(calls.count == 3)
    let sizes = try calls.map { call -> Int in
      let writes = try #require(call.json["writes"] as? [[String: Any]])
      return writes.count
    }
    #expect(sizes == [50, 50, 20])
  }

  @Test("an empty DID list makes no call")
  func emptyFollows() async throws {
    let transport = ScriptedTransport(ScriptedTransport.json([:]))
    let service = makeService(transport: transport, preferences: InMemoryPreferencesServer())
    let uris = try await service.createFollows(dids: [], via: nil)
    #expect(uris.isEmpty)
    #expect(transport.received.isEmpty)
  }

  @Test("an avatar upload posts a multipart body and returns the blob ref")
  func avatarUpload() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "blob": [
          "$type": "blob",
          "ref": ["$link": "bafkreiavatar"],
          "mimeType": "image/jpeg",
          "size": 3,
        ]
      ]))
    let service = makeService(transport: transport, preferences: InMemoryPreferencesServer())

    let ref = try await service.uploadAvatar(data: Data([1, 2, 3]), mimeType: "image/jpeg")

    let request = try #require(transport.lastRequest)
    #expect(request.xrpcMethod == "com.atproto.repo.uploadBlob")
    #expect(request.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=") == true)
    #expect(ref.ref == "bafkreiavatar")
    #expect(ref.mimeType == "image/jpeg")
  }

  @Test("the profile write reads the existing record first and preserves its fields")
  func profileUpsertSpreadsExisting() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "uri": "at://did:plc:me/app.bsky.actor.profile/self",
        "value": [
          "$type": "app.bsky.actor.profile",
          "description": "existing bio",
          "createdAt": "2020-01-01T00:00:00.000Z",
        ],
      ]),
      ScriptedTransport.json(["uri": "at://did:plc:me/app.bsky.actor.profile/self"]))
    let service = makeService(transport: transport, preferences: InMemoryPreferencesServer())

    try await service.upsertProfile(avatar: nil, displayName: "Alice", joinedViaStarterPack: nil)

    #expect(
      transport.methods == [
        "com.atproto.repo.getRecord", "com.atproto.repo.putRecord",
      ])
    let record = try #require(transport.lastRequest?.json["record"] as? [String: Any])
    #expect(record["description"] as? String == "existing bio")
    #expect(record["displayName"] as? String == "Alice")
    // The existing createdAt is kept rather than overwritten.
    #expect(record["createdAt"] as? String == "2020-01-01T00:00:00.000Z")
  }

  @Test("a missing profile record is not an error")
  func missingProfileRecord() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json(["error": "RecordNotFound"], status: 400),
      ScriptedTransport.json(["uri": "at://did:plc:me/app.bsky.actor.profile/self"]))
    let service = makeService(transport: transport, preferences: InMemoryPreferencesServer())

    try await service.upsertProfile(avatar: nil, displayName: "Alice", joinedViaStarterPack: nil)

    let record = try #require(transport.lastRequest?.json["record"] as? [String: Any])
    #expect(record["displayName"] as? String == "Alice")
    #expect(record["createdAt"] != nil)
  }

  @Test("an avatar reference and starter pack are encoded into the profile record")
  func profileRecordFields() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json(["error": "RecordNotFound"], status: 400),
      ScriptedTransport.json(["uri": "at://did:plc:me/app.bsky.actor.profile/self"]))
    let service = makeService(transport: transport, preferences: InMemoryPreferencesServer())

    try await service.upsertProfile(
      avatar: OnboardingBlobRef(ref: "bafkreiavatar", mimeType: "image/jpeg", size: 10),
      displayName: "Alice",
      joinedViaStarterPack: StarterPackRef(
        uri: "at://did:plc:creator/app.bsky.graph.starterpack/1", cid: "cid1"))

    let record = try #require(transport.lastRequest?.json["record"] as? [String: Any])
    let avatar = try #require(record["avatar"] as? [String: Any])
    let ref = try #require(avatar["ref"] as? [String: Any])
    #expect(ref["$link"] as? String == "bafkreiavatar")
    let pack = try #require(record["joinedViaStarterPack"] as? [String: Any])
    #expect(pack["cid"] as? String == "cid1")
  }

  @Test("interests are written through the preferences engine")
  func interestsThroughEngine() async throws {
    let transport = ScriptedTransport(ScriptedTransport.json([:]))
    let server = InMemoryPreferencesServer()
    let service = makeService(transport: transport, preferences: server)

    try await service.setInterests(tags: ["art", "music"])

    #expect(
      server.methods == [
        "app.bsky.actor.getPreferences", "app.bsky.actor.putPreferences",
      ])
    let written = server.lastWrittenPreferences
    let interestsPref = try #require(
      written.first { $0.objectValue?["$type"]?.stringValue == "app.bsky.actor.defs#interestsPref" }
    )
    let tags = try #require(interestsPref.objectValue?["tags"]?.stringArrayValue)
    #expect(tags == ["art", "music"])
  }

  @Test("the NUX write lands in the app-state preference")
  func nuxThroughEngine() async throws {
    let transport = ScriptedTransport(ScriptedTransport.json([:]))
    let server = InMemoryPreferencesServer()
    let service = makeService(transport: transport, preferences: server)

    try await service.upsertNux(id: "onboarding", completed: true, data: nil)

    let appState = try #require(
      server.lastWrittenPreferences.first {
        $0.objectValue?["$type"]?.stringValue == "app.bsky.actor.defs#bskyAppStatePref"
      })
    let nuxs = try #require(
      appState.objectValue?["nuxs"].flatMap { value -> [[String: JSONValue]]? in
        guard case .array(let items) = value else { return nil }
        return items.compactMap(\.objectValue)
      })
    #expect(nuxs.count == 1)
    #expect(nuxs[0]["id"]?.stringValue == "onboarding")
    #expect(nuxs[0]["completed"]?.boolValue == true)
  }

  @Test("saved feeds are written through the preferences engine with minted ids")
  func savedFeedsThroughEngine() async throws {
    let transport = ScriptedTransport(ScriptedTransport.json([:]))
    let server = InMemoryPreferencesServer()
    let service = makeService(transport: transport, preferences: server)

    try await service.overwriteSavedFeeds(DefaultSavedFeeds.all)

    let savedFeeds = try #require(
      server.lastWrittenPreferences.first {
        $0.objectValue?["$type"]?.stringValue == "app.bsky.actor.defs#savedFeedsPrefV2"
      })
    let items = try #require(
      savedFeeds.objectValue?["items"].flatMap { value -> [[String: JSONValue]]? in
        guard case .array(let values) = value else { return nil }
        return values.compactMap(\.objectValue)
      })
    #expect(items.count == 3)
    for item in items {
      #expect(item["id"]?.stringValue != nil)
    }
  }

  @Test("getStarterPack reads the pack and projects list and feeds")
  func getStarterPack() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "starterPack": [
          "uri": "at://did:plc:creator/app.bsky.graph.starterpack/1",
          "cid": "bafkreipack",
          "creator": ["did": "did:plc:creator", "handle": "creator.test"],
          "indexedAt": "2024-01-01T00:00:00.000Z",
          "list": [
            "uri": "at://did:plc:creator/app.bsky.graph.list/1",
            "cid": "bafkreilist",
            "name": "Birds list",
            "purpose": "app.bsky.graph.defs#referencelist",
          ],
          "feeds": [
            [
              "uri": "at://did:plc:creator/app.bsky.feed.generator/f",
              "cid": "bafkreifeed",
              "did": "did:plc:creator",
              "displayName": "Feed",
              "indexedAt": "2024-01-01T00:00:00.000Z",
              "creator": ["did": "did:plc:creator", "handle": "creator.test"],
            ]
          ],
          "record": [
            "$type": "app.bsky.graph.starterpack", "name": "Birds",
            "list": "at://did:plc:creator/app.bsky.graph.list/1",
            "createdAt": "2024-01-01T00:00:00.000Z",
          ],
        ]
      ]))
    let service = makeService(transport: transport, preferences: InMemoryPreferencesServer())

    let detail = try await service.getStarterPack(
      uri: "at://did:plc:creator/app.bsky.graph.starterpack/1")

    let request = try #require(transport.lastRequest)
    #expect(request.xrpcMethod == "app.bsky.graph.getStarterPack")
    #expect(request.query["starterPack"] == "at://did:plc:creator/app.bsky.graph.starterpack/1")
    #expect(detail.ref.cid == "bafkreipack")
    #expect(detail.listURI == "at://did:plc:creator/app.bsky.graph.list/1")
    #expect(detail.feedURIs == ["at://did:plc:creator/app.bsky.feed.generator/f"])
  }

  @Test("getListMemberDIDs follows the cursor")
  func listMembersPaging() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "items": [
          [
            "subject": ["did": "did:plc:a", "handle": "a.test"],
            "uri": "at://did:plc:creator/app.bsky.graph.listitem/1",
          ]
        ],
        "list": [
          "uri": "at://did:plc:creator/app.bsky.graph.list/1",
          "cid": "bafkreilist",
          "name": "Birds list",
          "purpose": "app.bsky.graph.defs#referencelist",
          "creator": ["did": "did:plc:creator", "handle": "creator.test"],
          "indexedAt": "2024-01-01T00:00:00.000Z",
        ],
        "cursor": "next-page",
      ]),
      ScriptedTransport.json([
        "items": [
          [
            "subject": ["did": "did:plc:b", "handle": "b.test"],
            "uri": "at://did:plc:creator/app.bsky.graph.listitem/2",
          ]
        ],
        "list": [
          "uri": "at://did:plc:creator/app.bsky.graph.list/1",
          "cid": "bafkreilist",
          "name": "Birds list",
          "purpose": "app.bsky.graph.defs#referencelist",
          "creator": ["did": "did:plc:creator", "handle": "creator.test"],
          "indexedAt": "2024-01-01T00:00:00.000Z",
        ],
      ]))
    let service = makeService(transport: transport, preferences: InMemoryPreferencesServer())

    let dids = try await service.getListMemberDIDs(
      listURI: "at://did:plc:creator/app.bsky.graph.list/1")

    #expect(dids == ["did:plc:a", "did:plc:b"])
    let calls = transport.received.filter { $0.xrpcMethod == "app.bsky.graph.getList" }
    #expect(calls.count == 2)
    #expect(calls[0].query["list"] == "at://did:plc:creator/app.bsky.graph.list/1")
    #expect(calls[0].query["limit"] == "100")
    #expect(calls[0].query["cursor"] == nil)
    #expect(calls[1].query["cursor"] == "next-page")
  }
}

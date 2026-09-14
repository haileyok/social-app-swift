import ATProtoClient
import Foundation
import Lexicons
import Testing

@testable import OnboardingLogic

@Suite("Live suggestion service wire behaviour")
struct LiveSuggestionServiceTests {

  private func client(_ transport: ScriptedTransport) -> XrpcClient {
    XrpcClient(
      baseURL: "https://api.bsky.app", proxyService: "did:web:api.bsky.app#bsky_appview",
      extraHeaders: ["Authorization": "Bearer access-jwt"], transport: transport)
  }

  @Test("suggested users calls the onboarding endpoint with category and limit")
  func suggestedUsersCall() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "actors": [
          [
            "did": "did:plc:one", "handle": "one.test", "displayName": "One",
            "viewer": ["following": "at://did:plc:me/app.bsky.graph.follow/1"],
          ],
          ["did": "did:plc:two", "handle": "two.test"],
        ],
        "recIdStr": "rec-123",
      ]))
    let service = LiveOnboardingSuggestionService(client: client(transport))

    let page = try await service.suggestedUsers(
      category: "art", limit: 10, interests: ["art", "music"])

    let request = try #require(transport.lastRequest)
    #expect(request.xrpcMethod == "app.bsky.unspecced.getSuggestedOnboardingUsers")
    #expect(request.query["category"] == "art")
    #expect(request.query["limit"] == "10")
    #expect(request.headers["X-Bsky-Topics"] == "art,music")
    // The session's own headers survive the merge.
    #expect(request.headers["Authorization"] == "Bearer access-jwt")
    #expect(request.headers["atproto-proxy"] == "did:web:api.bsky.app#bsky_appview")
    #expect(page.actors.count == 2)
    #expect(page.actors[0].did == "did:plc:one")
    #expect(page.actors[0].viewerFollowing == "at://did:plc:me/app.bsky.graph.follow/1")
    #expect(page.recID == "rec-123")
  }

  @Test("a nil category omits the query parameter")
  func nilCategoryOmitted() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json(["actors": []]))
    let service = LiveOnboardingSuggestionService(client: client(transport))
    _ = try await service.suggestedUsers(category: nil, limit: 10, interests: [])
    let request = try #require(transport.lastRequest)
    #expect(request.query["category"] == nil)
    #expect(request.query["limit"] == "10")
  }

  @Test("the deprecated recId is the fallback when recIdStr is absent")
  func recIdFallback() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json(["actors": [], "recId": "deprecated-rec"]))
    let service = LiveOnboardingSuggestionService(client: client(transport))
    let page = try await service.suggestedUsers(category: nil, limit: 10, interests: [])
    #expect(page.recID == "deprecated-rec")
  }

  @Test("blocked or muted viewer state is projected onto the suggested user")
  func viewerStateProjection() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "actors": [
          ["did": "did:plc:one", "handle": "one.test", "viewer": ["muted": true]],
          ["did": "did:plc:two", "handle": "two.test", "viewer": ["blockedBy": true]],
          [
            "did": "did:plc:three", "handle": "three.test",
            "viewer": ["blocking": "at://did:plc:me/app.bsky.graph.block/1"],
          ],
        ]
      ]))
    let service = LiveOnboardingSuggestionService(client: client(transport))
    let page = try await service.suggestedUsers(category: nil, limit: 10, interests: [])
    #expect(page.actors[0].isMuted)
    #expect(page.actors[1].isBlockedOrBlocking)
    #expect(page.actors[2].isBlockedOrBlocking)
  }

  @Test("starter packs calls the onboarding endpoint with a limit of 6")
  func starterPacksCall() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "starterPacks": [
          [
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
              "$type": "app.bsky.graph.starterpack",
              "name": "Birds",
              "list": "at://did:plc:creator/app.bsky.graph.list/1",
              "createdAt": "2024-01-01T00:00:00.000Z",
            ],
          ]
        ]
      ]))
    let service = LiveOnboardingSuggestionService(client: client(transport))

    let packs = try await service.suggestedStarterPacks(limit: 6, interests: ["nature"])

    let request = try #require(transport.lastRequest)
    #expect(request.xrpcMethod == "app.bsky.unspecced.getOnboardingSuggestedStarterPacks")
    #expect(request.query["limit"] == "6")
    #expect(request.headers["X-Bsky-Topics"] == "nature")
    #expect(packs.count == 1)
    #expect(packs[0].name == "Birds")
    #expect(packs[0].listURI == "at://did:plc:creator/app.bsky.graph.list/1")
    #expect(packs[0].feedURIs == ["at://did:plc:creator/app.bsky.feed.generator/f"])
  }

  @Test("a server error propagates")
  func serverError() async {
    let transport = ScriptedTransport.sticky(
      ScriptedTransport.json(["error": "InternalServerError"], status: 500))
    let service = LiveOnboardingSuggestionService(client: client(transport))
    await #expect(throws: (any Error).self) {
      _ = try await service.suggestedUsers(category: nil, limit: 10, interests: [])
    }
  }
}

@Suite("Handle availability")
struct HandleAvailabilityTests {

  private func client(_ transport: ScriptedTransport) -> XrpcClient {
    XrpcClient(baseURL: "https://bsky.social", transport: transport)
  }

  @Test("the entryway strategy is selected for the Bluesky service DID")
  func strategySelection() {
    #expect(
      LiveHandleAvailabilityService.strategy(forServiceDID: OnboardingConstants.blueskyServiceDID)
        == .entryway)
    #expect(
      LiveHandleAvailabilityService.strategy(forServiceDID: "did:web:example.com")
        == .resolveHandle)
  }

  @Test("an available result maps to available")
  func availableResult() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "handle": "alice.test",
        "result": ["$type": "com.atproto.temp.checkHandleAvailability#resultAvailable"],
      ]))
    let service = LiveHandleAvailabilityService(strategy: .entryway, client: client(transport))

    let result = try await service.checkHandleAvailability(handle: "alice.test")

    let request = try #require(transport.lastRequest)
    #expect(request.xrpcMethod == "com.atproto.temp.checkHandleAvailability")
    #expect(request.query["handle"] == "alice.test")
    #expect(result == .available)
  }

  @Test("an unavailable result carries the suggestions")
  func unavailableResult() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "handle": "alice.test",
        "result": [
          "$type": "com.atproto.temp.checkHandleAvailability#resultUnavailable",
          "suggestions": [
            ["handle": "alice1.test", "method": "suffix"],
            ["handle": "alice2.test", "method": "suffix"],
          ],
        ],
      ]))
    let service = LiveHandleAvailabilityService(strategy: .entryway, client: client(transport))

    let result = try await service.checkHandleAvailability(handle: "alice.test")

    #expect(result == .unavailable(suggestions: ["alice1.test", "alice2.test"]))
  }

  @Test("birthDate and email are forwarded when supplied")
  func birthDateAndEmail() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "handle": "alice.test",
        "result": ["$type": "com.atproto.temp.checkHandleAvailability#resultAvailable"],
      ]))
    let service = LiveHandleAvailabilityService(
      strategy: .entryway, client: client(transport), birthDate: "2000-01-01", email: "a@b.c")
    _ = try await service.checkHandleAvailability(handle: "alice.test")
    let request = try #require(transport.lastRequest)
    #expect(request.query["birthDate"] == "2000-01-01")
    #expect(request.query["email"] == "a@b.c")
  }

  @Test("the resolve-handle fallback reports a resolved handle as taken")
  func resolveHandleTaken() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json(["did": "did:plc:someone"]))
    let service = LiveHandleAvailabilityService(
      strategy: .resolveHandle, client: client(transport))

    let result = try await service.checkHandleAvailability(handle: "taken.test")

    let request = try #require(transport.lastRequest)
    #expect(request.xrpcMethod == "com.atproto.identity.resolveHandle")
    #expect(request.query["handle"] == "taken.test")
    #expect(result == .unavailable(suggestions: []))
  }

  @Test("the resolve-handle fallback treats a failure as available")
  func resolveHandleFailure() async throws {
    let transport = ScriptedTransport.sticky(
      ScriptedTransport.json(["error": "InvalidRequest"], status: 400))
    let service = LiveHandleAvailabilityService(
      strategy: .resolveHandle, client: client(transport))

    let result = try await service.checkHandleAvailability(handle: "free.test")

    #expect(result == .available)
  }

  @Test("an unrecognized entryway result throws")
  func unrecognizedResult() async {
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "handle": "alice.test",
        "result": ["$type": "com.atproto.temp.checkHandleAvailability#surprise"],
      ]))
    let service = LiveHandleAvailabilityService(strategy: .entryway, client: client(transport))
    await #expect(throws: OnboardingError.self) {
      _ = try await service.checkHandleAvailability(handle: "alice.test")
    }
  }
}

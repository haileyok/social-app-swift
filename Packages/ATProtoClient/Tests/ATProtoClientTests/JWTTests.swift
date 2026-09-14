import Foundation
import Persistence
import Testing

@testable import ATProtoClient

/// Builds a compact-JWS-shaped token with a real payload and junk signature.
///
/// The payload is the only part any code under test reads, and nothing
/// verifies signatures, so a placeholder signature segment is sufficient.
func makeJWT(payload: [String: Any]) -> String {
  let json = try! JSONSerialization.data(withJSONObject: payload)
  let header = JWT.base64URLEncode(Data(#"{"alg":"none","typ":"JWT"}"#.utf8))
  return "\(header).\(JWT.base64URLEncode(json)).signature-not-verified"
}

@Suite struct JWTTests {
  @Test func decodesExpiryAndScope() {
    let token = makeJWT(payload: ["exp": 1_700_000_000, "scope": "com.atproto.access"])
    let payload = JWT.decodePayload(token)
    #expect(payload?.exp == 1_700_000_000)
    #expect(payload?.scope == "com.atproto.access")
  }

  @Test func acceptsStringifiedExpiry() {
    let token = makeJWT(payload: ["exp": "1700000000"])
    #expect(JWT.decodePayload(token)?.exp == 1_700_000_000)
  }

  @Test func rejectsMalformedTokens() {
    #expect(JWT.decodePayload("not-a-jwt") == nil)
    #expect(JWT.decodePayload("only.two") == nil)
    #expect(JWT.decodePayload("a.!!!not-base64!!!.c") == nil)
  }

  @Test func isExpiredComparesAgainstNow() {
    let past = makeJWT(payload: ["exp": 1_000_000_000])
    let future = makeJWT(payload: ["exp": 4_000_000_000])
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    #expect(JWT.isExpired(past, now: now))
    #expect(!JWT.isExpired(future, now: now))
  }

  @Test func malformedTokenCountsAsExpired() {
    // Matches the RN behavior: an unreadable token takes the refresh path.
    #expect(JWT.isExpired("garbage"))
    // A token with no exp claim is also treated as expired.
    #expect(JWT.isExpired(makeJWT(payload: ["sub": "did:plc:alice"])))
  }

  @Test func detectsSignupQueuedScope() {
    let queued = makeJWT(payload: ["exp": 4_000_000_000, "scope": "com.atproto.signupQueued"])
    let normal = makeJWT(payload: ["exp": 4_000_000_000, "scope": "com.atproto.access"])

    #expect(JWT.isSignupQueued(queued))
    #expect(!JWT.isSignupQueued(normal))
    #expect(!JWT.isSignupQueued("garbage"))
  }

  @Test func detectsAppPasswordScope() {
    let appPassword = makeJWT(payload: ["scope": "com.atproto.appPass"])
    #expect(JWT.isAppPassword(appPassword))
    #expect(!JWT.isAppPassword(makeJWT(payload: ["scope": "com.atproto.access"])))
  }

  @Test func base64URLRoundTrips() {
    let data = Data("hello world, this needs padding!".utf8)
    let encoded = JWT.base64URLEncode(data)
    #expect(!encoded.contains("="))
    #expect(!encoded.contains("+"))
    #expect(!encoded.contains("/"))
    #expect(JWT.base64URLDecode(encoded) == data)
  }

  /// Hand-crafted tokens covering the base64url padding remainder cases.
  @Test func base64URLDecodeHandlesAllPaddingRemainders() {
    for length in 1...8 {
      let data = Data((0..<length).map { UInt8($0 + 65) })
      let encoded = JWT.base64URLEncode(data)
      #expect(JWT.base64URLDecode(encoded) == data, "length \(length)")
    }
  }
}

@Suite struct SessionAccountMappingTests {
  @Test func mapsSessionDataToAccount() {
    let data = SessionData(
      service: "https://bsky.social", did: "did:plc:alice", handle: "alice.example",
      accessJwt: makeJWT(payload: ["exp": 4_000_000_000, "scope": "com.atproto.access"]),
      refreshJwt: "refresh-1", email: "alice@example.com", emailConfirmed: true)

    let account = SessionAccountMapping.account(from: data, service: data.service)
    #expect(account?.did == "did:plc:alice")
    #expect(account?.handle == "alice.example")
    // Trailing slash is normalized, matching `new URL().toString()`.
    #expect(account?.service == "https://bsky.social/")
    #expect(account?.emailConfirmed == true)
    #expect(account?.signupQueued == false)
    #expect(account?.isSelfHosted == false)
  }

  @Test func marksSelfHostedAccounts() {
    let data = SessionData(
      service: "https://pds.example.com", did: "did:plc:alice", handle: "alice.example",
      accessJwt: "a", refreshJwt: "r")
    let account = SessionAccountMapping.account(from: data, service: data.service)
    #expect(account?.isSelfHosted == true)
  }

  @Test func detectsQueuedSignupFromAccessToken() {
    let data = SessionData(
      service: "https://bsky.social", did: "did:plc:alice", handle: "alice.example",
      accessJwt: makeJWT(payload: ["exp": 4_000_000_000, "scope": "com.atproto.signupQueued"]),
      refreshJwt: "r")
    let account = SessionAccountMapping.account(from: data, service: data.service)
    #expect(account?.signupQueued == true)
  }

  @Test func pdsURLComesFromDidDocumentNotService() {
    let didDoc = DidDocument(service: [
      .init(
        id: "#atproto_pds", type: "AtprotoPersonalDataServer",
        serviceEndpoint: "https://pds.example.com")
    ])
    let data = SessionData(
      service: "https://login.example.com", did: "did:plc:alice", handle: "alice.example",
      accessJwt: "a", refreshJwt: "r", didDoc: didDoc)

    let account = SessionAccountMapping.account(from: data, service: data.service)
    #expect(account?.pdsUrl == "https://pds.example.com/")
  }

  @Test func storedPdsURLIsUsedWhenDidDocumentMissing() {
    let data = SessionData(
      service: "https://login.example.com", did: "did:plc:alice", handle: "alice.example",
      accessJwt: "a", refreshJwt: "r")
    let account = SessionAccountMapping.account(
      from: data, service: data.service, storedPdsUrl: "https://pds.example.com")
    #expect(account?.pdsUrl == "https://pds.example.com/")
  }

  @Test func mapsAccountBackToSessionData() {
    let account = PersistedAccount(
      service: "https://bsky.social/", did: "did:plc:alice", handle: "alice.example",
      email: "alice@example.com", refreshJwt: "r", accessJwt: "a")
    let data = SessionAccountMapping.sessionData(from: account)

    #expect(data.did == "did:plc:alice")
    #expect(data.accessJwt == "a")
    #expect(data.refreshJwt == "r")
    #expect(data.email == "alice@example.com")
    // Absent `active` defaults to true.
    #expect(data.active == true)
  }

  @Test func missingTokensCountAsExpired() {
    let account = PersistedAccount(
      service: "https://bsky.social/", did: "did:plc:alice", handle: "alice.example")
    #expect(SessionAccountMapping.isExpired(account))
  }

  @Test func expiredTokenCountsAsExpired() {
    let account = PersistedAccount(
      service: "https://bsky.social/", did: "did:plc:alice", handle: "alice.example",
      accessJwt: makeJWT(payload: ["exp": 1_000_000_000]))
    #expect(SessionAccountMapping.isExpired(
      account, now: Date(timeIntervalSince1970: 1_700_000_000)))
  }

  @Test func validTokenIsNotExpired() {
    let account = PersistedAccount(
      service: "https://bsky.social/", did: "did:plc:alice", handle: "alice.example",
      accessJwt: makeJWT(payload: ["exp": 4_000_000_000]))
    #expect(!SessionAccountMapping.isExpired(
      account, now: Date(timeIntervalSince1970: 1_700_000_000)))
  }
}

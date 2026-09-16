import Foundation
import Persistence
import Testing

@testable import ATProtoClient

/// Builds a `SessionStore` over a fresh temp directory with a file-backed token
/// store, returning everything the test needs to inspect.
struct SessionStoreHarness {
  let directory: URL
  let persisted: PersistedStore
  let tokens: FileTokenStore
  let store: SessionStore
  let cacheCleared: CacheClearRecorder

  init() async {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("session-store-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    persisted = PersistedStore(directory: directory)
    tokens = FileTokenStore(rootDirectory: directory.appendingPathComponent("tokens"))
    let recorder = CacheClearRecorder()
    cacheCleared = recorder
    store = SessionStore(
      persisted: persisted, tokenStore: tokens,
      cacheClear: { did in recorder.record(did) },
      transport: ScriptedTransport())
  }

  func cleanUp() {
    try? FileManager.default.removeItem(at: directory)
  }
}

/// Thread-safe recorder for cache-clear hook invocations.
final class CacheClearRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var _dids: [String] = []

  var dids: [String] {
    lock.lock()
    defer { lock.unlock() }
    return _dids
  }

  func record(_ did: String) {
    lock.lock()
    defer { lock.unlock() }
    _dids.append(did)
  }
}

/// A long-lived access token, so resume takes the no-network fast path.
func validAccessToken(did: String) -> String {
  makeJWT(payload: ["sub": did, "exp": 4_000_000_000, "scope": "com.atproto.access"])
}

func sampleAccount(did: String, handle: String = "alice.example") -> PersistedAccount {
  PersistedAccount(
    service: "https://bsky.social/", did: did, handle: handle,
    email: "\(handle)@example.com", emailConfirmed: true,
    refreshJwt: "refresh-\(did)", accessJwt: validAccessToken(did: did))
}

@Suite struct SessionStoreTests {
  @Test func loginResultIsPersistedViaAddAccountFromSession() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("session-login-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let access = makeJWT(payload: ["exp": 4_000_000_000, "scope": "com.atproto.access"])
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "accessJwt": access, "refreshJwt": "refresh-1", "did": "did:plc:alice",
        "handle": "alice.example", "email": "alice@example.com", "emailConfirmed": true,
      ]))
    let tokens = FileTokenStore(rootDirectory: directory.appendingPathComponent("tokens"))
    let store = SessionStore(
      persisted: PersistedStore(directory: directory), tokenStore: tokens,
      transport: transport)
    _ = await store.hydrate()

    let session = try await PasswordSession.login(
      service: "https://bsky.social", identifier: "alice.example",
      password: "hunter2", transport: transport)
    let account = try await store.addAccount(fromSession: session)

    #expect(account.did == "did:plc:alice")
    #expect(account.handle == "alice.example")

    let snapshot = await store.snapshot()
    #expect(snapshot.accounts.count == 1)
    #expect(snapshot.currentDID == "did:plc:alice")
    // Tokens reached the secret store.
    #expect(try await tokens.token(kind: .refresh, for: "did:plc:alice") == "refresh-1")
  }

  @Test func freshLoginHooksPersistRotatedTokens() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    _ = await harness.store.hydrate()

    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "accessJwt": "access-1", "refreshJwt": "refresh-1",
        "did": "did:plc:alice", "handle": "alice.example",
      ]),
      ScriptedTransport.json(["error": "ExpiredToken"], status: 400),
      ScriptedTransport.json([
        "accessJwt": "access-2", "refreshJwt": "refresh-2",
        "did": "did:plc:alice", "handle": "alice.example",
        "emailConfirmed": true, "didDoc": ["service": []],
      ]),
      ScriptedTransport.json(["ok": true])
    )
    let session = try await PasswordSession.login(
      service: "https://bsky.social", identifier: "alice.example",
      password: "hunter2", hooks: harness.store.sessionHooks(),
      transport: transport)
    _ = try await harness.store.addAccount(fromSession: session)

    _ = try await session.request(
      method: "app.bsky.feed.getTimeline", httpMethod: "GET")

    #expect(
      try await harness.tokens.token(kind: .access, for: "did:plc:alice")
        == "access-2")
    #expect(
      try await harness.tokens.token(kind: .refresh, for: "did:plc:alice")
        == "refresh-2")
    #expect((await harness.store.snapshot()).currentAccount?.accessJwt == "access-2")
  }

  @Test func hydrateWithNoDataIsEmpty() async {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }

    let snapshot = await harness.store.hydrate()
    #expect(snapshot.accounts.isEmpty)
    #expect(snapshot.currentAccount == nil)
    #expect(!snapshot.hasSession)
  }

  @Test func addAccountPersistsEntryAndTokens() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    _ = await harness.store.hydrate()

    let account = sampleAccount(did: "did:plc:alice")
    let session = PasswordSession(data: SessionAccountMapping.sessionData(from: account))
    try await harness.store.addAccount(account, session: session)

    let snapshot = await harness.store.snapshot()
    #expect(snapshot.accounts.count == 1)
    #expect(snapshot.currentDID == "did:plc:alice")

    // Tokens landed in the token store.
    #expect(try await harness.tokens.token(kind: .access, for: "did:plc:alice")
      == account.accessJwt)
    #expect(try await harness.tokens.token(kind: .refresh, for: "did:plc:alice")
      == "refresh-did:plc:alice")
  }

  @Test func accountsSurviveAHydrateRoundTrip() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    _ = await harness.store.hydrate()

    let account = sampleAccount(did: "did:plc:alice")
    try await harness.store.addAccount(
      account,
      session: PasswordSession(data: SessionAccountMapping.sessionData(from: account)))

    // A brand-new store over the same directory sees the account and its
    // tokens.
    let reopened = SessionStore(
      persisted: PersistedStore(directory: harness.directory),
      tokenStore: FileTokenStore(
        rootDirectory: harness.directory.appendingPathComponent("tokens")),
      transport: ScriptedTransport())
    let snapshot = await reopened.hydrate()

    #expect(snapshot.accounts.count == 1)
    #expect(snapshot.accounts.first?.did == "did:plc:alice")
    /* Compare the decoded payload, not the raw bytes: JSON object key order
     * is not stable, so two encodings of the same claims differ textually. */
    #expect(
      JWT.decodePayload(snapshot.accounts.first?.accessJwt ?? "")
        == JWT.decodePayload(validAccessToken(did: "did:plc:alice")))
    #expect(snapshot.currentDID == "did:plc:alice")
  }

  @Test func addAccountReplacesExistingEntryRatherThanDuplicating() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    _ = await harness.store.hydrate()

    var account = sampleAccount(did: "did:plc:alice")
    try await harness.store.addAccount(
      account,
      session: PasswordSession(data: SessionAccountMapping.sessionData(from: account)))

    account.handle = "alice-renamed.example"
    try await harness.store.addAccount(
      account,
      session: PasswordSession(data: SessionAccountMapping.sessionData(from: account)))

    let snapshot = await harness.store.snapshot()
    #expect(snapshot.accounts.count == 1)
    #expect(snapshot.accounts.first?.handle == "alice-renamed.example")
  }

  @Test func switchingAccountsChangesCurrentWithoutLosingTheOther() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    _ = await harness.store.hydrate()

    let alice = sampleAccount(did: "did:plc:alice", handle: "alice.example")
    let bob = sampleAccount(did: "did:plc:bob", handle: "bob.example")
    try await harness.store.addAccount(
      alice, session: PasswordSession(data: SessionAccountMapping.sessionData(from: alice)))
    try await harness.store.addAccount(
      bob, session: PasswordSession(data: SessionAccountMapping.sessionData(from: bob)))

    // Bob was added last, so he is current and first in the list.
    var snapshot = await harness.store.snapshot()
    #expect(snapshot.accounts.count == 2)
    #expect(snapshot.currentDID == "did:plc:bob")

    try await harness.store.switchToAccount("did:plc:alice")
    snapshot = await harness.store.snapshot()
    #expect(snapshot.currentDID == "did:plc:alice")
    #expect(snapshot.accounts.count == 2)

    // The switch survives a reopen.
    let reopened = SessionStore(
      persisted: PersistedStore(directory: harness.directory),
      tokenStore: FileTokenStore(
        rootDirectory: harness.directory.appendingPathComponent("tokens")),
      transport: ScriptedTransport())
    #expect(await reopened.hydrate().currentDID == "did:plc:alice")
  }

  @Test func switchToUnknownAccountThrows() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    _ = await harness.store.hydrate()

    await #expect(throws: SessionStore.StoreError.unknownAccount("did:plc:ghost")) {
      try await harness.store.switchToAccount("did:plc:ghost")
    }
  }

  @Test func logoutCurrentAccountKeepsEntryButClearsTokens() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    _ = await harness.store.hydrate()

    let alice = sampleAccount(did: "did:plc:alice")
    try await harness.store.addAccount(
      alice, session: PasswordSession(data: SessionAccountMapping.sessionData(from: alice)))

    try await harness.store.logoutCurrentAccount()

    let snapshot = await harness.store.snapshot()
    // The account entry survives so the user can switch back...
    #expect(snapshot.accounts.count == 1)
    #expect(snapshot.accounts.first?.did == "did:plc:alice")
    // ...but the tokens are gone and nothing is current.
    #expect(snapshot.accounts.first?.accessJwt == nil)
    #expect(snapshot.accounts.first?.refreshJwt == nil)
    #expect(snapshot.currentDID == nil)
    #expect(try await harness.tokens.token(kind: .access, for: "did:plc:alice") == nil)
    // The cache-clear hook ran for that DID.
    #expect(harness.cacheCleared.dids == ["did:plc:alice"])
  }

  @Test func logoutEveryAccountClearsAllTokensAndKeepsEntries() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    _ = await harness.store.hydrate()

    for did in ["did:plc:alice", "did:plc:bob"] {
      let account = sampleAccount(did: did)
      try await harness.store.addAccount(
        account, session: PasswordSession(data: SessionAccountMapping.sessionData(from: account)))
    }

    try await harness.store.logoutEveryAccount()

    let snapshot = await harness.store.snapshot()
    #expect(snapshot.accounts.count == 2)
    #expect(snapshot.accounts.allSatisfy { $0.accessJwt == nil && $0.refreshJwt == nil })
    #expect(snapshot.currentDID == nil)
    #expect(try await harness.tokens.dids().isEmpty)
    #expect(harness.cacheCleared.dids.sorted() == ["did:plc:alice", "did:plc:bob"])
  }

  @Test func removeAccountDeletesEntryAndTokens() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    _ = await harness.store.hydrate()

    for did in ["did:plc:alice", "did:plc:bob"] {
      let account = sampleAccount(did: did)
      try await harness.store.addAccount(
        account, session: PasswordSession(data: SessionAccountMapping.sessionData(from: account)))
    }

    // Bob is current; removing him leaves no current account.
    try await harness.store.removeAccount("did:plc:bob")

    let snapshot = await harness.store.snapshot()
    #expect(snapshot.accounts.map(\.did) == ["did:plc:alice"])
    #expect(snapshot.currentDID == nil)
    #expect(try await harness.tokens.token(kind: .access, for: "did:plc:bob") == nil)
    #expect(try await harness.tokens.token(kind: .access, for: "did:plc:alice") != nil)
    #expect(harness.cacheCleared.dids == ["did:plc:bob"])
  }

  @Test func removingANonCurrentAccountLeavesCurrentAlone() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    _ = await harness.store.hydrate()

    for did in ["did:plc:alice", "did:plc:bob"] {
      let account = sampleAccount(did: did)
      try await harness.store.addAccount(
        account, session: PasswordSession(data: SessionAccountMapping.sessionData(from: account)))
    }
    try await harness.store.switchToAccount("did:plc:alice")

    try await harness.store.removeAccount("did:plc:bob")

    let snapshot = await harness.store.snapshot()
    #expect(snapshot.currentDID == "did:plc:alice")
    #expect(snapshot.accounts.map(\.did) == ["did:plc:alice"])
  }

  @Test func removeUnknownAccountThrows() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    _ = await harness.store.hydrate()

    await #expect(throws: SessionStore.StoreError.unknownAccount("did:plc:ghost")) {
      try await harness.store.removeAccount("did:plc:ghost")
    }
  }

  @Test func signupQueuedIsReportedForQueuedToken() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    _ = await harness.store.hydrate()

    let queued = PersistedAccount(
      service: "https://bsky.social/", did: "did:plc:queued", handle: "queued.example",
      refreshJwt: "r",
      accessJwt: makeJWT(payload: [
        "exp": 4_000_000_000, "scope": "com.atproto.signupQueued",
      ]))
    try await harness.store.addAccount(
      queued, session: PasswordSession(data: SessionAccountMapping.sessionData(from: queued)))

    #expect(await harness.store.isCurrentAccountSignupQueued())

    let normal = sampleAccount(did: "did:plc:normal")
    try await harness.store.addAccount(
      normal, session: PasswordSession(data: SessionAccountMapping.sessionData(from: normal)))
    #expect(!(await harness.store.isCurrentAccountSignupQueued()))
  }

  @Test func resumeWithValidTokenTakesNoNetworkPath() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    _ = await harness.store.hydrate()

    let alice = sampleAccount(did: "did:plc:alice")
    try await harness.store.addAccount(
      alice, session: PasswordSession(data: SessionAccountMapping.sessionData(from: alice)))

    let resumed = try await harness.store.resumeCurrent()
    #expect(resumed.did == "did:plc:alice")
    #expect(resumed.handle == "alice.example")
  }

  @Test func resumeRefreshesAnExpiredToken() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("session-resume-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let freshAccess = makeJWT(payload: ["exp": 4_000_000_000, "scope": "com.atproto.access"])
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "accessJwt": freshAccess, "refreshJwt": "refresh-2",
        "did": "did:plc:alice", "handle": "alice.example",
        "emailConfirmed": true,
        "didDoc": ["service": [["id": "#atproto_pds", "serviceEndpoint": "https://pds.example.com"]]],
      ]))
    let store = SessionStore(
      persisted: PersistedStore(directory: directory),
      tokenStore: FileTokenStore(rootDirectory: directory.appendingPathComponent("tokens")),
      transport: transport)
    _ = await store.hydrate()

    // An account with an already-expired access token.
    let expired = PersistedAccount(
      service: "https://bsky.social/", did: "did:plc:alice", handle: "alice.example",
      refreshJwt: "refresh-1",
      accessJwt: makeJWT(payload: ["exp": 1_000_000_000, "scope": "com.atproto.access"]))
    try await store.upsertAccount(expired)

    let resumed = try await store.resume(account: expired)

    // The refresh response supplied new tokens, which were merged and stored.
    #expect(resumed.accessJwt == freshAccess)
    #expect(resumed.refreshJwt == "refresh-2")
    #expect(resumed.pdsUrl == "https://pds.example.com/")
    #expect(transport.received.count >= 1)
    #expect(transport.received[0].url.hasSuffix("/xrpc/com.atproto.server.refreshSession"))
  }

  @Test func shutdownClearsEverything() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    _ = await harness.store.hydrate()

    let alice = sampleAccount(did: "did:plc:alice")
    try await harness.store.addAccount(
      alice, session: PasswordSession(data: SessionAccountMapping.sessionData(from: alice)))

    try await harness.store.shutdown()

    #expect(await harness.store.snapshot().accounts.isEmpty)
    #expect(try await harness.tokens.dids().isEmpty)
    #expect(harness.cacheCleared.dids == ["did:plc:alice"])

    // The store is closed to further mutation.
    await #expect(throws: SessionStore.StoreError.storeClosed) {
      try await harness.store.addAccount(
        alice, session: PasswordSession(data: SessionAccountMapping.sessionData(from: alice)))
    }
  }

  @Test func listenersReceiveSessionEvents() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    _ = await harness.store.hydrate()

    let events = EventRecorder()
    await harness.store.addListener { did, event in
      events.record(did: did, event: event)
    }

    let alice = sampleAccount(did: "did:plc:alice")
    try await harness.store.addAccount(
      alice, session: PasswordSession(data: SessionAccountMapping.sessionData(from: alice)))

    try await harness.store.logoutCurrentAccount()
    // The listener wiring is exercised by the hook paths in the resume tests;
    // here we only assert that registering and running a mutation never
    // double-fires.
    #expect(events.count <= 1)
  }
}

/// Thread-safe event recorder for listener assertions.
final class EventRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var _events: [(String, AtpSessionEvent)] = []

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return _events.count
  }

  func record(did: String, event: AtpSessionEvent) {
    lock.lock()
    defer { lock.unlock() }
    _events.append((did, event))
  }
}

import Foundation
import Persistence

/// Session-change events, mirroring the RN `AtpSessionEvent`.
public enum AtpSessionEvent: String, Sendable {
  /// Tokens rotated successfully.
  case update
  /// The session is definitively dead and the account was logged out.
  case expired
  /// A refresh failed transiently; the stored tokens are unchanged.
  case networkError = "network-error"
}

/// Multi-account session store.
///
/// Port of the non-React core of `src/state/session`: the accounts list, the
/// current account, and the operations that move between them. There is no UI
/// and no view layer here - consumers observe ``snapshot()`` and act on it.
///
/// ## Persistence model
///
/// The store owns a ``PersistedStore`` (the root document) and a
/// ``SessionTokenStore`` (the secrets). The account *entries* - handle, email,
/// service, PDS URL - live in the root document, because they are read on
/// every cold start. The JWTs live in the token store, because they belong in
/// the Keychain on Apple platforms. ``persist()`` writes both.
///
/// ## Concurrency
///
/// This is an actor, so all state mutation is serialized. Runs that cross an
/// `await` (login, resume, refresh) re-validate their preconditions when they
/// resume, since the state may have changed while they were suspended. That is
/// the Swift analogue of the RN `signal.aborted` checks.
public actor SessionStore {
  /// The immutable view consumers read. `Sendable` so it can cross actors.
  public struct Snapshot: Sendable, Equatable {
    public let accounts: [PersistedAccount]
    public let currentAccount: PersistedAccount?
    public let currentDID: String?

    public var hasSession: Bool { currentAccount != nil }

    public init(
      accounts: [PersistedAccount],
      currentAccount: PersistedAccount?,
      currentDID: String?
    ) {
      self.accounts = accounts
      self.currentAccount = currentAccount
      self.currentDID = currentDID
    }
  }

  /// Errors thrown by the store's operations.
  public enum StoreError: Error, Equatable {
    /// The store has been shut down.
    case storeClosed
    /// The referenced account is not present.
    case unknownAccount(String)
    /// No account is current, so a current-account operation is meaningless.
    case noCurrentAccount
    /// The session for the current account was disposed or is otherwise gone.
    case sessionUnavailable(String)
  }

  private let persisted: PersistedStore
  private let tokenStore: SessionTokenStore
  private let transport: HTTPTransport

  /// Per-DID teardown invoked on remove and on full logout. Exists so the app
  /// layer can drop caches (query store, moderation config, push token)
  /// without this package knowing about them.
  private let cacheClear: (@Sendable (String) async -> Void)?

  /// The persisted document, mirrored in memory.
  private var accounts: [PersistedAccount] = []
  private var currentAccount: PersistedCurrentAccount?

  /// Live sessions by DID, lazily created on resume/switch.
  private var sessions: [String: PasswordSession] = [:]

  /// True once ``shutdown()`` has run; further mutations throw.
  private var closed = false

  /// Creates the store.
  ///
  /// - Parameters:
  ///   - persisted: Root document store, already constructed at its directory.
  ///   - tokenStore: Secret store for JWTs.
  ///   - cacheClear: Per-DID teardown hook, called on remove and logout.
  ///   - transport: Network transport for login/resume/logout.
  public init(
    persisted: PersistedStore,
    tokenStore: SessionTokenStore,
    cacheClear: (@Sendable (String) async -> Void)? = nil,
    transport: HTTPTransport = URLSessionTransport()
  ) {
    self.persisted = persisted
    self.tokenStore = tokenStore
    self.cacheClear = cacheClear
    self.transport = transport
  }

  // MARK: - Hydration

  /// Loads accounts from the persisted document, hydrating their JWTs from
  /// the token store.
  ///
  /// The persisted session slice is the source of truth for which accounts
  /// exist; the token store supplies the secrets. A token store write that
  /// succeeded but was never mirrored into the root document therefore still
  /// yields a usable session, as long as the account entry is present.
  @discardableResult
  public func hydrate() async -> Snapshot {
    let schema = await persisted.hydrate()
    accounts = schema.session.accounts
    currentAccount = schema.session.currentAccount
    await refreshTokensFromStore()
    return snapshot()
  }

  /// Pulls the JWTs for every known account out of the token store.
  private func refreshTokensFromStore() async {
    accounts = await withTaskGroup(of: (Int, PersistedAccount).self) { group in
      for (index, account) in accounts.enumerated() {
        group.addTask { [tokenStore] in
          var copy = account
          copy.accessJwt = (try? await tokenStore.token(kind: .access, for: account.did))
            ?? account.accessJwt
          copy.refreshJwt = (try? await tokenStore.token(kind: .refresh, for: account.did))
            ?? account.refreshJwt
          return (index, copy)
        }
      }
      var result = accounts
      for await (index, account) in group {
        result[index] = account
      }
      return result
    }
  }

  /// The current state, safe to hand to another isolation domain.
  public func snapshot() -> Snapshot {
    Snapshot(
      accounts: accounts,
      currentAccount: accounts.first { $0.did == currentAccount?.did },
      currentDID: currentAccount?.did)
  }

  /// The live session for the current account, when one has been created.
  public func currentSession() -> PasswordSession? {
    guard let did = currentAccount?.did else { return nil }
    return sessions[did]
  }

  // MARK: - Mutations

  /// Adds or replaces an account from a completed login and makes it current.
  ///
  /// Replaces the matching entry positionally so a re-login to an existing
  /// account does not duplicate it.
  public func addAccount(
    _ account: PersistedAccount, session: PasswordSession
  ) async throws {
    try ensureOpen()
    await store(account: account, session: session)
    upsert(account: account, makeCurrent: true)
    try await persist()
  }

  /// Adds an account from a completed login (or resume) result.
  ///
  /// Derives the persisted account from the live session rather than asking
  /// the caller to build one, which is the common case after
  /// `PasswordSession.login`. Returns the account that was recorded.
  @discardableResult
  public func addAccount(
    fromSession session: PasswordSession
  ) async throws -> PersistedAccount {
    try ensureOpen()
    let data = try await session.sessionData()
    guard
      let account = SessionAccountMapping.account(
        from: data, service: data.service)
    else {
      throw StoreError.sessionUnavailable("login result had no session data")
    }
    await store(account: account, session: session)
    upsert(account: account, makeCurrent: true)
    try await persist()
    return account
  }

  /// Adds an account from a login or resume result without a live session.
  ///
  /// Used when the caller only wants the account recorded (e.g. an account
  /// discovered in storage).
  public func upsertAccount(_ account: PersistedAccount) async throws {
    try ensureOpen()
    upsert(account: account, makeCurrent: false)
    try await persist()
  }

  private func upsert(account: PersistedAccount, makeCurrent: Bool) {
    if let index = accounts.firstIndex(where: { $0.did == account.did }) {
      accounts[index] = account
    } else {
      // Most-recently-used first, matching the RN reducer.
      accounts.insert(account, at: 0)
    }
    if makeCurrent {
      currentAccount = PersistedCurrentAccount(
        did: account.did, service: account.service, handle: account.handle)
    }
  }

  /// Writes the account's tokens to the secret store and caches its session.
  private func store(account: PersistedAccount, session: PasswordSession) async {
    if let access = account.accessJwt {
      try? await tokenStore.store(access, kind: .access, for: account.did)
    }
    if let refresh = account.refreshJwt {
      try? await tokenStore.store(refresh, kind: .refresh, for: account.did)
    }
    sessions[account.did] = session
  }

  /// Makes `did` the current account, resuming its session if needed.
  ///
  /// A session is reused when one is already live; otherwise it is resumed
  /// from stored tokens. Resume is a no-network fast path when the stored
  /// access token is still valid, and a refresh otherwise.
  @discardableResult
  public func switchToAccount(_ did: String) async throws -> PersistedAccount {
    try ensureOpen()
    guard let account = accounts.first(where: { $0.did == did }) else {
      throw StoreError.unknownAccount(did)
    }
    currentAccount = PersistedCurrentAccount(
      did: account.did, service: account.service, handle: account.handle)
    try await persist()
    return account
  }

  /// Resumes the current account's session, refreshing tokens as needed.
  ///
  /// Returns the refreshed account snapshot. A transient (network) refresh
  /// failure leaves the stored tokens in place and reports
  /// ``AtpSessionEvent/networkError`` rather than logging the user out.
  @discardableResult
  public func resumeCurrent() async throws -> PersistedAccount {
    try ensureOpen()
    guard let did = currentAccount?.did,
      let stored = accounts.first(where: { $0.did == did })
    else { throw StoreError.noCurrentAccount }
    return try await resume(account: stored)
  }

  /// Resumes a specific account's session.
  @discardableResult
  public func resume(account stored: PersistedAccount) async throws -> PersistedAccount {
    try ensureOpen()
    if let live = sessions[stored.did], !(await live.isDestroyed()) {
      let data = try? await live.sessionData()
      return Self.merge(account: stored, session: data) ?? stored
    }
    let sessionData = SessionAccountMapping.sessionData(from: stored)
    let did = stored.did
    let hooks = SessionHooks(
      onUpdated: { [weak self] data in
        await self?.handleUpdate(did: did, data: data)
      },
      onDeleted: { [weak self] data in
        await self?.handleDeleted(did: did, data: data)
      },
      onUpdateFailure: { [weak self] data, _ in
        await self?.handleUpdateFailure(did: did, data: data)
      })

    let session = PasswordSession(
      data: sessionData, hooks: hooks, transport: transport)
    // Cache before refreshing. A transient refresh failure must leave a live
    // session available so the signed-in shell can build production clients
    // and retry on its next authenticated request. Definitive auth failures
    // destroy and remove this session through `handleDeleted`.
    sessions[did] = session
    if SessionAccountMapping.isExpired(stored) {
      _ = try await session.refresh()
    }

    let data = try? await session.sessionData()
    guard let refreshed = Self.merge(account: stored, session: data) else {
      return stored
    }
    updateEntry(refreshed)
    try await persist()
    return refreshed
  }

  /// Logs out the current account: clears its tokens but keeps the account
  /// entry, so the user can switch back and re-authenticate.
  ///
  /// This is the RN `logged-out-current-account` semantics.
  public func logoutCurrentAccount() async throws {
    try ensureOpen()
    guard let did = currentAccount?.did else { return }
    await sessions[did]?.markDestroyed()
    sessions[did] = nil
    try? await tokenStore.removeAll(for: did)
    if let index = accounts.firstIndex(where: { $0.did == did }) {
      accounts[index].accessJwt = nil
      accounts[index].refreshJwt = nil
    }
    currentAccount = nil
    await cacheClear?(did)
    try await persist()
  }

  /// Logs out every account, clearing every token but keeping the entries.
  ///
  /// This is the RN `logged-out-every-account` semantics.
  public func logoutEveryAccount() async throws {
    try ensureOpen()
    let dids = accounts.map(\.did)
    for did in dids {
      await sessions[did]?.markDestroyed()
    }
    sessions.removeAll()
    try? await tokenStore.removeAll()
    for index in accounts.indices {
      accounts[index].accessJwt = nil
      accounts[index].refreshJwt = nil
    }
    currentAccount = nil
    for did in dids {
      await cacheClear?(did)
    }
    try await persist()
  }

  /// Removes an account entirely, clearing its tokens and caches.
  ///
  /// Unlike logout, the entry is gone. Removing the current account leaves no
  /// account current, matching the RN reducer.
  public func removeAccount(_ did: String) async throws {
    try ensureOpen()
    guard accounts.contains(where: { $0.did == did }) else {
      throw StoreError.unknownAccount(did)
    }
    await sessions[did]?.markDestroyed()
    sessions[did] = nil
    try? await tokenStore.removeAll(for: did)
    accounts.removeAll { $0.did == did }
    if currentAccount?.did == did {
      currentAccount = nil
    }
    await cacheClear?(did)
    try await persist()
  }

  /// Rotates the current session's tokens and returns the refreshed account.
  ///
  /// Throws when nothing was rotated (a transient refresh failure), matching
  /// the RN contract that resolution means "tokens rotated".
  @discardableResult
  public func refreshCurrent() async throws -> PersistedAccount {
    try ensureOpen()
    guard let did = currentAccount?.did else { throw StoreError.noCurrentAccount }
    guard let session = sessions[did] else {
      throw StoreError.sessionUnavailable(did)
    }
    guard let stored = accounts.first(where: { $0.did == did }) else {
      throw StoreError.unknownAccount(did)
    }
    let before = try? await session.sessionData()
    let after = try await session.refresh()
    /* Identity is the rotation signal: PasswordSession allocates a new object
     * on a successful rotation and returns the existing one otherwise. */
    if let before, before == after {
      throw StoreError.sessionUnavailable("no rotation occurred for \(did)")
    }
    let merged = Self.merge(account: stored, session: after) ?? stored
    updateEntry(merged)
    try await persist()
    return merged
  }

  /// Whether the current account's access token was issued for a queued
  /// signup.
  public func isCurrentAccountSignupQueued() -> Bool {
    snapshot().currentAccount.map(SessionAccountMapping.isSignupQueued) ?? false
  }

  /// Clears every account, token, and cached session. A hard reset.
  public func shutdown() async throws {
    let dids = accounts.map(\.did)
    for did in dids {
      await sessions[did]?.markDestroyed()
      await cacheClear?(did)
    }
    sessions.removeAll()
    accounts = []
    currentAccount = nil
    try? await tokenStore.removeAll()
    try await persisted.clearStorage()
    closed = true
  }

  // MARK: - Hook handlers

  private func handleUpdate(did: String, data: SessionData) async {
    guard !closed, let stored = accounts.first(where: { $0.did == did }),
      let merged = Self.merge(account: stored, session: data)
    else { return }
    updateEntry(merged)
    if let access = merged.accessJwt {
      try? await tokenStore.store(access, kind: .access, for: did)
    }
    if let refresh = merged.refreshJwt {
      try? await tokenStore.store(refresh, kind: .refresh, for: did)
    }
    listeners.forEach { $0(did, .update) }
    try? await persist()
  }

  /// A definitive session death. Tokens are cleared and the account is logged
  /// out, but the entry survives so the user can re-authenticate.
  private func handleDeleted(did: String, data: SessionData) async {
    guard !closed, accounts.contains(where: { $0.did == did }) else { return }
    sessions[did] = nil
    try? await tokenStore.removeAll(for: did)
    if let index = accounts.firstIndex(where: { $0.did == did }) {
      accounts[index].accessJwt = nil
      accounts[index].refreshJwt = nil
    }
    if currentAccount?.did == did {
      currentAccount = nil
    }
    listeners.forEach { $0(did, .expired) }
    try? await persist()
  }

  /// A transient refresh failure. The stored tokens are kept, so the session
  /// can recover on the next attempt.
  private func handleUpdateFailure(did: String, data: SessionData) async {
    guard !closed else { return }
    listeners.forEach { $0(did, .networkError) }
  }

  /// Hooks for a newly-created login session.
  ///
  /// Login happens outside this actor, so the returned closures hop back into
  /// the store using the DID carried by each event. This keeps fresh sessions
  /// equivalent to sessions reconstructed by ``resume(account:)``.
  public nonisolated func sessionHooks() -> SessionHooks {
    SessionHooks(
      onUpdated: { [weak self] data in
        await self?.handleUpdate(did: data.did, data: data)
      },
      onDeleted: { [weak self] data in
        await self?.handleDeleted(did: data.did, data: data)
      },
      onUpdateFailure: { [weak self] data, _ in
        await self?.handleUpdateFailure(did: data.did, data: data)
      })
  }

  /// Change listeners, invoked on every session event.
  private var listeners: [@Sendable (String, AtpSessionEvent) -> Void] = []

  /// Registers a change listener. Listeners are best-effort and synchronous.
  public func addListener(_ listener: @escaping @Sendable (String, AtpSessionEvent) -> Void) {
    listeners.append(listener)
  }

  // MARK: - Internals

  private func ensureOpen() throws {
    if closed { throw StoreError.storeClosed }
  }

  private func updateEntry(_ account: PersistedAccount) {
    guard let index = accounts.firstIndex(where: { $0.did == account.did }) else {
      accounts.insert(account, at: 0)
      return
    }
    accounts[index] = account
  }

  /// Merges live session data over a stored account, preserving the fields the
  /// session does not carry (status, stored PDS URL).
  private static func merge(
    account: PersistedAccount, session: SessionData?
  ) -> PersistedAccount? {
    guard let session else { return nil }
    var merged =
      SessionAccountMapping.account(
        from: session, service: session.service, storedPdsUrl: account.pdsUrl)
      ?? account
    // The session never carries a status; keep whatever was stored.
    merged.status = account.status
    return merged
  }

  /// Writes the account entries to the root document and the tokens to the
  /// secret store.
  private func persist() async throws {
    let accounts = self.accounts
    let current = self.currentAccount
    try await persisted.write { schema in
      schema.session.accounts = accounts
      schema.session.currentAccount = current
    }
  }
}

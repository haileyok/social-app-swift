import ATProtoClient
import Foundation
import LoginLogic
import Persistence

/**
 The app's session state: which account is signed in, if any.

 This is the bridge between the pure session layer (`ATProtoClient.SessionStore`,
 an actor with no UI) and the root view. It owns the store's lifetime, the
 device directory its document lives in, and the one question the root view asks:
 *is anybody signed in?*

 ## Why not `Observable`

 The repo's Mac CI builds against the pinned toolchain, and `LoginViewModel`
 already shows the pattern the codebase uses to bridge a callback-based,
 non-MainActor source into SwiftUI: register one listener, republish on the main
 actor. `AppSession` does the same. The `sessionStore` itself stays a plain
 actor, so nothing here depends on the Observation framework.

 ## Bootstrap

 `start()` is the launch path. It builds the stores under the app's Application
 Support directory, hydrates the persisted document, and - when an account is
 recorded as current and has not expired - resumes it so the tokens are known to
 be live. It reports ``state`` exactly once it is settled, which is why the root
 view renders either a loading state or a decided one and never a signed-out
 shell that flips a moment later.

 ## Expiry

 ``loginIsStale`` is the "tokens are dead, ask again" flag. The store raises it
 when a session event reports ``AtpSessionEvent/expired``; a transient
 `networkError` deliberately does *not* set it, because the RN app keeps the user
 signed in through a flaky network rather than ejecting them to a login form.
 */
@MainActor
public final class AppSession {
  /// What the root view needs to know to pick a root.
  public enum State: Equatable {
    /** Bootstrap has not finished; the root view shows a placeholder. */
    case loading
    /** An account is signed in and its session is live. */
    case signedIn(PersistedAccount)
    /** Nobody is signed in, or the session is no longer usable. */
    case signedOut
  }

  /// The XRPC store every session operation runs through.
  public let sessionStore: SessionStore

  /// The transport, retained because the login flow and the store's resume both
  /// need the same one.
  private let transport: HTTPTransport

  /// The current state. Setting it notifies ``listeners``.
  public private(set) var state: State = .loading {
    didSet {
      guard state != oldValue else { return }
      let snapshot = state
      for listener in listeners { listener(snapshot) }
    }
  }

  /// The account currently signed in, when there is one.
  public var currentAccount: PersistedAccount? {
    if case .signedIn(let account) = state { return account }
    return nil
  }

  /// Whether an account is signed in.
  ///
  /// A `Bool` rather than the account itself, so a caller that only needs the
  /// yes/no answer does not have to handle a `PersistedAccount` to ask.
  public var isSignedIn: Bool { currentAccount != nil }

  /// The handle to show in the account menu, preferring the recorded one.
  public var currentHandle: String? {
    guard let account = currentAccount else { return nil }
    return account.handle.isEmpty ? nil : account.handle
  }

  /// Whether the last thing the store knew about the session was that it died.
  public private(set) var loginIsStale = false

  /// The bootstrap flag, so a repeated `start()` is a no-op.
  private var hasStarted = false

  private var listeners: [(State) -> Void] = []

  /**
   Creates a session owner over an already-built store.

   The root view uses ``init(launch:)``, which picks the production stores; this
   initializer exists so the session layer can be driven from a test (or a
   preview) with in-memory stores.
   */
  public init(
    sessionStore: SessionStore,
    transport: HTTPTransport = URLSessionTransport()
  ) {
    self.sessionStore = sessionStore
    self.transport = transport
  }

  /**
   Creates the production session owner.

   Storage lives under Application Support, which is where the RN app's
   `BSKY_STORAGE` document and the session tokens belong on Apple platforms.
   Tokens go to the Keychain when the platform has one and to a sibling file
   store otherwise, which is the same split `Persistence` uses everywhere else.
   */
  public convenience init(launch: ShellLaunch = .current) {
    let directory = Self.storageDirectory(demo: launch.isDemoLaunch)
    let transport = URLSessionTransport()
    self.init(
      sessionStore: SessionStore(
        persisted: PersistedStore(directory: directory),
        tokenStore: Self.makeTokenStore(at: directory),
        transport: transport),
      transport: transport)
  }

  // MARK: - Observation

  /// Registers a state observer and immediately delivers the current value.
  ///
  /// Delivering up front is what makes a late subscriber safe: a view that
  /// mounts after bootstrap sees the decided state rather than waiting for a
  /// transition that already happened.
  public func addListener(_ listener: @escaping (State) -> Void) {
    listeners.append(listener)
    listener(state)
  }

  // MARK: - Bootstrap

  /**
   Hydrates the stores and resumes the current account.

   Safe to call more than once: the second call is a no-op, so a `task` that
   runs twice on a view rebuild cannot start two resumes.
   */
  public func start() async {
    guard !hasStarted else { return }
    hasStarted = true

    // `SessionStore` is an actor, so the subscription has to be awaited: this
    // can only happen from an async context, which is why it lives here rather
    // than in `init`. Registering before the first hydrate means no event is
    // dropped between the read and the subscription.
    await sessionStore.addListener { [weak self] _, event in
      Task { @MainActor in self?.handle(event) }
    }

    let snapshot = await sessionStore.hydrate()
    guard let account = snapshot.currentAccount else {
      state = .signedOut
      return
    }

    // An account entry with no access token cannot resume: the login chooser
    // treats it the same way (`ResumeDecision`). Show the form instead of
    // burning a refresh against tokens we know are absent.
    guard ResumeDecision.forAccount(account) == .resume else {
      state = .signedOut
      return
    }

    do {
      let resumed = try await sessionStore.resume(account: account)
      state = .signedIn(resumed)
    } catch {
      // A failed resume is not a network failure the user can retry from here:
      // the persisted entry stayed in place, so the sign-in form can offer the
      // account again. Drop to signed-out rather than blocking the launch.
      loginIsStale = true
      state = .signedOut
    }
  }

  // MARK: - Sign in / out

  /**
   The login flow this app drives.

   Built with the live session store, so a successful sign-in records the
   account and its tokens without the view having to mirror anything.
   */
  public func makeLoginFlow() -> LoginFlow {
    LoginFlow(transport: transport, sessionStore: sessionStore)
  }

  /**
   Adopts an account the login flow just signed in.

   The flow has already written it to the session store; this refreshes the
   root's state so the shell appears, and clears the stale flag.
   */
  public func adoptSignedInAccount(_ account: PersistedAccount) async {
    loginIsStale = false
    let snapshot = await sessionStore.snapshot()
    state = .signedIn(snapshot.currentAccount ?? account)
  }

  /**
   Signs out the current account and returns to the login root.

   This is `SessionStore.logoutCurrentAccount`: the tokens are cleared but the
   account *entry* survives, so the sign-in form can offer it again and the user
   does not have to retype the handle.
   */
  public func signOut() async {
    try? await sessionStore.logoutCurrentAccount()
    loginIsStale = false
    state = .signedOut
  }

  /**
   Reacts to a session event from the store.

   Only `expired` moves the root: the tokens are definitively gone, so the shell
   cannot keep rendering account-scoped content. `update` is invisible (the
   rotation already landed in the store) and `networkError` keeps the user where
   they are.
   */
  private func handle(_ event: AtpSessionEvent) {
    guard event == .expired else { return }
    loginIsStale = true
    state = .signedOut
  }

  // MARK: - Storage

  /// The directory the app's persisted document and tokens live in.
  ///
  /// Demo launches get a separate directory so a CI screenshot run and a real
  /// session cannot see each other's accounts, and so the UI tests never
  /// inherit whatever a previous run left behind.
  static func storageDirectory(demo: Bool) -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? FileManager.default.temporaryDirectory
    let name = demo ? "SocialAppDemo" : "SocialApp"
    return base.appendingPathComponent(name, isDirectory: true)
  }

  /// The token store for a storage directory: Keychain on Apple platforms, the
  /// file store elsewhere (the same split the Persistence tests rely on).
  static func makeTokenStore(at directory: URL) -> any SessionTokenStore {
    #if canImport(Security)
      return KeychainTokenStore()
    #else
      return FileTokenStore(rootDirectory: directory)
    #endif
  }

  /**
   A session owner over a store rooted at `directory`.

   The production path is ``init(launch:)``; this seam exists so the session can
   be driven over a scratch directory - by a test, a preview, or a future
   "reset local data" affordance - without the caller having to know how the
   Persistence stores are wired together.

   The transport is not a parameter: a `HTTPTransport` default argument would
   make every caller's object file reference the transport type, which the app's
   unit-test target deliberately does not link (it links `AppShell` alone).
   */
  public static func withStorage(directory: URL) -> AppSession {
    let transport = URLSessionTransport()
    return AppSession(
      sessionStore: SessionStore(
        persisted: PersistedStore(directory: directory),
        tokenStore: makeTokenStore(at: directory),
        transport: transport),
      transport: transport)
  }
}

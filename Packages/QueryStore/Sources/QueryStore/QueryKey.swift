import Foundation

/// Marker protocol for the typed `args` payload carried by a ``QueryKey``.
///
/// This mirrors the `T extends Record<string, unknown>` argument object of the
/// RN app's `createQueryKey` helper (`src/state/queries/util.ts`): every value the
/// query depends on belongs here, and changing it produces a different key and
/// therefore a separate cache entry.
public protocol QueryArgs: Hashable, Sendable {}

/// Argument payload for queries that take no arguments.
public struct NoQueryArgs: QueryArgs {
  public init() {}
}

/// Options carried by every ``QueryKey``.
///
/// Ported from the third tuple element of `createQueryKey`:
/// `[root, args, {persistedVersion}]`.
public struct QueryOptions: Hashable, Sendable {
  /// Optional account scope (usually a DID).
  ///
  /// The RN app scopes the whole `QueryClient` to the signed-in account by
  /// re-keying the provider on `currentDid`. A single Swift store serves the same
  /// purpose by carrying the DID on the key, so two accounts hold two distinct
  /// entries for the same root and args.
  public var scope: String?

  /// Version of the persisted payload for this query, if it is persisted.
  ///
  /// Bumping this value is how a breaking change to a persisted payload shape is
  /// busted: a snapshot restored under version `n` no longer matches a key built
  /// at version `n + 1`. Callers that persist should pair this with
  /// `STALE.INFINITY` so a restored entry is not immediately refetched.
  public var persistedVersion: Int?

  public init(scope: String? = nil, persistedVersion: Int? = nil) {
    self.scope = scope
    self.persistedVersion = persistedVersion
  }

  /// No scope and no persisted version.
  public static let none = QueryOptions()
}

/// A structured, hashable query key: a root plus a typed argument object.
///
/// `QueryKey` is the identity of a cache entry. Two keys are equal when their
/// root, scope, persisted version and argument payload are all equal.
///
/// ## Why identity is description-based
///
/// The argument payload is stored as its rendered description rather than as an
/// erased `AnyHashable`. That is what lets a key be rebuilt after a restart: a
/// persisted snapshot records the rendered args (see
/// ``PersistedQuery/args``), and a key reconstructed from it must compare equal
/// to the live, strongly typed key. Erasing to `AnyHashable` would make the
/// restored key a `String`-argued key and the live key a `FeedArgs`-argued one,
/// so the two would never meet.
///
/// The tradeoff is that two distinct argument types rendering to the same text
/// would collide, so ``QueryArgs`` conformers should render distinctly - the
/// compiler-synthesised `String(describing:)` for a struct does.
///
/// ```swift
/// struct FeedArgs: QueryArgs {
///   let feed: String
///   let limit: Int
/// }
///
/// let key = QueryKey("feed", FeedArgs(feed: "discover", limit: 30))
/// key.description  // feed(FeedArgs(feed: "discover", limit: 30))
/// ```
public struct QueryKey: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  /// Stable key root. Ported from `feed-info`, `getFeedSourceInfo`, etc.
  public let root: String

  /// Scope and persisted-version options.
  public let options: QueryOptions

  /// Rendered argument payload. Used for equality, hashing and persistence.
  public let argsText: String

  /// Creates a key from a root and a typed argument payload.
  public init<A: QueryArgs>(_ root: String, _ args: A, options: QueryOptions = .none) {
    self.root = root
    self.argsText = String(describing: args)
    self.options = options
  }

  /// Creates a key whose query takes no arguments.
  public init(_ root: String, options: QueryOptions = .none) {
    self.init(root, NoQueryArgs(), options: options)
  }

  /// Rebuilds a key whose argument payload is only known as text.
  ///
  /// This is how a key is reconstructed from a persisted snapshot. The result
  /// compares equal to a live key built from the same args value.
  public init(root: String, argsText: String, options: QueryOptions = .none) {
    self.root = root
    self.argsText = argsText
    self.options = options
  }

  /// The key root, without args or options.
  public var keyRoot: String { root }

  /// The account scope, if any.
  public var scope: String? { options.scope }

  /// The persisted payload version, if this key is persisted.
  public var persistedVersion: Int? { options.persistedVersion }

  /// Rendered argument payload, the value a persisted snapshot is matched on.
  public var argsDebugDescription: String { argsText }

  /// Returns a copy of the key scoped to `scope`.
  public func scoped(to scope: String?) -> QueryKey {
    var options = self.options
    options.scope = scope
    return QueryKey(root: root, argsText: argsText, options: options)
  }

  /// Returns a copy of the key with no account scope.
  public func unscoped() -> QueryKey { scoped(to: nil) }

  /// Returns a copy of the key with a different persisted payload version.
  public func withPersistedVersion(_ version: Int?) -> QueryKey {
    var options = self.options
    options.persistedVersion = version
    return QueryKey(root: root, argsText: argsText, options: options)
  }

  /// The account scope a snapshot uses, defaulting to the signed-out name.
  public var persistenceScope: String { options.scope ?? QueryStore.loggedOutScope }

  /// Human-readable identity, e.g. `feed(FeedArgs(feed: "discover"))@did:plc:me#v1`.
  public var description: String {
    var text = "\(root)(\(argsText))"
    if let scope = options.scope { text += "@\(scope)" }
    if let version = options.persistedVersion { text += "#v\(version)" }
    return text
  }

  public var debugDescription: String {
    "QueryKey(root: \(root), args: \(argsText), scope: \(options.scope ?? "-"), "
      + "version: \(options.persistedVersion.map(String.init) ?? "-"))"
  }
}

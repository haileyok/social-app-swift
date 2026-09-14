import Foundation
import Synchronization

/// Which session token is being read or written.
public enum SessionTokenKind: String, Sendable, CaseIterable {
  case access
  case refresh
}

/// Errors thrown by the token store implementations.
public enum SessionTokenStoreError: Error, Equatable {
  /// A required on-disk component could not be created or removed.
  case fileSystem(String)

  /// A Keychain operation failed with the given `OSStatus`. Only produced
  /// when the Security framework is available.
  case keychain(Int32)

  /// Stored token bytes were not valid UTF-8.
  case invalidTokenData
}

/// Per-account secret storage for session tokens.
///
/// Tokens are keyed by the account DID, never by handle, because a handle can
/// change while a session is live. Implementations must be safe to call from
/// any isolation domain (the session actor calls them from its own context).
public protocol SessionTokenStore: Sendable {
  /// Stores `token`, replacing any previous value for that account and kind.
  func store(_ token: String, kind: SessionTokenKind, for did: String) async throws

  /// Returns the stored token, or `nil` when none is present.
  func token(kind: SessionTokenKind, for did: String) async throws -> String?

  /// Removes one token. Removing an absent token is not an error.
  func remove(kind: SessionTokenKind, for did: String) async throws

  /// Removes every token for one account.
  func removeAll(for did: String) async throws

  /// Removes every token for every account.
  func removeAll() async throws

  /// The DIDs that currently hold at least one token.
  func dids() async throws -> [String]
}

/// Shared file naming for the store implementations.
enum StorageFileNaming {
  /// Reduces an arbitrary string (a DID contains `:`) to something safe to
  /// use as a single path component.
  static func sanitize(_ value: String) -> String {
    String(value.map { character in
      character.isLetter || character.isNumber || character == "-" ? character : "_"
    })
  }
}

/// File-backed token store: the Linux implementation, and the one tests use.
///
/// One JSON file per account, so a corrupt entry cannot take the rest down.
/// The file records the DID alongside the tokens, which is what makes
/// {@link dids} recoverable without relying on the (lossy) file name.
public struct FileTokenStore: SessionTokenStore {
  /// Directory holding the per-account token files.
  public let rootDirectory: URL

  private let fileManager: FileManager

  public init(rootDirectory: URL, fileManager: FileManager = .default) {
    self.rootDirectory = rootDirectory
    self.fileManager = fileManager
  }

  /// On-disk shape of one account's token file.
  private struct TokenFile: Codable {
    var did: String
    var tokens: [String: String]
  }

  private func url(for did: String) -> URL {
    rootDirectory.appendingPathComponent(
      "tokens-\(StorageFileNaming.sanitize(did)).json")
  }

  private func read(did: String) throws -> TokenFile? {
    let url = url(for: did)
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(TokenFile.self, from: data)
  }

  private func write(_ file: TokenFile, did: String) throws {
    do {
      try fileManager.createDirectory(
        at: rootDirectory, withIntermediateDirectories: true)
      let data = try JSONEncoder().encode(file)
      try data.write(to: url(for: did), options: .atomic)
    } catch {
      throw SessionTokenStoreError.fileSystem("\(error)")
    }
  }

  public func store(
    _ token: String, kind: SessionTokenKind, for did: String
  ) async throws {
    var file = (try? read(did: did)) ?? TokenFile(did: did, tokens: [:])
    file.did = did
    file.tokens[kind.rawValue] = token
    try write(file, did: did)
  }

  public func token(kind: SessionTokenKind, for did: String) async throws -> String? {
    try read(did: did)?.tokens[kind.rawValue]
  }

  public func remove(kind: SessionTokenKind, for did: String) async throws {
    guard var file = try read(did: did) else { return }
    file.tokens[kind.rawValue] = nil
    if file.tokens.isEmpty {
      try removeFile(did: did)
    } else {
      try write(file, did: did)
    }
  }

  public func removeAll(for did: String) async throws {
    try removeFile(did: did)
  }

  public func removeAll() async throws {
    guard let names = try? fileManager.contentsOfDirectory(atPath: rootDirectory.path)
    else { return }
    for name in names where name.hasPrefix("tokens-") && name.hasSuffix(".json") {
      try removeFile(named: name)
    }
  }

  public func dids() async throws -> [String] {
    guard let names = try? fileManager.contentsOfDirectory(atPath: rootDirectory.path)
    else { return [] }
    var result: [String] = []
    for name in names.sorted() where name.hasPrefix("tokens-") && name.hasSuffix(".json") {
      let url = rootDirectory.appendingPathComponent(name)
      guard let data = try? Data(contentsOf: url),
        let file = try? JSONDecoder().decode(TokenFile.self, from: data)
      else { continue }
      result.append(file.did)
    }
    return result
  }

  private func removeFile(did: String) throws {
    try removeFile(url: url(for: did))
  }

  private func removeFile(named name: String) throws {
    try removeFile(url: rootDirectory.appendingPathComponent(name))
  }

  private func removeFile(url: URL) throws {
    guard fileManager.fileExists(atPath: url.path) else { return }
    do {
      try fileManager.removeItem(at: url)
    } catch {
      throw SessionTokenStoreError.fileSystem("\(error)")
    }
  }
}

/// Process-local token store, for tests and previews that want no disk at all.
public final class InMemoryTokenStore: SessionTokenStore {
  private let tokens = Mutex<[String: [SessionTokenKind: String]]>([:])

  public init() {}

  public func store(
    _ token: String, kind: SessionTokenKind, for did: String
  ) async throws {
    tokens.withLock { store in
      store[did, default: [:]][kind] = token
    }
  }

  public func token(kind: SessionTokenKind, for did: String) async throws -> String? {
    tokens.withLock { $0[did]?[kind] }
  }

  public func remove(kind: SessionTokenKind, for did: String) async throws {
    tokens.withLock { store in
      store[did]?[kind] = nil
      if store[did]?.isEmpty == true { store[did] = nil }
    }
  }

  public func removeAll(for did: String) async throws {
    tokens.withLock { $0[did] = nil }
  }

  public func removeAll() async throws {
    tokens.withLock { $0.removeAll() }
  }

  public func dids() async throws -> [String] {
    tokens.withLock { Array($0.keys).sorted() }
  }
}

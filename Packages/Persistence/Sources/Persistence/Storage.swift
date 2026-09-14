import Foundation

/// Errors thrown by ``Storage``.
public enum StorageError: Error, Equatable {
  /// A read or write against the filesystem failed.
  case fileSystem(String)

  /// A stored value could not be decoded as its declared type.
  case decoding(String)
}

/// A versioned, scoped key/value store backed by a JSON file.
///
/// This is the Swift port of the RN `Storage` class in `src/storage/index.ts`.
/// It keeps the same scope shape: a list of scope components in front of a
/// key, joined by `:` into one storage key. The package exports two instances
/// with fixed scope arity:
///
/// - ``device`` - `Storage<DeviceSchema>` with no scope component.
/// - ``account`` - `Storage<AccountSchema>` scoped by account DID.
///
/// Unlike the RN implementation (MMKV, synchronous), this is JSON-file backed
/// through `FileManager`, so every operation is `async` and the file is
/// rewritten atomically on each mutation. Atomic writes matter here: a partial
/// write would otherwise corrupt the whole store, which is exactly the failure
/// tolerant decoding is designed to survive.
public actor Storage<Schema> {
  /// Identifier used in the file name (e.g. `bsky_device`).
  public nonisolated let id: String

  /// Scope components that prefix every key written through this instance.
  public nonisolated let scope: [String]

  /// The current on-disk schema version. Bumping this makes ``migrate`` run.
  public nonisolated let schemaVersion: Int

  private let fileManagerBox: SendableFileManager

  private var fileManager: FileManager { fileManagerBox.value }
  private let directory: URL

  /// Runs when the stored `_version` differs from ``schemaVersion``.
  private let migration: (@Sendable (Int, [String: JSONValue]) -> [String: JSONValue])?

  /// The joined storage key separator, matching the RN implementation.
  private static var separator: String { ":" }

  /// Creates a store rooted at `directory`.
  ///
  /// - Parameters:
  ///   - id: Identifier used in the file name.
  ///   - scope: Fixed scope components for this instance (empty for device).
  ///   - schemaVersion: Current version; a mismatch triggers `migration`.
  ///   - directory: Directory holding the JSON file.
  ///   - migration: Called with the stored version and the stored members,
  ///     and returns the migrated members. Only invoked when versions differ.
  public init(
    id: String,
    scope: [String] = [],
    schemaVersion: Int = 1,
    directory: URL,
    fileManager: SendableFileManager = SendableFileManager(),
    migration: (@Sendable (Int, [String: JSONValue]) -> [String: JSONValue])? = nil
  ) {
    self.id = id
    self.scope = scope
    self.schemaVersion = schemaVersion
    self.directory = directory
    self.fileManagerBox = fileManager
    self.migration = migration
  }

  private var fileURL: URL {
    directory.appendingPathComponent("\(id).json")
  }

  private func storageKey(_ key: String, scopedBy scopeComponents: [String]) -> String {
    (scope + scopeComponents + [key]).joined(separator: Self.separator)
  }

  /// Reads and migrates the raw document.
  ///
  /// A missing file is an empty store (not an error). A file that is not
  /// valid JSON is also treated as empty: the alternative is refusing to boot,
  /// and the data is unrecoverable regardless.
  private func loadRaw() -> [String: JSONValue] {
    guard fileManager.fileExists(atPath: fileURL.path),
      let data = try? Data(contentsOf: fileURL),
      let raw = try? JSONDecoder().decode(JSONValue.self, from: data),
      let members = raw.objectValue
    else { return [:] }

    let storedVersion = Int(members["_version"]?.numberValue ?? 0)
    guard let migration, storedVersion != schemaVersion else { return members }
    var migrated = migration(storedVersion, members)
    migrated["_version"] = .number(Double(schemaVersion))
    try? writeRaw(migrated)
    return migrated
  }

  private func writeRaw(_ members: [String: JSONValue]) throws {
    do {
      try fileManager.createDirectory(
        at: directory, withIntermediateDirectories: true)
      var payload = members
      payload["_version"] = .number(Double(schemaVersion))
      let data = try JSONEncoder().encode(JSONValue.object(payload))
      try data.write(to: fileURL, options: .atomic)
    } catch {
      throw StorageError.fileSystem("\(error)")
    }
  }

  /// Stores `value` under the key, optionally inside extra scopes.
  public func set<Value: Encodable>(
    _ scopes: [String], _ key: String, value: Value
  ) throws {
    var members = loadRaw()
    guard let encoded = try? JSONEncoder().encode(value),
      let json = try? JSONDecoder().decode(JSONValue.self, from: encoded)
    else {
      throw StorageError.decoding("could not encode value for key '\(key)'")
    }
    members[storageKey(key, scopedBy: scopes)] = json
    try writeRaw(members)
  }

  /// Stores `value` in this instance's own scope.
  public func set<Value: Encodable>(_ key: String, value: Value) throws {
    try set([], key, value: value)
  }

  /// Reads the value under the key, or `nil` when absent.
  ///
  /// A present-but-undecodable value reports `nil` rather than throwing. The
  /// per-key equivalent of the root-level tolerant policy: a bad preference
  /// read falls back to the caller's default instead of failing the call.
  public func get<Value: Decodable>(
    _ scopes: [String], _ key: String, as type: Value.Type
  ) -> Value? {
    let members = loadRaw()
    guard let raw = members[storageKey(key, scopedBy: scopes)] else { return nil }
    return raw.decoded(as: Value.self)
  }

  /// Reads the value in this instance's own scope.
  public func get<Value: Decodable>(_ key: String, as type: Value.Type) -> Value? {
    get([], key, as: type)
  }

  /// Removes one key. Removing an absent key is not an error.
  public func remove(_ scopes: [String], _ key: String) throws {
    var members = loadRaw()
    members[storageKey(key, scopedBy: scopes)] = nil
    try writeRaw(members)
  }

  /// Removes one key from this instance's own scope.
  public func remove(_ key: String) throws {
    try remove([], key)
  }

  /// Removes many keys sharing a scope prefix.
  public func removeMany(_ scopes: [String], keys: [String]) throws {
    var members = loadRaw()
    for key in keys {
      members[storageKey(key, scopedBy: scopes)] = nil
    }
    try writeRaw(members)
  }

  /// Removes every key written through this instance, leaving the version
  /// marker in place so the empty store reads as current.
  public func removeAll() throws {
    try writeRaw([:])
  }

  /// Every key currently present, in storage form.
  public func keys() -> [String] {
    loadRaw().keys.filter { $0 != "_version" }.sorted()
  }
}

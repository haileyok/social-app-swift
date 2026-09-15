import Foundation

/// The root persisted document store: hydration, migration, and writes.
///
/// This is the Swift port of `src/state/persisted/index.ts` (the native
/// variant). The RN version keeps an in-memory `_state`, hydrates it once on
/// `init`, and rewrites the whole document on every `write`. This port keeps
/// the same shape but decodes tolerantly, so hydration cannot log the user out
/// because one field drifted (see ``TolerantDecoding``).
public actor PersistedStore {
  /// File name used for the root document.
  public static let storageKey = "BSKY_STORAGE"

  private let fileURL: URL
  private let directory: URL
  private let fileManagerBox: SendableFileManager

  private var fileManager: FileManager { fileManagerBox.value }
  private let migration: (@Sendable (Int, [String: JSONValue]) -> [String: JSONValue])?

  /// The current in-memory document. Starts at defaults until ``hydrate()``.
  private var state: PersistedSchema

  /// Field-level fallbacks applied during the last ``hydrate()``.
  public private(set) var lastDecodeIssues: [DecodeIssue] = []

  /// The schema version this build writes.
  public let schemaVersion: Int

  /// Creates the store.
  ///
  /// - Parameters:
  ///   - directory: Directory holding `BSKY_STORAGE.json`.
  ///   - schemaVersion: Current schema version, recorded in the document.
  ///   - migration: Given the stored version and members, returns migrated
  ///     members. Runs only when the stored version differs.
  public init(
    directory: URL,
    schemaVersion: Int = PersistedMigrator.currentVersion,
    fileManager: SendableFileManager = SendableFileManager(),
    migration: (@Sendable (Int, [String: JSONValue]) -> [String: JSONValue])? = nil,
    defaultLanguagePrefs: LanguagePrefs = LanguagePrefs()
  ) {
    self.directory = directory
    self.fileURL = directory.appendingPathComponent("\(Self.storageKey).json")
    self.schemaVersion = schemaVersion
    self.fileManagerBox = fileManager
    self.migration = migration
    self.state = PersistedSchema.defaults(languagePrefs: defaultLanguagePrefs)
  }

  /// Reads the document from disk into memory, applying migrations and
  /// tolerant decoding.
  ///
  /// A missing or unparseable file leaves the defaults in place. This mirrors
  /// the RN `init()`, minus the all-or-nothing validation.
  @discardableResult
  public func hydrate() -> PersistedSchema {
    guard fileManager.fileExists(atPath: fileURL.path),
      let data = try? Data(contentsOf: fileURL),
      let raw = try? JSONDecoder().decode(JSONValue.self, from: data),
      var members = raw.objectValue
    else {
      state = PersistedSchema.defaults()
      lastDecodeIssues = []
      return state
    }

    let storedVersion = Int(members["_version"]?.numberValue ?? 0)
    if let migration, storedVersion != schemaVersion {
      members = migration(storedVersion, members)
    }

    let decoded = PersistedSchema.decodeTolerantly(from: .object(members))
    state = normalized(decoded.schema)
    lastDecodeIssues = decoded.issues
    return state
  }

  /// The current in-memory document (RN `get`).
  public func current() -> PersistedSchema {
    state
  }

  /// Writes one slice of the document and persists the whole thing.
  ///
  /// The closure is handed the current state and returns the new one, which
  /// keeps read-modify-write atomic within the actor.
  @discardableResult
  public func write(
    _ mutate: @Sendable (inout PersistedSchema) -> Void
  ) throws -> PersistedSchema {
    var next = state
    mutate(&next)
    state = normalized(next)
    try persist()
    return state
  }

  /// Replaces the whole document.
  @discardableResult
  public func replace(with next: PersistedSchema) throws -> PersistedSchema {
    state = normalized(next)
    try persist()
    return state
  }

  /// Deletes the backing file and resets to defaults (RN `clearStorage`).
  public func clearStorage() throws {
    if fileManager.fileExists(atPath: fileURL.path) {
      do {
        try fileManager.removeItem(at: fileURL)
      } catch {
        throw StorageError.fileSystem("\(error)")
      }
    }
    state = PersistedSchema.defaults()
    lastDecodeIssues = []
  }

  private func persist() throws {
    do {
      try fileManager.createDirectory(
        at: directory, withIntermediateDirectories: true)
      var members = try encodeMembers(state)
      members["_version"] = .number(Double(schemaVersion))
      let data = try JSONEncoder().encode(JSONValue.object(members))
      try data.write(to: fileURL, options: .atomic)
    } catch let error as StorageError {
      throw error
    } catch {
      throw StorageError.fileSystem("\(error)")
    }
  }

  private func encodeMembers(_ schema: PersistedSchema) throws -> [String: JSONValue] {
    guard let data = try? JSONEncoder().encode(schema),
      let value = try? JSONDecoder().decode(JSONValue.self, from: data),
      let members = value.objectValue
    else {
      throw StorageError.decoding("could not encode root document")
    }
    return members
  }

  /// Applies the normalizations RN performs on every read and write
  /// (`normalizeData` in `src/state/persisted/util.ts`): the non-region
  /// language codes and deduped list fields.
  private func normalized(_ input: PersistedSchema) -> PersistedSchema {
    var next = input
    var prefs = next.languagePrefs
    prefs.primaryLanguage = LanguageNormalization.twoLetterCode(prefs.primaryLanguage)
    prefs.contentLanguages = Self.dedup(
      prefs.contentLanguages.map(LanguageNormalization.twoLetterCode))
    prefs.postLanguage = LanguageNormalization.normalizePostLanguage(prefs.postLanguage)
    prefs.postLanguageHistory = Self.dedup(
      prefs.postLanguageHistory.map(LanguageNormalization.normalizePostLanguage))
    next.languagePrefs = prefs
    return next
  }

  /// Order-preserving de-duplication, matching RN `dedupArray`.
  static func dedup(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values where seen.insert(value).inserted {
      result.append(value)
    }
    return result
  }
}

/// Language-tag normalization used by ``PersistedStore/normalized(_:)``.
///
/// The RN implementation uses the `bcp-47` package. Foundation has no
/// equivalent parser, so this reduces a tag to its primary subtag: split on
/// `-`/`_`, lowercase, keep the first component when it looks like a language
/// code. That covers every case the app actually stores (they are written as
/// 2-letter codes already); a tag this cannot reduce is returned unchanged,
/// matching the RN fallback.
public enum LanguageNormalization {
  /// Reduces a BCP-47 tag to its 2-letter language code when possible.
  public static func twoLetterCode(_ tag: String) -> String {
    let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return tag }
    let primary = trimmed.split(whereSeparator: { $0 == "-" || $0 == "_" })
      .first.map(String.init)?.lowercased() ?? ""
    guard !primary.isEmpty else { return tag }
    return primary
  }

  /// Normalizes each comma-separated component of a posting-language value.
  public static func normalizePostLanguage(_ value: String) -> String {
    value
      .split(separator: ",")
      .map { twoLetterCode(String($0)) }
      .filter { !$0.isEmpty }
      .joined(separator: ",")
  }
}

import Foundation

/// Schema migrations for the root persisted document.
///
/// The RN app has no explicit version marker on the root document; it relies
/// on zod's per-field `.optional()`s to absorb shape changes, plus
/// `normalizeData` for value normalization. The Swift port adds an explicit
/// `_version` integer so migrations run deterministically instead of being
/// inferred from which fields happen to be absent.
///
/// Each step is expressed as a function from the stored members to the
/// migrated members. Steps are pure so they are trivially testable, and the
/// migrator applies every step from the stored version up to the current one.
public enum PersistedMigrator {
  /// The version written by this build.
  public static let currentVersion = 1

  /// A single migration step: `from` -> `from + 1`.
  public typealias Step = @Sendable ([String: JSONValue]) -> [String: JSONValue]

  /// Ordered steps, where `steps[i]` migrates version `i` to `i + 1`.
  ///
  /// Version 1 is the first versioned schema, so this is empty. Future shape
  /// changes append a step here and bump ``currentVersion``.
  public static let steps: [Step] = []

  /// Applies every step from `fromVersion` up to ``currentVersion``.
  ///
  /// A stored version newer than the build (a downgrade) is left untouched
  /// rather than guessed at; tolerant decoding handles any field it does not
  /// recognize. A negative or zero version is treated as version 1, since
  /// that is what an unversioned document means.
  public static func migrate(
    fromVersion: Int, members: [String: JSONValue]
  ) -> [String: JSONValue] {
    guard fromVersion < currentVersion else { return members }
    let start = max(fromVersion, 0)
    guard start < currentVersion else { return members }
    var result = members
    for index in start..<currentVersion where index < steps.count {
      result = steps[index](result)
    }
    return result
  }

  /// A migration closure suitable for ``PersistedStore`` / ``Storage``.
  public static let closure:
    @Sendable (Int, [String: JSONValue]) -> [String: JSONValue] = { version, members in
      migrate(fromVersion: version, members: members)
    }
}

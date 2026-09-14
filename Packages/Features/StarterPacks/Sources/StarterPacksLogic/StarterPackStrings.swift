import Foundation

/// String sanitizers the default starter-pack name depends on.
///
/// Ports `src/lib/strings/display-names.ts` (`sanitizeDisplayName`),
/// `src/lib/strings/handles.ts` (`sanitizeHandle`) and `src/lib/strings/helpers.ts`
/// (`enforceLen`). These are the inputs to
/// `createSanitizedDisplayName(profile, true)` and therefore to the
/// "`<name>`'s Starter Pack" default.
///
/// `forceLTR` is not ported: RN's `forceLTR` only wraps a string in bidi
/// embedding marks on native, and a Logic package has no platform to branch on.
/// The lowercased handle is returned verbatim.
public enum StarterPackStrings {
  /// ✅ ✓ ✔ ☑, stripped from display names.
  private static let checkMarks: Set<Character> = ["\u{2705}", "\u{2713}", "\u{2714}", "\u{2611}"]

  /// Control characters and bidi overrides, stripped from display names.
  private static let controlCharacters: Set<Unicode.Scalar> = {
    var set = Set<Unicode.Scalar>()
    for value in 0x00...0x1F { set.insert(Unicode.Scalar(value)!) }
    for value in 0x7F...0x9F { set.insert(Unicode.Scalar(value)!) }
    for value in [0x061C, 0x200E, 0x200F] { set.insert(Unicode.Scalar(value)!) }
    for value in 0x202A...0x202E { set.insert(Unicode.Scalar(value)!) }
    for value in 0x2066...0x2069 { set.insert(Unicode.Scalar(value)!) }
    return set
  }()

  /// A display name with check marks and control characters removed, runs of
  /// whitespace collapsed, and the result trimmed.
  ///
  /// Port of `sanitizeDisplayName`. The moderation blur branch is not ported:
  /// the Logic package has no moderation decision to consult here, and passing
  /// one through only ever made the name empty.
  public static func sanitizeDisplayName(_ str: String) -> String {
    let withoutControl = String(
      String.UnicodeScalarView(
        str.unicodeScalars.filter { !controlCharacters.contains($0) }))
    let withoutMarks = String(withoutControl.filter { !checkMarks.contains($0) })
    return collapseWhitespace(withoutMarks).trimmingCharacters(in: .whitespaces)
  }

  /// A handle lowercased and prefixed, or the invalid-handle placeholder.
  ///
  /// Port of `sanitizeHandle`. `handle.invalid` is the sentinel the appview
  /// returns for a handle it could not resolve; RN renders a warning in its
  /// place, and this port keeps the same sentinel so callers can recognize it.
  public static func sanitizeHandle(_ handle: String, prefix: String = "") -> String {
    let lowered = prefix + handle.lowercased()
    return handle == "handle.invalid" ? invalidHandlePlaceholder : lowered
  }

  /// What `sanitizeHandle` returns in place of `handle.invalid`.
  public static let invalidHandlePlaceholder = "\u{26A0}Invalid Handle"

  /// Truncates a string to `len` characters, optionally marking the cut with an
  /// ellipsis.
  ///
  /// Port of `enforceLen` with `mode: 'end'` (the mode every starter-pack caller
  /// uses). JS `.length` counts UTF-16 code units; the difference only shows on
  /// astral characters, and only ever truncates one character earlier there.
  public static func enforceLen(_ str: String, _ len: Int, ellipsis: Bool = false) -> String {
    if str.count <= len { return str }
    let head = String(str.prefix(len))
    return ellipsis ? head + "\u{2026}" : head
  }

  /// The default pack name for a profile: its display name, or `@handle` when
  /// there is none.
  ///
  /// Port of `createSanitizedDisplayName(profile, true)` followed by the
  /// wizard's `"\(displayName)'s Starter Pack"` template and a 50-character
  /// slice. RN uses a right single quotation mark (`’`).
  public static func defaultPackName(displayName: String?, handle: String) -> String {
    let base: String
    if let displayName, !displayName.isEmpty {
      base = sanitizeDisplayName(displayName)
    } else {
      base = sanitizeHandle(handle)
    }
    return enforceLen("\(base)\u{2019}s Starter Pack", StarterPackConstants.maxNameLength)
  }

  /// Collapses runs of whitespace (including a following zero-width space) to a
  /// single space.
  ///
  /// Port of the `MULTIPLE_SPACES_RE` replace: `[\s][\s\u200B]+` becomes `" "`.
  private static func collapseWhitespace(_ str: String) -> String {
    var out = String()
    out.reserveCapacity(str.count)
    var pending: Character?
    for character in str {
      if character == "\u{200B}" { continue }
      if character.isWhitespace {
        pending = " "
        continue
      }
      if let space = pending {
        out.append(space)
        pending = nil
      }
      out.append(character)
    }
    if let space = pending { out.append(space) }
    return out
  }
}

import Foundation
import Lexicons

/// The self-labels the composer offers as content warnings.
///
/// Ported from `src/lib/moderation.ts` (`ADULT_CONTENT_LABELS`,
/// `OTHER_SELF_LABELS`, `SELF_LABELS`).
public enum SelfLabels {
  /// `ADULT_CONTENT_LABELS` - the adult-content warnings.
  public static let adultContent: [String] = ["sexual", "nudity", "porn"]

  /// `OTHER_SELF_LABELS` - the remaining self-label warnings.
  public static let other: [String] = ["graphic-media"]

  /// `SELF_LABELS` - every label the composer can attach, in RN order.
  public static let all: [String] = adultContent + other

  /// Whether `label` is one the composer offers.
  public static func isComposerLabel(_ label: String) -> Bool {
    all.contains(label)
  }
}

/// The labels attached to one post.
///
/// A thin wrapper over the array so the record builder and the composer UI both
/// speak the same type, and so the wire shape (`com.atproto.label.defs#selfLabels`)
/// is built in exactly one place.
public struct SelfLabelSet: Hashable, Sendable {
  /// The label values, in the order the user selected them.
  public var values: [String]

  public init(values: [String] = []) {
    self.values = values
  }

  /// Whether any label is attached.
  public var isEmpty: Bool { values.isEmpty }

  /// Adds `label` if it is not already present.
  public mutating func insert(_ label: String) {
    guard !values.contains(label) else { return }
    values.append(label)
  }

  /// Removes `label` if present.
  public mutating func remove(_ label: String) {
    values.removeAll { $0 == label }
  }

  /// Whether `label` is attached.
  public func contains(_ label: String) -> Bool { values.contains(label) }

  /// The record shape, or `nil` when no labels are attached.
  ///
  /// Ported from `lib/api/index.ts`: the record only carries `labels` when the
  /// composer has at least one, and always with the selfLabels `$type`.
  public var recordValue: Com.Atproto.LabelDefs_SelfLabels? {
    guard !values.isEmpty else { return nil }
    return Com.Atproto.LabelDefs_SelfLabels(
      values: values.map { Com.Atproto.LabelDefs_SelfLabel(val: $0) })
  }
}

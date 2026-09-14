/// A per-context projection of a decision: what to filter, blur, alert, and
/// inform for a given surface.
public struct ModerationUI: Sendable {
  /// Whether the blur must not be dismissible by the viewer.
  public var noOverride = false
  public var filters: [ModerationCause] = []
  public var blurs: [ModerationCause] = []
  public var alerts: [ModerationCause] = []
  public var informs: [ModerationCause] = []

  public init() {}

  /// Whether this surface should be filtered out entirely.
  public var filter: Bool { !filters.isEmpty }
  /// Whether this surface should be blurred.
  public var blur: Bool { !blurs.isEmpty }
  /// Whether this surface should show an alert.
  public var alert: Bool { !alerts.isEmpty }
  /// Whether this surface should show an informational notice.
  public var inform: Bool { !informs.isEmpty }
}

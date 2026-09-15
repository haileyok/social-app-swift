import UIComponentsCore

/// Convenience reads over ``ModerationSurface``.
///
/// `ModerationSurface` deliberately exposes only `isVisible` because the mask
/// decides how to draw; the header needs to know a little more (which cause, and
/// whether the viewer may override it) to place its own reveal affordance, so
/// those reads live here rather than being re-derived at each call site.
extension ModerationSurface {
  /// The cause when this surface is blurred, `nil` otherwise.
  public var blurCause: ModerationCauseDescription? {
    if case .blur(let cause, _) = self { return cause }
    return nil
  }

  /// The cause when this surface is filtered, `nil` otherwise.
  public var filterCause: ModerationCauseDescription? {
    if case .filter(let cause) = self { return cause }
    return nil
  }

  /// Whether a blurred surface may be revealed by the viewer.
  public var allowsOverride: Bool {
    if case .blur(_, let allowOverride) = self { return allowOverride }
    return false
  }

  /// A cause to report for this surface, whichever shape it took.
  public var cause: ModerationCauseDescription? {
    blurCause ?? filterCause
  }
}

#if canImport(SwiftUI)
import DesignSystemCore
import SwiftUI

/**
 The RN breakpoints, resolved from SwiftUI's horizontal size class and the
 container width.

 The pure thresholds and predicates live in `DesignSystemCore.Breakpoints`; this
 bridges them to the values SwiftUI actually exposes. The mapping is documented
 on `Breakpoints` and in the README: the RN 500/800/1300 media queries become
 size-class checks gated on the container width.

 ```swift
 GeometryReader { proxy in
   let bp = ScreenBreakpoints(sizeClass: hSizeClass, width: proxy.size.width)
   if bp.isAtLeast(.tablet) { ... }
 }
 ```
 */
public struct ScreenBreakpoints: Equatable, Sendable {
  /** The container width in points. */
  public let width: Double
  /** Whether the horizontal size class is `.regular`. */
  public let isRegularWidth: Bool

  public init(width: Double, isRegularWidth: Bool) {
    self.width = width
    self.isRegularWidth = isRegularWidth
  }

  /** `useBreakpoints().gtPhone` */
  public var gtPhone: Bool {
    Breakpoints.isAtLeast(.phone, width: width, isRegularWidth: isRegularWidth)
  }

  /** `useBreakpoints().gtMobile` */
  public var gtMobile: Bool {
    Breakpoints.isAtLeast(.mobile, width: width, isRegularWidth: isRegularWidth)
  }

  /** `useBreakpoints().gtTablet` */
  public var gtTablet: Bool {
    Breakpoints.isAtLeast(.tablet, width: width, isRegularWidth: isRegularWidth)
  }

  /** `useBreakpoints().activeBreakpoint` */
  public var active: Breakpoints.Active? {
    Breakpoints.active(width: width, isRegularWidth: isRegularWidth)
  }

  /** `useLayoutBreakpoints().rightNavVisible` */
  public var rightNavVisible: Bool { Breakpoints.isRightNavVisible(width: width) }

  /** `useLayoutBreakpoints().centerColumnOffset` */
  public var centerColumnOffset: Bool { Breakpoints.isCenterColumnOffset(width: width) }

  /** `useLayoutBreakpoints().leftNavMinimal` */
  public var leftNavMinimal: Bool { Breakpoints.isLeftNavMinimal(width: width) }

  /** Whether a named breakpoint is cleared. */
  public func isAtLeast(_ breakpoint: Breakpoints.Active) -> Bool {
    Breakpoints.isAtLeast(breakpoint, width: width, isRegularWidth: isRegularWidth)
  }
}

extension EnvironmentValues {
  /**
   The current screen breakpoints, from the environment's horizontal size class.
   `width` defaults to 0 so a view that never reports a width reads as compact;
   set it with `.screenWidth(proxy.size.width)` inside a `GeometryReader`.
   */
}

private struct ScreenWidthKey: EnvironmentKey {
  static let defaultValue: Double = 0
}

extension EnvironmentValues {
  /** The container width used with the horizontal size class for breakpoints. */
  public var screenWidth: Double {
    get { self[ScreenWidthKey.self] }
    set { self[ScreenWidthKey.self] = newValue }
  }
}

extension View {
  /** Records the container width so `breakpoints` can resolve. */
  public func screenWidth(_ width: Double) -> some View {
    environment(\.screenWidth, width)
  }
}

/**
 Provides the resolved breakpoints to descendants. Attach from a `GeometryReader`
 (or any view that knows its width):

 ```swift
 GeometryReader { proxy in
   Content().breakpoints(width: proxy.size.width)
 }
 ```

 Descendants read `@Environment(\.breakpoints)`.
 */
private struct BreakpointsKey: EnvironmentKey {
  static let defaultValue = ScreenBreakpoints(width: 0, isRegularWidth: false)
}

extension EnvironmentValues {
  /** The resolved breakpoints for the current container. */
  public var breakpoints: ScreenBreakpoints {
    get { self[BreakpointsKey.self] }
    set { self[BreakpointsKey.self] = newValue }
  }
}

extension View {
  /** Resolves breakpoints from an explicit width and the ambient size class. */
  public func breakpoints(width: Double) -> some View {
    modifier(BreakpointsModifier(width: width))
  }
}

struct BreakpointsModifier: ViewModifier {
  let width: Double

  @Environment(\.horizontalSizeClass) private var sizeClass

  func body(content: Content) -> some View {
    content
      .environment(\.screenWidth, width)
      .environment(
        \.breakpoints,
        ScreenBreakpoints(width: width, isRegularWidth: sizeClass == .regular))
  }
}
#endif

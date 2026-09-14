import DesignTokens

/**
 The RN app's responsive breakpoints, restated as width thresholds, plus the
 size-class mapping that replaces them on iOS.

 The RN app uses three `useMediaQuery` breakpoints at 500, 800 and 1300 points
 (`src/alf/breakpoints.ts`), and a finer set for the shell (`useLayoutBreakpoints`:
 1100 and 1300). SwiftUI has no media queries: the equivalent signal is the
 horizontal size class, corrected for the widths the RN breakpoints actually
 draw a line at. The threshold table below is the pure mapping; the SwiftUI layer
 reads the real size class and viewport width and asks this type what is active.

 Mapping (documented migration, see README):

 | RN query            | iOS reality                                             |
 | ------------------- | ------------------------------------------------------- |
 | `minWidth: 500`     | `.regular` width class on every current iPhone in landscape, or any iPad |
 | `minWidth: 800`     | `.regular` width class and a viewport at least 800pt wide (iPad, iPhone Pro Max landscape) |
 | `minWidth: 1300`    | 1300pt wide viewport (iPad Pro 12.9" landscape, Mac)     |
 */
public enum Breakpoints {
  /// `useBreakpoints`: `gtPhone`, `minWidth: 500`.
  public static let phone = 500.0
  /// `useBreakpoints`: `gtMobile`, `minWidth: 800`.
  public static let mobile = 800.0
  /// `useBreakpoints`: `gtTablet`, `minWidth: 1300`.
  public static let tablet = 1300.0

  /// `useLayoutBreakpoints`: `rightNavVisible` / `centerColumnOffset` minWidth.
  public static let rightNavMinWidth = 1100.0
  /// `useLayoutBreakpoints`: `centerColumnOffset` maxWidth.
  public static let centerColumnMaxWidth = 1300.0

  /** The largest threshold the width clears, mirroring `activeBreakpoint`. */
  public static func active(width: Double, isRegularWidth: Bool) -> Active? {
    if width >= tablet {
      return .tablet
    }
    if width >= mobile && isRegularWidth {
      return .mobile
    }
    if width >= phone && isRegularWidth {
      return .phone
    }
    return nil
  }

  /**
   Whether the viewport is at or above a threshold. `atLeast(.phone)` is the RN
   `gtPhone` predicate, with the width class additionally required for the two
   wider steps because a compact-width iPhone at 500pt+ (e.g. landscape on a
   non-Pro device) is still a phone layout.
   */
  public static func isAtLeast(
    _ breakpoint: Active, width: Double, isRegularWidth: Bool
  ) -> Bool {
    switch breakpoint {
    case .phone: width >= phone && isRegularWidth
    case .mobile: width >= mobile && isRegularWidth
    case .tablet: width >= tablet
    }
  }

  /** The three RN breakpoint names. */
  public enum Active: String, Equatable, Sendable, CaseIterable {
    case phone = "gtPhone"
    case mobile = "gtMobile"
    case tablet = "gtTablet"
  }

  /** `useLayoutBreakpoints().rightNavVisible` - `minWidth: 1100`. */
  public static func isRightNavVisible(width: Double) -> Bool {
    width >= rightNavMinWidth
  }

  /** `useLayoutBreakpoints().leftNavMinimal` - `maxWidth: 1300`. */
  public static func isLeftNavMinimal(width: Double) -> Bool {
    width <= centerColumnMaxWidth
  }

  /**
   `useLayoutBreakpoints().centerColumnOffset` - `minWidth: 1100` and
   `maxWidth: 1300` (`react-responsive` treats `maxWidth` as inclusive).
   */
  public static func isCenterColumnOffset(width: Double) -> Bool {
    width >= rightNavMinWidth && width <= centerColumnMaxWidth
  }
}

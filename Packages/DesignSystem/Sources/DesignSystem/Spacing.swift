#if canImport(SwiftUI)
import DesignTokens
import SwiftUI

/**
 ALF's spacing and radius scales as SwiftUI-friendly constants and modifiers.

 ```swift
 VStack { ... }.padding(.md)              // 12pt, the ALF `md` step
 Color.red.cornerRadius(.lg)              // 16pt
 ```
 */
public enum Spacing {
  public static let xxs = Scales.Spacing.xxs
  public static let xs = Scales.Spacing.xs
  public static let sm = Scales.Spacing.sm
  public static let md = Scales.Spacing.md
  public static let lg = Scales.Spacing.lg
  public static let xl = Scales.Spacing.xl
  public static let xxl = Scales.Spacing.xxl
  public static let xxxl = Scales.Spacing.xxxl
  public static let xxxxl = Scales.Spacing.xxxxl
  public static let xxxxxl = Scales.Spacing.xxxxxl

  /**
   A spacing step, so `.padding(.md)` reads the way ALF's `a.p_md` does. The
   cases mirror the t-shirt scale (including ALF's `3xl`..`5xl`, which the RN
   app documents as `2xl`..`4xl`).
   */
  public enum Step: Equatable, Sendable, CaseIterable {
    case xxs
    case xs
    case sm
    case md
    case lg
    case xl
    case xxl
    case xxxl
    case xxxxl
    case xxxxxl

    /** The value in points. */
    public var value: Double {
      switch self {
      case .xxs: Spacing.xxs
      case .xs: Spacing.xs
      case .sm: Spacing.sm
      case .md: Spacing.md
      case .lg: Spacing.lg
      case .xl: Spacing.xl
      case .xxl: Spacing.xxl
      case .xxxl: Spacing.xxxl
      case .xxxxl: Spacing.xxxxl
      case .xxxxxl: Spacing.xxxxxl
      }
    }
  }
}

/** ALF's corner-radius scale (`tokens.borderRadius`), in points. */
public enum Radius {
  public static let xxs = Scales.Radius.xxs
  public static let xs = Scales.Radius.xs
  public static let sm = Scales.Radius.sm
  public static let md = Scales.Radius.md
  public static let lg = Scales.Radius.lg
  public static let xl = Scales.Radius.xl
  public static let full = Scales.Radius.full

  public enum Step: Equatable, Sendable, CaseIterable {
    case xxs
    case xs
    case sm
    case md
    case lg
    case xl
    case full

    public var value: Double {
      switch self {
      case .xxs: Radius.xxs
      case .xs: Radius.xs
      case .sm: Radius.sm
      case .md: Radius.md
      case .lg: Radius.lg
      case .xl: Radius.xl
      case .full: Radius.full
      }
    }
  }
}

extension View {
  /** `.padding(.md)` - an ALF spacing step on every edge. */
  public func padding(_ step: Spacing.Step) -> some View {
    padding(step.value)
  }

  /** `.padding(.md, .horizontal)` - an ALF spacing step on one edge set. */
  public func padding(_ step: Spacing.Step, _ edges: Edge.Set) -> some View {
    padding(edges, step.value)
  }

  /**
   A composed inset shortcut matching ALF's `a.px_md`/`a.py_lg` idiom, where a
   view commonly takes a horizontal and a vertical step.
   */
  public func padding(_ horizontal: Spacing.Step, _ vertical: Spacing.Step) -> some View {
    padding(.horizontal, horizontal.value).padding(.vertical, vertical.value)
  }

  /** `.cornerRadius(.lg)` - an ALF radius step, with corner curves on iOS. */
  public func cornerRadius(_ step: Radius.Step) -> some View {
    modifier(RadiusModifier(radius: step.value))
  }
}

struct RadiusModifier: ViewModifier {
  let radius: Double

  func body(content: Content) -> some View {
    // `Radius.full` is ALF's "pill" sentinel; clipping to half the height is not
    // expressible as a fixed radius, so callers use `.clipShape(.capsule)` for
    // pills and this modifier for the finite steps.
    content
      .clipShape(.rect(cornerRadius: radius, style: .continuous))
  }
}
#endif

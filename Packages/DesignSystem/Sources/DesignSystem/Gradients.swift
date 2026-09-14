#if canImport(SwiftUI)
import DesignTokens
import SwiftUI

/**
 The eight ALF gradient presets as `LinearGradient`s.

 The token data records only stops; the axis comes from `GradientFill`'s
 top-left to bottom-right diagonal, which `GradientPreset.diagonalStart` /
 `.diagonalEnd` record as unit-square points. `LinearGradient` takes start and
 end points, so the conversion is direct.

 ```swift
 GradientFill(.sky) { content }
 ```
 */
public enum GradientName: String, Equatable, Sendable, CaseIterable {
  case primary
  case sky
  case midnight
  case sunrise
  case sunset
  case summer
  case nordic
  case bonfire

  /** The preset from `GradientPreset.designTokens`. */
  public var preset: Gradient {
    switch self {
    case .primary: GradientPreset.designTokens.primary
    case .sky: GradientPreset.designTokens.sky
    case .midnight: GradientPreset.designTokens.midnight
    case .sunrise: GradientPreset.designTokens.sunrise
    case .sunset: GradientPreset.designTokens.sunset
    case .summer: GradientPreset.designTokens.summer
    case .nordic: GradientPreset.designTokens.nordic
    case .bonfire: GradientPreset.designTokens.bonfire
    }
  }

  /**
   The gradient as a SwiftUI `LinearGradient` on `GradientFill`'s diagonal axis.
   The stop positions become `Gradient.Stop.location` values, so a preset with
   four uneven stops renders exactly where ALF draws them.
   */
  public var linearGradient: LinearGradient {
    LinearGradient(
      stops: preset.stops.map { Gradient.Stop(color: Color(hex: $0.color), location: $0.position) },
      startPoint: UnitPoint(x: GradientPreset.diagonalStart.x, y: GradientPreset.diagonalStart.y),
      endPoint: UnitPoint(x: GradientPreset.diagonalEnd.x, y: GradientPreset.diagonalEnd.y))
  }

  /** The preset's single hover colour, for web-parity states. */
  public var hoverColor: Color { Color(hex: preset.hoverColor) }
}

/**
 A view that fills with a gradient preset, the SwiftUI counterpart of ALF's
 `GradientFill`.
 */
public struct GradientFill<Content: View>: View {
  private let name: GradientName
  private let content: Content

  public init(_ name: GradientName, @ViewBuilder content: () -> Content) {
    self.name = name
    self.content = content()
  }

  public var body: some View {
    content.background(name.linearGradient)
  }
}
#endif

#if canImport(SwiftUI)
import DesignSystemCore
import DesignTokens
import SwiftUI

/**
 Typography view helpers, the SwiftUI counterpart of ALF's `<Text>`.

 ```swift
 AlfText("Hello", scale: .md, weight: Scales.FontWeight.semiBold)
 ```
 */
public struct AlfText: View {
  private let content: String
  private let scale: TypeScale
  private let weight: String
  private let color: Color?

  @Environment(\.alfTheme) private var theme
  @Environment(\.alfFontFamily) private var family
  @Environment(\.alfFontScale) private var fontScale

  public init(
    _ content: String,
    scale: TypeScale = .md,
    weight: String = Scales.FontWeight.normal,
    color: Color? = nil
  ) {
    self.content = content
    self.scale = scale
    self.weight = weight
    self.color = color
  }

  public var body: some View {
    Text(content)
      .font(scale.font(fontScale: fontScale, family: family, weight: weight))
      .tracking(scale.metrics(fontScale: fontScale, family: family, weight: weight).tracking)
      .foregroundStyle(color ?? theme.atomColors.text)
      .lineSpacing(lineSpacing)
  }

  /**
   The extra points per line SwiftUI needs after the font's own leading:
   `resolvedLineHeight - size`. Zero when the step has no resolved line height.
   */
  private var lineSpacing: Double {
    let metrics = scale.metrics(fontScale: fontScale, family: family, weight: weight)
    guard let lineHeight = metrics.lineHeight else { return 0 }
    return max(0, lineHeight - metrics.size)
  }
}

extension View {
  /**
   Applies an ALF type step to any view's text, reading the injected theme,
   family and font scale.
   */
  public func themedFont(
    _ scale: TypeScale,
    weight: String = Scales.FontWeight.normal
  ) -> some View {
    modifier(ThemedFontModifier(scale: scale, weight: weight))
  }
}

struct ThemedFontModifier: ViewModifier {
  let scale: TypeScale
  let weight: String

  @Environment(\.alfFontFamily) private var family
  @Environment(\.alfFontScale) private var fontScale

  func body(content: Content) -> some View {
    let metrics = scale.metrics(fontScale: fontScale, family: family, weight: weight)
    content
      .font(scale.font(fontScale: fontScale, family: family, weight: weight))
      .tracking(metrics.tracking)
      .lineSpacing(max(0, (metrics.lineHeight ?? metrics.size) - metrics.size))
  }
}
#endif

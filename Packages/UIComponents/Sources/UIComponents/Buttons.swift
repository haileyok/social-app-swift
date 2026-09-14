#if canImport(SwiftUI)
import DesignSystem
import DesignTokens
import SwiftUI
import UIComponentsCore

/// The SwiftUI button, carrying the RN app's `color`/`size`/`shape` matrix.
///
/// ```swift
/// Button("Follow") { follow() }           // primary, small, pill
///   .buttonStyle(.alf)
/// Button("Delete", role: .destructive) {}
///   .buttonStyle(.alf(color: .negative, size: .large))
/// ```
///
/// The shape is chosen by the style, so a caller writes `.buttonStyle(.alf(...))`
/// rather than setting a corner radius.
public struct AlfButtonStyle: ButtonStyle {
  private let resolved: ResolvedButton

  @Environment(\.alfTheme) private var theme
  @Environment(\.isEnabled) private var isEnabled

  public init(
    color: ButtonColor = .primary,
    size: ButtonSize = .small,
    shape: ButtonShape = .`default`
  ) {
    self.resolved = ResolvedButton.resolve(color: color, size: size, shape: shape)
  }

  /// The variant this style was built with, for callers that need to react to it.
  public var variant: (color: ButtonColor, size: ButtonSize, shape: ButtonShape) {
    (resolved.color, resolved.size, resolved.shape)
  }

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .modifier(AlfButtonLabel(modifier: self, isPressed: configuration.isPressed))
  }

  /// The container and label styling, kept in a modifier so it can read the
  /// environment (`isEnabled`, theme) that a `ButtonStyle` may also read but
  /// which is clearer in one place.
  fileprivate struct AlfButtonLabel: ViewModifier {
    let modifier: AlfButtonStyle
    let isPressed: Bool

    @Environment(\.alfTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
      let resolved = modifier.resolved
      let metrics = resolved.metrics
      let background = resolved.background(disabled: !isEnabled, interacting: isPressed)
      let foreground = resolved.foreground(disabled: !isEnabled)
      content
        .font(
          metrics.textScale.typeScale.font(fontScale: fontScale, family: family, weight: metrics.fontWeight.rawValue)
        )
        .foregroundStyle(foreground.resolve(theme))
        .multilineTextAlignment(.center)
        .padding(.vertical, metrics.paddingVertical)
        .padding(.horizontal, metrics.paddingHorizontal)
        .frame(
          minWidth: metrics.side,
          minHeight: metrics.side
        )
        .background(backgroundColor(background))
        .contentShape(shapeContent)
        .clipShape(shapeClip)
        .opacity(isEnabled ? 1 : 0.999)
    }

    @Environment(\.alfFontScale) private var fontScale
    @Environment(\.alfFontFamily) private var family

    private func backgroundColor(_ token: ColorToken?) -> Color {
      token?.resolve(theme) ?? .clear
    }

    private var shapeClip: AnyShape {
      let radius = modifier.resolved.metrics.cornerRadius
      if let radius {
        return AnyShape(.rect(cornerRadius: radius, style: .continuous))
      }
      return AnyShape(.capsule)
    }

    private var shapeContent: AnyShape { shapeClip }
  }
}

extension ButtonStyle where Self == AlfButtonStyle {
  /// The Bluesky button style. Defaults to primary/small/pill.
  public static var alf: AlfButtonStyle { AlfButtonStyle() }

  /// The Bluesky button style with an explicit matrix position.
  public static func alf(
    color: ButtonColor = .primary,
    size: ButtonSize = .small,
    shape: ButtonShape = .`default`
  ) -> AlfButtonStyle {
    AlfButtonStyle(color: color, size: size, shape: shape)
  }
}

/// The button's label text, sized by the enclosing style.
///
/// This is the counterpart of the RN `<ButtonText>`. The style already sets the
/// font and colour, so this only exists to mark intent and to carry an
/// accessibility label for icon-only buttons.
public struct AlfButtonText: View {
  private let content: String
  private let emoji: Bool

  public init(_ content: String, emoji: Bool = false) {
    self.content = content
    self.emoji = emoji
  }

  public var body: some View {
    Text(content)
  }
}

/// A convenience wrapper for the common "labelled action" button, so a caller
/// does not have to remember to apply a `ButtonStyle`.
///
/// ```swift
/// AlfButton("Follow", color: .primary) { follow() }
/// ```
public struct AlfButton: View {
  private let label: String
  private let color: ButtonColor
  private let size: ButtonSize
  private let shape: ButtonShape
  private let action: () -> Void

  public init(
    _ label: String,
    color: ButtonColor = .primary,
    size: ButtonSize = .small,
    shape: ButtonShape = .`default`,
    action: @escaping () -> Void
  ) {
    self.label = label
    self.color = color
    self.size = size
    self.shape = shape
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      Text(label)
    }
    .buttonStyle(.alf(color: color, size: size, shape: shape))
  }
}

/// An icon-only button in the `round`/`square` shapes.
public struct AlfIconButton: View {
  private let systemImage: String
  private let label: String
  private let color: ButtonColor
  private let size: ButtonSize
  private let shape: ButtonShape
  private let action: () -> Void

  public init(
    systemImage: String,
    label: String,
    color: ButtonColor = .secondary,
    size: ButtonSize = .small,
    shape: ButtonShape = .round,
    action: @escaping () -> Void
  ) {
    self.systemImage = systemImage
    self.label = label
    self.color = color
    self.size = size
    self.shape = shape
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
    }
    .buttonStyle(.alf(color: color, size: size, shape: shape))
    .accessibilityLabel(label)
  }
}
#endif

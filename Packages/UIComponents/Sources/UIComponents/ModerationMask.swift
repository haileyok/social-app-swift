#if canImport(SwiftUI)
import DesignSystem
import DesignTokens
import SwiftUI
import UIComponentsCore

/// Blurs or hides content per a ``ModerationSurface``, with a reveal
/// affordance when the cause allows overriding.
///
/// The RN app splits this across `Hider`/`ContentHider`/`PostHider`. The port
/// keeps one view: it wraps arbitrary content, decides blur-vs-filter from the
/// resolved surface, and owns the reveal state. Callers pass the surface they
/// already computed, so the view never inspects a `ModerationDecision`.
///
/// ```swift
/// ModerationMask(surface: item.moderation.content) {
///   PostBody(...)
/// }
/// ```
public struct ModerationMask<Content: View>: View {
  private let surface: ModerationSurface
  private let content: Content

  @State private var isRevealed = false

  public init(surface: ModerationSurface, @ViewBuilder content: () -> Content) {
    self.surface = surface
    self.content = content()
  }

  public var body: some View {
    switch surface {
    case .none:
      content
    case .filter:
      EmptyView()
    case .blur(let description, let allowOverride):
      blurBody(description: description, allowOverride: allowOverride)
    }
  }

  private func blurBody(description: ModerationCauseDescription, allowOverride: Bool) -> some View {
    ZStack {
      content
        .blur(radius: isRevealed ? 0 : 12)
        .accessibilityHidden(!isRevealed)
      if !isRevealed {
        ModerationMaskOverlay(
          description: description,
          allowOverride: allowOverride,
          onReveal: {
            withAnimation(.easeOut(duration: 0.2)) { isRevealed = true }
          })
      }
    }
  }
}

/// The label and reveal button drawn over blurred content.
struct ModerationMaskOverlay: View {
  let description: ModerationCauseDescription
  let allowOverride: Bool
  let onReveal: () -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    VStack(spacing: Spacing.sm) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 18, weight: .semibold))
      Text(description.name)
        .font(TypeScale.sm.font(weight: "600"))
        .multilineTextAlignment(.center)
      if allowOverride {
        Button(action: onReveal) {
          Text("Show")
            .font(TypeScale.sm.font(weight: "600"))
        }
        .buttonStyle(.alf(color: .secondary, size: .small))
        .accessibilityHint("Reveals the hidden content")
      } else {
        Text("Hidden")
          .font(TypeScale.xs.font())
      }
    }
    .foregroundStyle(theme.atomColors.textInverted)
    .padding(.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.atomColors.bgContrast900.opacity(0.6))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(description.name). \(description.description)")
  }
}
#endif

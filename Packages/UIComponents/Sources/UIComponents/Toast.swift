#if canImport(SwiftUI)
import DesignSystem
import DesignTokens
import SwiftUI
import UIComponentsCore

/// The toast presenter, held by a view (or the app) and read by the modifier.
///
/// A toast is owned by whoever presents it: the core ``ToastState`` carries the
/// queue, and this object makes it observable so a modifier can animate the
/// banner in and out. The app can hold one presenter at its root and show toasts
/// from anywhere.
///
/// ```swift
/// // at the root
/// RootView().toastPresenter(toastPresenter)
/// // anywhere below
/// toastPresenter.show(Toast(message: "Post deleted", kind: .success))
/// ```
@Observable
public final class ToastPresenter {
  /// The queue state the modifier renders.
  public private(set) var state = ToastState()

  public init() {}

  /// Shows a toast, replacing the visible one.
  public func show(_ toast: Toast) {
    state.show(toast)
  }

  /// Convenience for the common message-only toast.
  public func show(_ message: String, kind: ToastKind = .neutral) {
    show(Toast(message: message, kind: kind))
  }

  /// Dismisses the visible toast and promotes the next queued one.
  public func dismiss() {
    state.dismiss()
  }

  /// Dismisses everything.
  public func clear() {
    state.clear()
  }
}

/// Renders the presenter's current toast at the bottom of the content.
///
/// The banner auto-dismisses after its duration, and a tap dismisses it
/// immediately. The accessibility announcement is posted when a toast appears so
/// VoiceOver reads it without the user navigating to the banner.
public struct ToastModifier: ViewModifier {
  private let presenter: ToastPresenter

  @Environment(\.alfTheme) private var theme

  public init(presenter: ToastPresenter) {
    self.presenter = presenter
  }

  public func body(content: Content) -> some View {
    content
      .overlay(alignment: .bottom) {
        if let toast = presenter.state.current {
          ToastBanner(toast: toast) {
            presenter.dismiss()
          }
          .padding(.horizontal, Spacing.lg)
          .padding(.bottom, Spacing.xxl)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .id(toast.id)
          .task(id: toast.id) {
            try? await Task.sleep(for: .seconds(toast.duration))
            presenter.dismiss()
          }
        }
      }
      .animation(.easeOut(duration: 0.25), value: presenter.state.current?.id)
  }
}

extension View {
  /// Attaches a toast presenter to this view's bottom edge.
  public func toastPresenter(_ presenter: ToastPresenter) -> some View {
    modifier(ToastModifier(presenter: presenter))
  }
}

/// One toast banner.
public struct ToastBanner: View {
  private let toast: Toast
  private let onDismiss: () -> Void

  @Environment(\.alfTheme) private var theme

  public init(toast: Toast, onDismiss: @escaping () -> Void) {
    self.toast = toast
    self.onDismiss = onDismiss
  }

  public var body: some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: iconName)
        .font(.system(size: 14, weight: .semibold))
      Text(toast.message)
        .font(TypeScale.sm.font(weight: "500"))
        .lineLimit(3)
      Spacer(minLength: 0)
    }
    .foregroundStyle(theme.atomColors.textInverted)
    .padding(.md)
    .background(theme.atomColors.bgContrast900)
    .clipShape(.rect(cornerRadius: Radius.lg, style: .continuous))
    .alfShadow(.lg)
    .contentShape(.rect)
    .onTapGesture(perform: onDismiss)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isStaticText)
  }

  private var iconName: String {
    switch toast.kind {
    case .neutral: "info.circle.fill"
    case .success: "checkmark.circle.fill"
    case .error: "exclamationmark.triangle.fill"
    }
  }
}
#endif

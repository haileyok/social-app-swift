#if canImport(SwiftUI)
import DesignSystem
import DesignTokens
import SwiftUI
import UIComponentsCore

/// The full-surface list states: loading, empty, and error.
///
/// A list view switches on a ``ListState`` and renders one of these, which keeps
/// the copy and the retry affordance in one place:
///
/// ```swift
/// switch state {
/// case .loading: ListSkeleton()
/// case .empty: EmptyStateView(strings: .feed) { refresh() }
/// case .error(let err): ErrorStateView(error: err) { retry() }
/// default: content
/// }
/// ```
public struct EmptyStateView: View {
  private let icon: String
  private let title: String
  private let message: String
  private let actionLabel: String?
  private let action: (() -> Void)?

  @Environment(\.alfTheme) private var theme

  public init(
    icon: String = "square.stack",
    title: String,
    message: String,
    actionLabel: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.icon = icon
    self.title = title
    self.message = message
    self.actionLabel = actionLabel
    self.action = action
  }

  /// Builds an empty state from a ``ListStrings``.
  public init(
    strings: ListStrings,
    icon: String = "square.stack",
    actionLabel: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.init(
      icon: icon,
      title: strings.emptyTitle,
      message: strings.emptyMessage,
      actionLabel: actionLabel,
      action: action)
  }

  public var body: some View {
    StateScaffold(
      icon: icon, title: title, message: message,
      actionLabel: actionLabel, action: action)
  }
}

/// The error state, with a retry action.
public struct ErrorStateView: View {
  private let error: ListState.ListErrorState
  private let retry: () -> Void

  public init(error: ListState.ListErrorState, retry: @escaping () -> Void) {
    self.error = error
    self.retry = retry
  }

  public init(
    title: String, message: String, retryLabel: String = "Retry", retry: @escaping () -> Void
  ) {
    self.init(
      error: ListState.ListErrorState(title: title, message: message), retry: retry)
  }

  public var body: some View {
    StateScaffold(
      icon: "exclamationmark.triangle",
      title: error.title,
      message: error.message,
      actionLabel: "Retry",
      action: retry)
  }
}

/// The shared layout for the empty and error states: a centred icon, a title, a
/// message, and an optional action.
struct StateScaffold: View {
  let icon: String
  let title: String
  let message: String
  let actionLabel: String?
  let action: (() -> Void)?

  @Environment(\.alfTheme) private var theme

  var body: some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: icon)
        .font(.system(size: 32, weight: .regular))
        .foregroundStyle(theme.atomColors.textContrastMedium)
      Text(title)
        .font(TypeScale.lg.font(weight: "600"))
        .foregroundStyle(theme.atomColors.text)
        .multilineTextAlignment(.center)
      Text(message)
        .font(TypeScale.md.font())
        .foregroundStyle(theme.atomColors.textContrastMedium)
        .multilineTextAlignment(.center)
      if let actionLabel, let action {
        Button(actionLabel, action: action)
          .buttonStyle(.alf(color: .secondary, size: .small))
          .padding(.top, Spacing.xs)
      }
    }
    .frame(maxWidth: 320)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.xxl)
  }
}

/// The first-load skeleton: a column of placeholder post rows.
public struct ListSkeleton: View {
  private let rowCount: Int

  public init(rowCount: Int = ListState.skeletonRowCount) {
    self.rowCount = rowCount
  }

  public var body: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      ForEach(0..<rowCount, id: \.self) { _ in
        PostSkeletonRow()
        Divider()
      }
    }
    .accessibilityLabel("Loading")
  }
}

/// The inline retry row shown when pagination fails under existing content.
public struct RetryRow: View {
  private let message: String
  private let retry: () -> Void

  @Environment(\.alfTheme) private var theme

  public init(message: String = "Could not load more", retry: @escaping () -> Void) {
    self.message = message
    self.retry = retry
  }

  public var body: some View {
    VStack(spacing: Spacing.sm) {
      Text(message)
        .font(TypeScale.sm.font())
        .foregroundStyle(theme.atomColors.textContrastMedium)
      Button("Retry", action: retry)
        .buttonStyle(.alf(color: .secondary, size: .small))
    }
    .frame(maxWidth: .infinity)
    .padding(.lg)
  }
}

/// The trailing "load next page" spinner for an infinite list.
public struct LoadMoreSpinner: View {
  public init() {}

  public var body: some View {
    ProgressView()
      .frame(maxWidth: .infinity)
      .padding(.lg)
      .accessibilityLabel("Loading more")
  }
}
#endif

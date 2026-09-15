import DesignSystem
import DesignTokens
import SwiftUI
import UIComponents

/// Which full-screen placeholder a route landed on.
public enum PostThreadPlaceholderKind: String, Sendable, CaseIterable, Hashable {
  /// The viewer or the author blocked the other: there is no thread to show.
  case blocked
  /// The post was deleted, or the server would not hydrate it.
  case notFound
}

/// The full-screen placeholder for a thread that cannot be shown at all.
///
/// RN has two screens here - `PostThreadBlocked` and `PostThreadNotFound` -
/// which differ only in copy and glyph. One screen keyed by
/// ``PostThreadPlaceholderKind`` keeps the copy in the strings seam and gives
/// both routes one shape to render.
///
/// ```swift
/// PostThreadPlaceholderScreen(kind: .blocked)
/// ```
public struct PostThreadPlaceholderScreen: View {
  private let kind: PostThreadPlaceholderKind
  private let strings: PostThreadStrings
  private let onBack: (() -> Void)?

  @Environment(\.alfTheme) private var theme

  public init(
    kind: PostThreadPlaceholderKind,
    strings: PostThreadStrings = .defaults,
    onBack: (() -> Void)? = nil
  ) {
    self.kind = kind
    self.strings = strings
    self.onBack = onBack
  }

  public var body: some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: icon)
        .font(.system(size: 34, weight: .semibold))
        .foregroundStyle(theme.atomColors.textContrastMedium)
      Text(title)
        .font(TypeScale.lg.font(weight: Scales.FontWeight.semiBold))
        .foregroundStyle(theme.atomColors.text)
        .multilineTextAlignment(.center)
      Text(message)
        .font(TypeScale.sm.font())
        .foregroundStyle(theme.atomColors.textContrastMedium)
        .multilineTextAlignment(.center)
      if let onBack {
        Button(strings.retry, action: onBack)
          .buttonStyle(.alf(color: .secondary, size: .small))
      }
    }
    .frame(maxWidth: 340)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(Spacing.xxl)
    .background(theme.atomColors.bg)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("thread-placeholder-\(kind.rawValue)")
  }

  private var icon: String {
    switch kind {
    case .blocked: "hand.raised"
    case .notFound: "questionmark.circle"
    }
  }

  private var title: String {
    switch kind {
    case .blocked: strings.blockedTitle
    case .notFound: strings.notFoundTitle
    }
  }

  private var message: String {
    switch kind {
    case .blocked: strings.blockedMessage
    case .notFound: strings.notFoundMessage
    }
  }
}

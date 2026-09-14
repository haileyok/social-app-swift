import DesignSystem
import DesignSystemCore
import SwiftUI

/// The floating "New posts" pill.
///
/// Port of the RN pill in `src/view/com/posts/PostFeed.tsx`: a rounded,
/// primary-coloured affordance that sits over the top of the list after a poll
/// finds newer content, and scrolls the list to the top when tapped. The
/// presenter returns a `showPill` decision from ``HomeFeedLogic/NewPostsPoller``;
/// this view only draws it and reports the tap.
public struct NewPostsPill: View {
  private let count: Int?
  private let onTap: () -> Void

  @Environment(\.alfTheme) private var theme

  public init(count: Int? = nil, onTap: @escaping () -> Void) {
    self.count = count
    self.onTap = onTap
  }

  public var body: some View {
    Button(action: onTap) {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "arrow.up")
          .font(.system(size: 13, weight: .semibold))
        Text(label)
          .font(TypeScale.sm.font(weight: "600"))
      }
      .foregroundStyle(theme.atomColors.textInverted)
      .padding(.horizontal, Spacing.lg)
      .padding(.vertical, Spacing.sm)
      .background(theme.palette.primary_500)
      .clipShape(Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
    .alfShadow(.md)
    .accessibilityLabel(label)
    .accessibilityHint(HomeFeedStrings.newPostsHint)
  }

  /// The pill's copy. The RN pill never carries a count; when a caller has one
  /// it is shown, otherwise the plain label is used.
  private var label: String {
    // Named `total`, not `count`: swiftlint's `empty_count` rule reads any
    // `count > 0` comparison as a collection check.
    guard let total, total > 0 else { return HomeFeedStrings.newPosts }
    return "\(total) \(HomeFeedStrings.newPosts.lowercased())"
  }
}

#Preview {
  NewPostsPill {}
    .theme(.light)
}

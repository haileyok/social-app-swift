import DesignSystem
import DesignTokens
import ProfileLogic
import SwiftUI

/// The followers / following / posts metric line.
///
/// Port of `ProfileHeaderMetrics`. Each metric is a tappable run of text; the
/// labels arrive already formatted from ``ProfileHeaderViewData``, so this view
/// only lays them out and reports which one was pressed.
public struct ProfileHeaderMetrics: View {
  private let data: ProfileHeaderViewData
  private let strings: any ProfileStrings
  private let onSelect: (Metric) -> Void

  @Environment(\.alfTheme) private var theme

  /// Which metric was tapped.
  public enum Metric: String, Sendable, CaseIterable {
    case followers
    case follows
    case posts
  }

  public init(
    data: ProfileHeaderViewData,
    strings: any ProfileStrings = defaultProfileStrings,
    onSelect: @escaping (Metric) -> Void
  ) {
    self.data = data
    self.strings = strings
    self.onSelect = onSelect
  }

  public var body: some View {
    HStack(spacing: Spacing.xs) {
      metric(strings.followersCount(data.followersCountLabel), .followers)
      separator
      metric(strings.followsCount(data.followsCountLabel), .follows)
      separator
      metric(strings.postsCount(data.postsCountLabel), .posts)
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private var separator: some View {
    Text("·")
      .font(TypeScale.sm.font())
      .foregroundStyle(theme.atomColors.textContrastLow)
      .accessibilityHidden(true)
  }

  private func metric(_ label: String, _ kind: Metric) -> some View {
    Button {
      onSelect(kind)
    } label: {
      Text(label)
        .font(TypeScale.sm.font())
        .foregroundStyle(theme.atomColors.textContrastMedium)
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(.isLink)
  }
}

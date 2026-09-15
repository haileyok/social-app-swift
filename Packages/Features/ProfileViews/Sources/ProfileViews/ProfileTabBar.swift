import DesignSystem
import DesignTokens
import ProfileLogic
import SwiftUI
import UIComponents

/// The profile's section bar.
///
/// Port of the `TabBar` the RN profile screen renders over its pager. The bar is
/// driven by ``ProfileTabVisibility/sections``, so the labeler variant loses the
/// Media and Videos tabs and gains Labels without this view knowing why.
public struct ProfileTabBar: View {
  private let sections: [ProfileSection]
  private let selected: ProfileSection
  private let strings: any ProfileStrings
  private let onSelect: (ProfileSection) -> Void

  @Environment(\.alfTheme) private var theme

  public init(
    sections: [ProfileSection],
    selected: ProfileSection,
    strings: any ProfileStrings = defaultProfileStrings,
    onSelect: @escaping (ProfileSection) -> Void
  ) {
    self.sections = sections
    self.selected = selected
    self.strings = strings
    self.onSelect = onSelect
  }

  public var body: some View {
    HStack(spacing: 0) {
      ForEach(sections, id: \.rawValue) { section in
        tab(section)
      }
    }
    .padding(.top, Spacing.sm)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(theme.atomColors.borderContrastLow)
        .frame(height: 1)
    }
  }

  private func tab(_ section: ProfileSection) -> some View {
    Button {
      onSelect(section)
    } label: {
      VStack(spacing: Spacing.xs) {
        Text(strings.tabTitle(section.title))
          .font(TypeScale.sm.font(weight: weight(for: section)))
          .foregroundStyle(
            section == selected ? theme.atomColors.text : theme.atomColors.textContrastMedium)
          .lineLimit(1)
        Rectangle()
          .fill(section == selected ? theme.atomColors.text : .clear)
          .frame(height: 2)
          .frame(maxWidth: .infinity)
      }
      .frame(maxWidth: .infinity)
      .padding(.bottom, Spacing.xs)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(section == selected ? [.isSelected] : [])
  }

  private func weight(for section: ProfileSection) -> String {
    section == selected ? Scales.FontWeight.semiBold : Scales.FontWeight.normal
  }
}

extension ProfileSection {
  /// The tab label, in the RN app's wording.
  public var title: String {
    switch self {
    case .filters: "Labels"
    case .lists: "Lists"
    case .posts: "Posts"
    case .replies: "Replies"
    case .media: "Media"
    case .videos: "Videos"
    case .likes: "Likes"
    case .feeds: "Feeds"
    case .starterPacks: "Starter Packs"
    }
  }
}

extension ProfileTab {
  /// The tab label.
  public var title: String {
    switch self {
    case .posts: "Posts"
    case .replies: "Replies"
    case .media: "Media"
    case .videos: "Videos"
    case .likes: "Likes"
    }
  }
}

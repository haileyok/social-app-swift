import DesignSystem
import DesignSystemCore
import SwiftUI

/// The feed switcher: one tab per pinned feed.
///
/// RN drives this with a horizontal paging carousel whose header is a
/// `TabBar`. Native-first here: a `ScrollView` of tabs with the active one
/// underlined, in a `safeAreaInset(edge: .top)`. That keeps the pinned tab
/// available while the feed scrolls (RN's header collapses), which is the
/// behaviour iOS users expect from a segmented feed switcher and avoids
/// rebuilding the paging container.
public struct FeedSwitcherBar: View {
  private let feeds: [PinnedFeed]
  private let selected: FeedDescriptor?
  private let onSelect: (FeedDescriptor) -> Void

  @Environment(\.alfTheme) private var theme

  public init(
    feeds: [PinnedFeed],
    selected: FeedDescriptor?,
    onSelect: @escaping (FeedDescriptor) -> Void
  ) {
    self.feeds = feeds
    self.selected = selected
    self.onSelect = onSelect
  }

  public var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Spacing.sm) {
        ForEach(feeds, id: \.config.id) { feed in
          tab(feed)
        }
      }
      .padding(.horizontal, Spacing.lg)
    }
    .scrollClipDisabled()
    .background(theme.atomColors.bg)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(theme.atomColors.borderContrastLow)
        .frame(height: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(HomeFeedStrings.feedSwitcherLabel)
  }

  @ViewBuilder
  private func tab(_ feed: PinnedFeed) -> some View {
    let isSelected = feed.descriptor == selected
    Button {
      onSelect(feed.descriptor)
    } label: {
      VStack(spacing: Spacing.sm) {
        Text(label(feed))
          .font(TypeScale.md.font(weight: isSelected ? "600" : "500"))
          .foregroundStyle(
            isSelected ? theme.atomColors.text : theme.atomColors.textContrastMedium)
          .lineLimit(1)
        Rectangle()
          .fill(isSelected ? theme.colors.primary500 : .clear)
          .frame(height: 2)
          .clipShape(.rect(cornerRadius: Radius.full, style: .continuous))
      }
      .padding(.top, Spacing.lg)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
  }

  /// The tab's label: the resolved display name, or the generic fallback.
  private func label(_ feed: PinnedFeed) -> String {
    let trimmed = feed.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? HomeFeedStrings.unnamedFeed : trimmed
  }
}

#Preview {
  VStack {
    FeedSwitcherBar(
      feeds: [
        PinnedFeed(config: SavedFeedEntry(id: "1", type: .timeline, value: "following", pinned: true), displayName: "Following"),
        PinnedFeed(config: SavedFeedEntry(id: "2", type: .feed, value: "at://x", pinned: true), displayName: "Science"),
      ],
      selected: .following,
      onSelect: { _ in })
    Spacer()
  }
  .theme(ThemePreference.light)
}

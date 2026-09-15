import DesignSystem
import DesignTokens
import SwiftUI

import NotificationsLogic

/**
 The All / Mentions / Priority filter control.

 The RN screen uses its pager's `TabBar`
 (`~/bluesky/social-app/src/view/screens/Notifications.tsx`); this is the same
 affordance as a segmented row, sized for a phone. The unread count rides on the
 All tab, matching the RN tab which shows the unread bell rather than a number
 per tab.
 */
public struct NotificationsFilterBar: View {
  @Binding private var selection: NotificationsFilterTab
  private let unread: UnreadCount

  @Environment(\.alfTheme) private var theme

  public init(selection: Binding<NotificationsFilterTab>, unread: UnreadCount = .none) {
    self._selection = selection
    self.unread = unread
  }

  public var body: some View {
    HStack(spacing: Spacing.xs) {
      ForEach(NotificationsFilterTab.allCases) { tab in
        tabButton(tab)
      }
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.vertical, Spacing.sm)
    .background(theme.atomColors.bg)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(theme.atomColors.borderContrastLow)
        .frame(height: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(NotificationsAccessibility.filterTabs)
  }

  private func tabButton(_ tab: NotificationsFilterTab) -> some View {
    let isSelected = tab == selection
    return Button {
      selection = tab
    } label: {
      HStack(spacing: Spacing.xs) {
        Text(tab.title)
          .font(TypeScale.md.font(weight: isSelected ? Scales.FontWeight.semiBold : Scales.FontWeight.normal))
        if tab == .all, !unread.isEmpty {
          unreadBadge
        }
      }
      .foregroundStyle(isSelected ? theme.atomColors.text : theme.atomColors.textContrastMedium)
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.sm)
      .background(isSelected ? theme.atomColors.bgContrast100 : .clear)
      .clipShape(.capsule)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(NotificationsAccessibility.filterTab(tab))
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  /// The unread badge, capped at the logic package's `30+` state.
  private var unreadBadge: some View {
    Text(unread.rawValue)
      .font(TypeScale.xs.font(weight: Scales.FontWeight.semiBold))
      .foregroundStyle(theme.colors.white)
      .padding(.horizontal, Spacing.xs)
      .padding(.vertical, 1)
      .background(theme.colors.primary500)
      .clipShape(.capsule)
      .accessibilityLabel("\(unread.count) unread notifications")
  }
}

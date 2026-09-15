import DesignSystem
import DesignTokens
import SwiftUI

/// The "N followers you know" pill at the top of a followers list.
///
/// The RN followers screen renders a known-followers header above the list when
/// the viewer has any. It is a tap target into the known-followers screen, so it
/// stays a separate view from ``KnownFollowersLine`` (which is a sentence in the
/// profile header).
public struct KnownFollowersPill: View {
  private let count: Int
  private let onSelect: () -> Void

  @Environment(\.alfTheme) private var theme

  public init(count: Int, onSelect: @escaping () -> Void = {}) {
    self.count = count
    self.onSelect = onSelect
  }

  public var body: some View {
    Button(action: onSelect) {
      HStack(spacing: Spacing.sm) {
        Image(systemName: "person.2.fill")
          .font(TypeScale.sm.font())
        Text("\(count) followers you know")
          .font(TypeScale.sm.font(weight: Scales.FontWeight.semiBold))
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(TypeScale.xs.font())
      }
      .foregroundStyle(theme.atomColors.text)
      .padding(.horizontal, Spacing.lg)
      .padding(.vertical, Spacing.md)
      .background(theme.atomColors.bgContrast50)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
  }
}

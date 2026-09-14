import DesignSystem
import DesignTokens
import Lexicons
import ProfileLogic
import SwiftUI
import UIComponents

/// The "Followed by ..." line under a profile's description.
///
/// Port of `KnownFollowers`. The derivation is `KnownFollowersLogic`'s; this view
/// renders the stacked avatars and the sentence, and reports a tap so the caller
/// can push the known-followers list.
public struct KnownFollowersLine: View {
  private let knownFollowers: App.Bsky.ActorDefs_KnownFollowers
  private let strings: any ProfileStrings
  private let onSelect: () -> Void

  @Environment(\.alfTheme) private var theme

  public init(
    knownFollowers: App.Bsky.ActorDefs_KnownFollowers,
    strings: any ProfileStrings = defaultProfileStrings,
    onSelect: @escaping () -> Void = {}
  ) {
    self.knownFollowers = knownFollowers
    self.strings = strings
    self.onSelect = onSelect
  }

  public var body: some View {
    Button(action: onSelect) {
      HStack(spacing: Spacing.sm) {
        avatarStack
        Text(label)
          .font(TypeScale.sm.font())
          .foregroundStyle(theme.atomColors.textContrastMedium)
          .multilineTextAlignment(.leading)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }

  /// The sentence, built from the first two preview names and the total.
  private var label: String {
    let names = previews.prefix(2).map { $0.displayName ?? "@\($0.handle.rawValue)" }
    return strings.knownFollowers(Array(names), total: KnownFollowersLogic.count(knownFollowers))
  }

  private var previews: [App.Bsky.ActorDefs_ProfileViewBasic] {
    KnownFollowersLogic.previews(knownFollowers)
  }

  /// Overlapping avatars, the newest first, matching the RN row.
  private var avatarStack: some View {
    HStack(spacing: -Spacing.sm) {
      ForEach(previews.prefix(3), id: \.did.rawValue) { follower in
        Avatar(
          avatar: follower.avatar?.rawValue,
          handle: follower.handle.rawValue,
          displayName: follower.displayName,
          size: .xs)
        .overlay(Circle().strokeBorder(theme.atomColors.bg, lineWidth: 1.5))
      }
    }
    .accessibilityHidden(true)
  }
}

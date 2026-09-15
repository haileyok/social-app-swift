import DesignSystem
import DesignTokens
import OnboardingLogic
import SwiftUI
import UIComponents

/// A selectable interest chip, port of `StepInterests/InterestButton.tsx`.
///
/// The selected state carries both a fill change and a checkmark, so it is
/// legible without colour. The label is the logic layer's display name for the
/// tag, falling back to the capitalized tag.
struct InterestChip: View {
  private let tag: String
  private let isSelected: Bool
  private let action: () -> Void

  @Environment(\.alfTheme) private var theme

  init(tag: String, isSelected: Bool, action: @escaping () -> Void) {
    self.tag = tag
    self.isSelected = isSelected
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: Spacing.xs) {
        if isSelected {
          Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
        }
        Text(OnboardingCopy.interestName(tag))
      }
      .font(TypeScale.md.font(weight: isSelected ? Scales.FontWeight.medium : Scales.FontWeight.normal))
      .foregroundStyle(isSelected ? theme.atomColors.textInverted : theme.atomColors.text)
      .padding(.lg, .horizontal)
      .padding(.sm, .vertical)
      .background(isSelected ? theme.atomColors.bgContrast900 : theme.atomColors.bgContrast100)
      .clipShape(.capsule)
      .overlay {
        if !isSelected {
          Capsule().strokeBorder(theme.atomColors.borderContrastLow)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(OnboardingCopy.interestName(tag))
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    .accessibilityIdentifier(OnboardingAccessibility.interestChip(tag))
  }
}

/// A selectable account row, used by the suggested-accounts step.
///
/// The avatar and names come from ``SuggestedUser``; the selection is a
/// checkmark disc rather than a follow button, because the step follows the
/// whole selection at once on continue.
struct SuggestedAccountRow: View {
  private let user: SuggestedUser
  private let isSelected: Bool
  private let action: () -> Void

  @Environment(\.alfTheme) private var theme

  init(user: SuggestedUser, isSelected: Bool, action: @escaping () -> Void) {
    self.user = user
    self.isSelected = isSelected
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: Spacing.md) {
        AvatarPlaceholder(seed: user.displayName ?? user.handle, size: .md)
        VStack(alignment: .leading, spacing: 2) {
          if let displayName = user.displayName, !displayName.isEmpty {
            Text(displayName)
              .font(TypeScale.md.font(weight: Scales.FontWeight.medium))
              .foregroundStyle(theme.atomColors.text)
              .lineLimit(1)
          }
          Text("@\(user.handle)")
            .font(TypeScale.sm.font())
            .foregroundStyle(theme.atomColors.textContrastMedium)
            .lineLimit(1)
        }
        Spacer(minLength: Spacing.sm)
        selectionIndicator
      }
      .padding(.sm, .vertical)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .disabled(user.isBlockedOrBlocking || user.isMuted)
    .accessibilityLabel(user.displayName ?? "@\(user.handle)")
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    .accessibilityIdentifier(OnboardingAccessibility.suggestedAccountRow(user.did))
  }

  /// The checkmark disc, filled when selected.
  private var selectionIndicator: some View {
    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
      .font(.system(size: 24))
      .foregroundStyle(isSelected ? theme.atomColors.text : theme.atomColors.textContrastLow)
  }
}

/// A selectable starter-pack row.
///
/// RN renders each pack through its full `StarterPackCard`; this keeps the step
/// layout (name, feeds, selection) without the card's navigation affordances,
/// which have no destination inside onboarding.
struct StarterPackRow: View {
  private let pack: SuggestedStarterPack
  private let isSelected: Bool
  private let action: () -> Void

  @Environment(\.alfTheme) private var theme

  init(pack: SuggestedStarterPack, isSelected: Bool, action: @escaping () -> Void) {
    self.pack = pack
    self.isSelected = isSelected
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: Spacing.md) {
        Image(systemName: "person.3.fill")
          .font(.system(size: 20))
          .foregroundStyle(theme.atomColors.textContrastMedium)
          .frame(width: 40, height: 40)
          .background(theme.atomColors.bgContrast100)
          .clipShape(.rect(cornerRadius: Radius.sm))
        VStack(alignment: .leading, spacing: 2) {
          Text(pack.name.isEmpty ? "Starter pack" : pack.name)
            .font(TypeScale.md.font(weight: Scales.FontWeight.medium))
            .foregroundStyle(theme.atomColors.text)
            .lineLimit(2)
          if !pack.feedURIs.isEmpty {
            Text(feedSummary)
              .font(TypeScale.sm.font())
              .foregroundStyle(theme.atomColors.textContrastMedium)
              .lineLimit(1)
          }
        }
        Spacer(minLength: Spacing.sm)
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 24))
          .foregroundStyle(isSelected ? theme.atomColors.text : theme.atomColors.textContrastLow)
      }
      .padding(.md)
      .background(theme.atomColors.bgContrast50)
      .clipShape(.rect(cornerRadius: Radius.md))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.md)
          .strokeBorder(theme.atomColors.borderContrastLow)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(pack.name)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    .accessibilityIdentifier(OnboardingAccessibility.starterPackRow(pack.uri))
  }

  /// A short description of what the pack pins.
  private var feedSummary: String {
    let count = pack.feedURIs.count
    return count == 1 ? "1 feed" : "\(count) feeds"
  }
}

import DesignSystem
import DesignTokens
import StarterPacksLogic
import SwiftUI
import UIComponents

/// The wizard's first step: the pack's name and description.
///
/// Port of `StepDetails.tsx`. The only rule the step enforces is the name's
/// length, and that lives in ``StarterPackWizard/setName(_:)`` - the field's
/// counter reads ``StarterPackConstants/maxNameLength`` so the two cannot drift.
public struct StarterPackWizardDetailsStep: View {
  private let name: Binding<String>
  private let description: Binding<String>

  @Environment(\.alfTheme) private var theme

  public init(name: Binding<String>, description: Binding<String>) {
    self.name = name
    self.description = description
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          fieldLabel(StarterPackCopy.nameLabel)
          TextField(StarterPackCopy.namePlaceholder, text: name)
            .textFieldStyle(.plain)
            .font(TypeScale.md.font())
            .padding(Spacing.md)
            .background(theme.atomColors.bgContrast50)
            .clipShape(.rect(cornerRadius: Radius.sm))
            .accessibilityIdentifier(StarterPackAccessibility.nameField)
          AlfText(
            "\(remainingNameCharacters) \(StarterPackCopy.nameLimitSuffix)", scale: .xxs,
            color: theme.atomColors.textContrastMedium)
        }

        VStack(alignment: .leading, spacing: Spacing.xs) {
          fieldLabel(StarterPackCopy.descriptionLabel)
          TextField(StarterPackCopy.descriptionPlaceholder, text: description, axis: .vertical)
            .textFieldStyle(.plain)
            .font(TypeScale.sm.font())
            .lineLimit(4...8)
            .padding(Spacing.md)
            .background(theme.atomColors.bgContrast50)
            .clipShape(.rect(cornerRadius: Radius.sm))
            .accessibilityIdentifier(StarterPackAccessibility.descriptionField)
        }
      }
      .padding(Spacing.lg)
    }
    .accessibilityIdentifier(StarterPackAccessibility.detailsStep)
  }

  /// What the counter shows. The reducer slices on write, so this is derived
  /// from the bound value rather than tracked separately.
  private var remainingNameCharacters: Int {
    max(0, StarterPackConstants.maxNameLength - name.wrappedValue.count)
  }

  private func fieldLabel(_ text: String) -> some View {
    AlfText(text, scale: .xs, weight: Scales.FontWeight.semiBold, color: theme.atomColors.textContrastMedium)
  }
}

/// The wizard's second step: the member picker.
///
/// Port of `StepProfiles.tsx`. The step searches through the injected closure and
/// renders whatever comes back; whether a row is selected, and whether adding it
/// is refused, is ``StarterPackWizard``'s answer.
public struct StarterPackWizardProfilesStep: View {
  private let results: [StarterPackProfileResult]
  private let optedOutDIDs: Set<String>
  private let isSelected: (String) -> Bool
  private let onToggle: (StarterPackProfileResult) -> Void
  private let onSearch: (String) -> Void

  @State private var query = ""

  @Environment(\.alfTheme) private var theme

  public init(
    results: [StarterPackProfileResult],
    optedOutDIDs: Set<String> = [],
    isSelected: @escaping (String) -> Bool,
    onToggle: @escaping (StarterPackProfileResult) -> Void,
    onSearch: @escaping (String) -> Void = { _ in }
  ) {
    self.results = results
    self.optedOutDIDs = optedOutDIDs
    self.isSelected = isSelected
    self.onToggle = onToggle
    self.onSearch = onSearch
  }

  public var body: some View {
    VStack(spacing: 0) {
      searchField
      Divider()
        .overlay(theme.atomColors.borderContrastLow)
      resultsList
    }
    .accessibilityIdentifier(StarterPackAccessibility.profilesStep)
  }

  private var searchField: some View {
    TextField(StarterPackCopy.searchPeoplePlaceholder, text: $query)
      .textFieldStyle(.plain)
      .font(TypeScale.sm.font())
      .padding(Spacing.sm)
      .padding(.horizontal, Spacing.md)
      .background(theme.atomColors.bgContrast50)
      .clipShape(.capsule)
      .padding(Spacing.md)
      .accessibilityIdentifier(StarterPackAccessibility.profilesSearchField)
      .onChange(of: query) { _, value in
        onSearch(value)
      }
  }

  @ViewBuilder private var resultsList: some View {
    if results.isEmpty {
      EmptyStateView(
        icon: "magnifyingglass",
        title: "No results",
        message: StarterPackCopy.searchEmptyMessage)
        .frame(minHeight: 200)
    } else {
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(results) { result in
            StarterPackSearchRow(
              name: result.profile.displayLabel,
              handle: "@\(result.profile.handle)",
              avatar: result.avatar,
              systemImage: "person.crop.circle",
              isSelected: isSelected(result.did),
              isOptedOut: optedOutDIDs.contains(result.did)
            ) {
              onToggle(result)
            }
            .accessibilityIdentifier(StarterPackAccessibility.searchRow(result.did))
            Divider()
              .overlay(theme.atomColors.borderContrastLow)
          }
        }
      }
    }
  }
}

/// The wizard's third step: the feed picker.
///
/// Port of `StepFeeds.tsx`, structurally the same as the people step. The
/// three-feed cap is the reducer's, surfaced through the refusals the footer
/// renders.
public struct StarterPackWizardFeedsStep: View {
  private let results: [StarterPackFeedResult]
  private let isSelected: (String) -> Bool
  private let onToggle: (StarterPackFeedResult) -> Void
  private let onSearch: (String) -> Void

  @State private var query = ""

  @Environment(\.alfTheme) private var theme

  public init(
    results: [StarterPackFeedResult],
    isSelected: @escaping (String) -> Bool,
    onToggle: @escaping (StarterPackFeedResult) -> Void,
    onSearch: @escaping (String) -> Void = { _ in }
  ) {
    self.results = results
    self.isSelected = isSelected
    self.onToggle = onToggle
    self.onSearch = onSearch
  }

  public var body: some View {
    VStack(spacing: 0) {
      TextField(StarterPackCopy.searchFeedsPlaceholder, text: $query)
        .textFieldStyle(.plain)
        .font(TypeScale.sm.font())
        .padding(Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .background(theme.atomColors.bgContrast50)
        .clipShape(.capsule)
        .padding(Spacing.md)
        .accessibilityIdentifier(StarterPackAccessibility.feedsSearchField)
        .onChange(of: query) { _, value in
          onSearch(value)
        }

      Divider()
        .overlay(theme.atomColors.borderContrastLow)

      if results.isEmpty {
        EmptyStateView(
          icon: "dot.radiowaves.left.and.right",
          title: "No results",
          message: StarterPackCopy.searchFeedsEmptyMessage)
          .frame(minHeight: 200)
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(results) { result in
              StarterPackSearchRow(
                name: result.feed.displayLabel,
                handle: result.creatorHandle.map { "@\($0)" } ?? result.uri,
                avatar: result.avatar,
                systemImage: "dot.radiowaves.left.and.right",
                isSelected: isSelected(result.uri),
                isOptedOut: false
              ) {
                onToggle(result)
              }
              .accessibilityIdentifier(StarterPackAccessibility.searchRow(result.uri))
              Divider()
                .overlay(theme.atomColors.borderContrastLow)
            }
          }
        }
      }
    }
    .accessibilityIdentifier(StarterPackAccessibility.feedsStep)
  }
}

/// One search result: avatar, name, subtitle, and a check when selected.
public struct StarterPackSearchRow: View {
  private let name: String
  private let handle: String
  private let avatar: String?
  private let systemImage: String
  private let isSelected: Bool
  private let isOptedOut: Bool
  private let action: () -> Void

  @Environment(\.alfTheme) private var theme

  public init(
    name: String,
    handle: String,
    avatar: String? = nil,
    systemImage: String = "person.crop.circle",
    isSelected: Bool = false,
    isOptedOut: Bool = false,
    action: @escaping () -> Void
  ) {
    self.name = name
    self.handle = handle
    self.avatar = avatar
    self.systemImage = systemImage
    self.isSelected = isSelected
    self.isOptedOut = isOptedOut
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      HStack(spacing: Spacing.sm) {
        Avatar(avatar: avatar, handle: handle, displayName: name, size: .md)
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          AlfText(name, scale: .sm, weight: Scales.FontWeight.semiBold)
            .lineLimit(1)
          AlfText(handle, scale: .xs, color: theme.atomColors.textContrastMedium)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if isOptedOut {
          StarterPackOptedOutBadge()
        }
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(
            isSelected ? theme.atomColors.text : theme.atomColors.textContrastLow)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      isSelected ? "\(name), selected" : "\(name), not selected")
    .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : [])
  }
}

/// The wizard's edit sheet: remove members or feeds already picked.
///
/// Port of `WizardEditListDialog`. The order of the rows is
/// ``WizardEditList/entries(for:wizard:)``'s: on the people step the target
/// profile leads, so the person the pack is about is the first row the user
/// sees.
public struct StarterPackWizardEditSheet: View {
  private let wizard: StarterPackWizard
  private let onRemove: (StarterPackWizardEditEntry) -> Void

  @Environment(\.alfTheme) private var theme
  @Environment(\.dismiss) private var dismiss

  public init(wizard: StarterPackWizard, onRemove: @escaping (StarterPackWizardEditEntry) -> Void) {
    self.wizard = wizard
    self.onRemove = onRemove
  }

  public var body: some View {
    NavigationStack {
      List {
        switch WizardEditList.entries(for: wizard.currentStep, wizard: wizard) {
        case .profiles(let profiles):
          ForEach(profiles, id: \.did) { profile in
            StarterPackWizardProfileRow(profile: profile)
            .swipeActions {
              Button("Remove", role: .destructive) {
                onRemove(.profile(profile))
              }
              .accessibilityIdentifier(StarterPackAccessibility.editSheetRow(profile.did))
            }
          }
        case .feeds(let feeds):
          ForEach(feeds, id: \.uri) { feed in
            StarterPackWizardFeedRow(feed: feed)
              .swipeActions {
                Button("Remove", role: .destructive) {
                  onRemove(.feed(feed))
                }
                .accessibilityIdentifier(StarterPackAccessibility.editSheetRow(feed.uri))
              }
          }
        }
      }
      .navigationTitle(StarterPackCopy.editListsTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(StarterPackCopy.editListsDoneAction) { dismiss() }
        }
      }
    }
    .accessibilityIdentifier(StarterPackAccessibility.editSheet)
  }
}

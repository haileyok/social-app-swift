import DesignSystem
import DesignTokens
import StarterPacksLogic
import SwiftUI

/**
 The wizard: details, then people, then feeds.

 Ported from `screens/StarterPack/Wizard/index.tsx` plus its three step bodies.
 The screen owns layout and text entry only. Every rule - the name slice, the
 member cap, the feed cap, the eight-member minimum, which button label a step
 carries - comes from ``StarterPackWizard``, and the refusals the reducer
 returned are rendered as inline errors rather than re-decided here.
 */
public struct StarterPackWizardScreen: View {
  private let isEditing: Bool
  private let searchProfiles: (String) -> Void
  private let searchFeeds: (String) -> Void
  private let onSubmit: (StarterPackWizard) -> Void
  private let onCancel: () -> Void

  /// Profile search results for the people step, in wire order.
  private let profileResults: [StarterPackProfileResult]
  /// Feed search results for the feeds step.
  private let feedResults: [StarterPackFeedResult]
  /// DIDs of members who opted out, which the rows badge.
  private let optedOutDIDs: Set<String>

  @State private var wizard: StarterPackWizard
  @State private var isEditSheetPresented = false

  @Environment(\.alfTheme) private var theme
  @Environment(\.dismiss) private var dismiss

  /// Creates the wizard.
  ///
  /// - Parameters:
  ///   - wizard: the initial state, from one of ``StarterPackWizard``'s
  ///     initializers (a fresh pack seeded with a target profile, or an existing
  ///     pack for editing).
  ///   - isEditing: whether this is the edit flow, which changes only the
  ///     title's verb.
  ///   - profileResults / feedResults: the current search results, keyed so the
  ///     row's selection state reads off ``StarterPackWizard``.
  ///   - optedOutDIDs: from ``StarterPackMemberSelection/optedOutDIDs(_:)``.
  ///   - searchProfiles / searchFeeds: run a search query.
  ///   - onSubmit: called with the final state when the user finishes.
  ///   - onCancel: called when the user backs out of the first step.
  public init(
    wizard: StarterPackWizard,
    isEditing: Bool = false,
    profileResults: [StarterPackProfileResult] = [],
    feedResults: [StarterPackFeedResult] = [],
    optedOutDIDs: Set<String> = [],
    searchProfiles: @escaping (String) -> Void = { _ in },
    searchFeeds: @escaping (String) -> Void = { _ in },
    onSubmit: @escaping (StarterPackWizard) -> Void = { _ in },
    onCancel: @escaping () -> Void = {}
  ) {
    _wizard = State(initialValue: wizard)
    self.isEditing = isEditing
    self.profileResults = profileResults
    self.feedResults = feedResults
    self.optedOutDIDs = optedOutDIDs
    self.searchProfiles = searchProfiles
    self.searchFeeds = searchFeeds
    self.onSubmit = onSubmit
    self.onCancel = onCancel
  }

  public var body: some View {
    VStack(spacing: 0) {
      stepIndicator
      Divider()
        .overlay(theme.atomColors.borderContrastLow)

      stepBody
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      if wizard.currentStep != .details {
        footer
      }
    }
    .background(theme.atomColors.bg)
    .accessibilityIdentifier(StarterPackAccessibility.wizard)
    .navigationTitle(StarterPackCopy.wizardHeader(for: wizard.currentStep))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button {
          if wizard.isFirstStep {
            onCancel()
            dismiss()
          } else {
            wizard.back()
          }
        } label: {
          Image(systemName: "chevron.left")
        }
        .accessibilityLabel("Back")
        .accessibilityIdentifier(StarterPackAccessibility.backButton)
      }
    }
    .sheet(isPresented: $isEditSheetPresented) {
      StarterPackWizardEditSheet(wizard: wizard) { entry in
        remove(entry)
      }
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
  }

  // MARK: - Chrome

  @ViewBuilder private var stepIndicator: some View {
    HStack(spacing: Spacing.sm) {
      ForEach(StarterPackWizardStep.order, id: \.self) { step in
        let isCurrent = step == wizard.currentStep
        AlfText(
          step.rawValue, scale: .xs,
          weight: isCurrent ? Scales.FontWeight.semiBold : Scales.FontWeight.normal,
          color: isCurrent ? theme.atomColors.text : theme.atomColors.textContrastMedium
        )
        if step != StarterPackWizardStep.order.last {
          Image(systemName: "chevron.right")
            .font(.system(size: 9))
            .foregroundStyle(theme.atomColors.textContrastLow)
            .accessibilityHidden(true)
        }
      }
      Spacer(minLength: 0)
      if isEditing {
        AlfText("Editing", scale: .xs, color: theme.atomColors.textContrastMedium)
      }
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.vertical, Spacing.sm)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(StarterPackAccessibility.wizardSteps)
  }

  @ViewBuilder private var stepBody: some View {
    switch wizard.currentStep {
    case .details:
      StarterPackWizardDetailsStep(
        name: Binding(
          get: { wizard.name ?? "" },
          set: { wizard.setName($0) }),
        description: Binding(
          get: { wizard.description ?? "" },
          set: { wizard.setDescription($0) }))
    case .profiles:
      StarterPackWizardProfilesStep(
        results: profileResults,
        optedOutDIDs: optedOutDIDs,
        isSelected: { wizard.hasProfile(did: $0) },
        onToggle: { toggleProfile($0) },
        onSearch: searchProfiles)
    case .feeds:
      StarterPackWizardFeedsStep(
        results: feedResults,
        isSelected: { wizard.hasFeed(uri: $0) },
        onToggle: { toggleFeed($0) },
        onSearch: searchFeeds)
    }
  }

  private var footer: some View {
    VStack(spacing: Spacing.sm) {
      errorLines

      HStack(spacing: Spacing.md) {
        // RN's `isEditEnabled`: more than one person, or any feed.
        if wizard.isEditEnabled {
          AlfButton(
            StarterPackCopy.editAction(count: wizard.currentItemsCount), color: .secondary,
            size: .small, shape: .rectangular
          ) {
            isEditSheetPresented = true
          }
          .accessibilityIdentifier(StarterPackAccessibility.wizardEditButton)
        }

        Spacer(minLength: 0)

        AlfText(
          "\(wizard.currentItemsCount)/\(wizard.currentItemsLimit)", scale: .sm,
          weight: Scales.FontWeight.semiBold
        )
        .accessibilityIdentifier(StarterPackAccessibility.footerCounter)

        AlfButton(
          wizard.nextButtonLabel, color: .primary, size: .large, shape: .rectangular
        ) {
          advance()
        }
        .disabled(!wizard.canSubmitCurrentStep)
        .accessibilityIdentifier(StarterPackAccessibility.nextButton)
      }
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.vertical, Spacing.md)
    .background(theme.atomColors.bgContrast25)
    .overlay(alignment: .top) {
      Divider().overlay(theme.atomColors.borderContrastLow)
    }
  }

  /// The inline error block: the reducer's refusals first, then the recorded
  /// error. RN raises the refusals as toasts; inline is the equivalent here.
  @ViewBuilder private var errorLines: some View {
    let messages = wizard.lastRefusals.map(\.message) + [wizard.error].compactMap { $0 }
    if !messages.isEmpty {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        ForEach(messages.indices, id: \.self) { index in
          HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.circle")
              .font(.system(size: 12))
              .foregroundStyle(theme.atomColors.textContrastMedium)
              .accessibilityHidden(true)
            AlfText(messages[index], scale: .xs, color: theme.atomColors.textContrastMedium)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityIdentifier(StarterPackAccessibility.inlineError)
    }
  }

  // MARK: - Actions

  /// Advances one step, or submits on the last.
  ///
  /// The people-step minimum is not re-checked: the button is already disabled
  /// below it, and ``StarterPackWizard/canSubmitCurrentStep`` owns that rule.
  private func advance() {
    guard wizard.canSubmitCurrentStep else { return }
    if wizard.isLastStep {
      onSubmit(wizard)
    } else {
      wizard.clearRefusals()
      wizard.next()
    }
  }

  /// Adds or removes a member. Both writes go through the value type, so a
  /// refusal is recorded rather than thrown away.
  private func toggleProfile(_ result: StarterPackProfileResult) {
    if wizard.hasProfile(did: result.did) {
      wizard.removeProfile(did: result.did)
    } else {
      wizard.addProfile(result.profile)
    }
  }

  /// Adds or removes a feed.
  private func toggleFeed(_ result: StarterPackFeedResult) {
    if wizard.hasFeed(uri: result.uri) {
      wizard.removeFeed(uri: result.uri)
    } else {
      wizard.addFeed(result.feed)
    }
  }

  /// Removes an entry from the edit sheet.
  private func remove(_ entry: StarterPackWizardEditEntry) {
    switch entry {
    case .profile(let profile): wizard.removeProfile(did: profile.did)
    case .feed(let feed): wizard.removeFeed(uri: feed.uri)
    }
  }
}

/// One searchable profile in the wizard's picker.
public struct StarterPackProfileResult: Identifiable, Sendable, Equatable {
  /// The account's DID, which is the row's identity.
  public let did: String
  /// The member shape the wizard stores.
  public let profile: WizardProfile
  /// The avatar URL, for the row.
  public let avatar: String?

  public var id: String { did }

  /// Creates a result.
  public init(did: String, handle: String, displayName: String? = nil, avatar: String? = nil) {
    self.did = did
    self.profile = WizardProfile(did: did, handle: handle, displayName: displayName)
    self.avatar = avatar
  }
}

/// One searchable feed in the wizard's picker.
public struct StarterPackFeedResult: Identifiable, Sendable, Equatable {
  /// The generator's AT URI, which is the row's identity.
  public let uri: String
  /// The feed shape the wizard stores.
  public let feed: WizardFeed
  /// The avatar URL, for the row.
  public let avatar: String?
  /// The generator's creator handle, for the row's subtitle.
  public let creatorHandle: String?

  public var id: String { uri }

  /// Creates a result.
  public init(uri: String, displayName: String, avatar: String? = nil, creatorHandle: String? = nil) {
    self.uri = uri
    self.feed = WizardFeed(uri: uri, displayName: displayName)
    self.avatar = avatar
    self.creatorHandle = creatorHandle
  }
}

/// One removable row in the wizard's edit sheet.
public enum StarterPackWizardEditEntry: Sendable, Equatable {
  /// A member row.
  case profile(WizardProfile)
  /// A feed row.
  case feed(WizardFeed)
}

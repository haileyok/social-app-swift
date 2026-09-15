import ATProtoClient
import Foundation
import Preferences

/// The outcome of running a step.
public enum StepOutcome: Sendable, Equatable {
  /// The step's work succeeded; the wizard should advance.
  case advanced
  /// The step's work succeeded, but the wizard stays put so the caller can
  /// show something (a saved state, a confirmation).
  case completed
  /// The step failed. Carries a typed error and a suggestion about whether
  /// onboarding can continue anyway.
  case failed(OnboardingError)
}

/// The best-effort failure policy for a step.
///
/// RN's completion step wraps its whole block in a `try/catch` that logs and
/// continues ("don't alert the user, just let them into their account"). The
/// profile and interests steps are only reachable with a session, so a failure
/// there is worth reporting. Encoding the policy next to the step keeps the
/// caller from having to know which failures are fatal.
public enum StepFailurePolicy: Sendable, Equatable {
  /// A failure blocks progress.
  case fatal
  /// A failure is logged and the step is settled anyway.
  case bestEffort

  /// The policy for a step.
  public static func policy(for step: OnboardingStep) -> StepFailurePolicy {
    switch step {
    case .finished:
      // RN's finish block is explicitly best-effort.
      return .bestEffort
    case .profile, .interests, .suggestedAccounts, .suggestedStarterPacks,
      .findContactsIntro, .findContacts:
      return .fatal
    }
  }
}

/// Performs each onboarding step's writes.
///
/// This is the piece the RN screens hold inline: `StepFinished.finishOnboarding`
/// does its five writes in a `Promise.all`, `StepInterests.saveInterests` calls
/// `setInterestsPref`, `StepSuggestedAccounts.followAll` calls
/// `bulkWriteFollows`. Collecting them here means the sequence, the params, and
/// the failure policy are all testable without a view.
///
/// The class is `@unchecked Sendable` because its only mutable state is the
/// wizard, guarded by a lock. Dependencies are all `Sendable`.
public final class OnboardingStepRunner: @unchecked Sendable {
  private let actions: any OnboardingActionService
  private let preferences: PreferencesEngine
  private let lock = NSLock()
  private var wizard: OnboardingWizard

  /// The step machine this runner drives.
  public var currentWizard: OnboardingWizard {
    lock.lock()
    defer { lock.unlock() }
    return wizard
  }

  /// Creates a runner.
  public init(
    wizard: OnboardingWizard,
    actions: any OnboardingActionService,
    preferences: PreferencesEngine
  ) {
    self.wizard = wizard
    self.actions = actions
    self.preferences = preferences
  }

  /// Creates a runner over a fresh wizard.
  public convenience init(
    configuration: OnboardingStepConfiguration = .default,
    actions: any OnboardingActionService,
    preferences: PreferencesEngine
  ) {
    self.init(
      wizard: OnboardingWizard(configuration: configuration), actions: actions,
      preferences: preferences)
  }

  /// Replaces the wizard, e.g. with one restored from a snapshot.
  public func setWizard(_ wizard: OnboardingWizard) {
    lock.lock()
    self.wizard = wizard
    lock.unlock()
  }

  // MARK: - Profile step

  /// Runs the profile step: validate, upload the avatar, write the profile.
  ///
  /// Sequence, and why:
  /// 1. Validate the display name and handle locally. Both are pure, so an
  ///    invalid input never reaches the network.
  /// 2. Upload the avatar blob (when the user chose a photo). RN defers this
  ///    to completion and uploads alongside the other writes; doing it here
  ///    keeps each step self-contained and means a failed upload does not
  ///    take the follow and preference writes down with it.
  /// 3. Write the profile record with the avatar reference.
  ///
  /// The handle is not written: a handle change is
  /// `com.atproto.identity.updateHandle`, not a profile field, and RN's
  /// onboarding never changes one. It is validated so a caller that collects
  /// one gets the same answer the signup step would.
  @discardableResult
  public func runProfileStep(
    displayName: String,
    handle: String? = nil,
    avatarImageData: Data? = nil,
    avatarMimeType: String? = nil
  ) async -> StepOutcome {
    let nameValidation = ProfileValidation.validateDisplayName(displayName)
    if case .tooLong = nameValidation {
      return .failed(
        .displayNameTooLong(maxLength: ProfileValidation.maxDisplayNameLength))
    }

    if let handle {
      switch ProfileValidation.validateHandle(handle) {
      case .empty:
        return .failed(.handleInvalid(reason: "handle was empty"))
      case .invalid(let reason):
        return .failed(.handleInvalid(reason: reason))
      case .valid:
        break
      }
    }

    let resolvedName: String
    switch nameValidation {
    case .valid(let trimmed): resolvedName = trimmed
    case .empty, .tooLong: resolvedName = ""
    }

    var result = ProfileStepResult(
      avatarImageData: avatarImageData,
      avatarMimeType: avatarMimeType,
      isCreatedAvatar: avatarImageData == nil,
      displayName: resolvedName)

    do {
      var avatar: OnboardingBlobRef?
      if let avatarImageData, let avatarMimeType {
        do {
          avatar = try await actions.uploadAvatar(
            data: avatarImageData, mimeType: avatarMimeType)
        } catch {
          return .failed(
            .avatarUploadFailed(underlying: OnboardingErrorMapper.map(error).underlying))
        }
      }
      // No starter-pack reference here: the pack is only resolved (and its
      // strong ref obtained) at completion, and RN writes the reference in the
      // same `upsertProfile` call that attaches the avatar.
      try await actions.upsertProfile(
        avatar: avatar, displayName: resolvedName, joinedViaStarterPack: nil)
      // The uploaded bytes are not kept in the result: they would be
      // re-uploaded by a resumed session that already wrote them.
      result.avatarImageData = nil
      result.avatarMimeType = nil
      storeProfileResult(result)
      return .advanced
    } catch {
      return .failed(
        .profileWriteFailed(underlying: OnboardingErrorMapper.map(error).underlying))
    }
  }

  // MARK: - Interests step

  /// Runs the interests step: write the interests preference.
  ///
  /// The taxonomy is filtered to known tags before the write, so a restored
  /// snapshot cannot push an off-vocabulary tag into the preference.
  ///
  /// `required` mirrors the RN `OnboardingInterestsRequiredEnable` gate: when
  /// on, an empty selection is refused before the write.
  @discardableResult
  public func runInterestsStep(
    selected: [String], required: Bool = false
  ) async -> StepOutcome {
    if required && selected.isEmpty {
      return .failed(.unexpected(message: "Choose at least one interest.", underlying: nil))
    }
    let tags = Interests.known(selected)
    do {
      try await actions.setInterests(tags: tags)
      storeInterestsResult(InterestsStepResult(selectedInterests: tags))
      return .advanced
    } catch {
      return .failed(
        .interestsWriteFailed(underlying: OnboardingErrorMapper.map(error).underlying))
    }
  }

  // MARK: - Suggested accounts step

  /// Runs the suggested-accounts step: follow every selected account.
  ///
  /// One `applyWrites` batch per 50 follows (RN's chunk size), through
  /// ``OnboardingActionService/createFollows(dids:via:)``. The step is
  /// best-effort in RN too (`followAll`'s toast reports the failure and the
  /// user can continue), but the wizard treats it as fatal so the caller can
  /// decide; the returned ``StepOutcome/failed(_:)`` carries the suggestion.
  @discardableResult
  public func runSuggestedAccountsStep(
    selectedDIDs: [String], via: StarterPackRef? = nil
  ) async -> StepOutcome {
    guard !selectedDIDs.isEmpty else {
      storeSuggestedAccountsResult(SuggestedAccountsStepResult(followedDIDs: []))
      return .advanced
    }
    do {
      let uris = try await actions.createFollows(dids: selectedDIDs, via: via)
      // Preserve selection order rather than dictionary order.
      let followed = selectedDIDs.filter { uris[$0] != nil }
      storeSuggestedAccountsResult(SuggestedAccountsStepResult(followedDIDs: followed))
      return .advanced
    } catch {
      let mapped = OnboardingErrorMapper.map(error)
      return .failed(.followFailed(underlying: mapped.underlying))
    }
  }

  // MARK: - Starter packs step

  /// Records the starter pack the user chose, if any.
  ///
  /// Choosing a pack does not write anything at this step: RN follows the
  /// pack's members and pins its feeds at completion, using the pack's strong
  /// reference. So this just records the choice.
  @discardableResult
  public func runStarterPacksStep(joinedStarterPackURI: String?) async -> StepOutcome {
    storeStarterPacksResult(StarterPacksStepResult(joinedStarterPackURI: joinedStarterPackURI))
    return .advanced
  }

  // MARK: - Adult content gate

  /// Applies the adult-content preference.
  ///
  /// Driven by the preferences engine's `setAdultContentEnabled`, which is a
  /// plain preference write. RN's onboarding flow has no adult-content screen:
  /// the gate is applied from the moderation settings and from the
  /// age-assurance dialog after onboarding. It is exposed here so a flow that
  /// does collect the answer (and the age-assurance gate that follows it) has
  /// the one write it needs.
  @discardableResult
  public func applyAdultContentGate(enabled: Bool) async -> StepOutcome {
    do {
      try await actions.setAdultContentEnabled(enabled)
      return .completed
    } catch {
      let mapped = OnboardingErrorMapper.map(error)
      return .failed(.preferencesUnavailable(underlying: mapped.underlying))
    }
  }

  // MARK: - Completion

  /// Runs the completion step: the batch of writes RN makes in `StepFinished`.
  ///
  /// The writes, from `StepFinished.finishOnboarding`:
  /// 1. Follow the app account plus every member of a joined starter pack.
  /// 2. Write the interests preference.
  /// 3. Overwrite the saved feeds with the three defaults, plus the pack's
  ///    feeds when a pack was joined.
  /// 4. Upsert the profile with the avatar and the `joinedViaStarterPack`.
  /// 5. Mark the NUX complete.
  ///
  /// RN runs 1-3 (and the notification permission) in a `Promise.all` and
  /// swallows every error; a resumed session must not be able to fail out of
  /// onboarding. This implementation runs them in the same order, sequentially
  /// so the exact call sequence is observable, and applies
  /// ``StepFailurePolicy/bestEffort``: the first error is recorded and the
  /// remaining writes still run.
  @discardableResult
  public func runCompletionStep(
    displayName: String? = nil,
    avatarImageData: Data? = nil,
    avatarMimeType: String? = nil,
    markNuxComplete: Bool = true
  ) async -> StepOutcome {
    let wizard = currentWizard
    var firstError: OnboardingError?

    // 1. Follows, including a joined starter pack's members.
    let pack = await resolveJoinedStarterPack(
      uri: wizard.results.starterPacks.joinedStarterPackURI)
    firstError = firstError ?? pack.error
    var followDIDs = [OnboardingConstants.bskyAppAccountDID]
    followDIDs.append(contentsOf: pack.memberDIDs)
    do {
      _ = try await actions.createFollows(dids: followDIDs, via: pack.ref)
    } catch {
      firstError =
        firstError ?? .followFailed(underlying: OnboardingErrorMapper.map(error).underlying)
    }

    // 2. Interests.
    do {
      try await actions.setInterests(tags: wizard.results.interests.selectedInterests)
    } catch {
      firstError =
        firstError ?? .interestsWriteFailed(underlying: OnboardingErrorMapper.map(error).underlying)
    }

    // 3. Saved feeds: the defaults, then the pack's feeds.
    let packFeeds = pack.feedURIs.map { SavedFeed(type: "feed", value: $0, pinned: true) }
    do {
      try await actions.overwriteSavedFeeds(DefaultSavedFeeds.all + packFeeds)
    } catch {
      firstError = firstError ?? OnboardingErrorMapper.map(error)
    }

    // 4. Profile write.
    let profileError = await writeCompletionProfile(
      displayName: displayName ?? wizard.results.profile.displayName,
      avatarImageData: avatarImageData, avatarMimeType: avatarMimeType,
      starterPackRef: pack.ref)
    if firstError == nil { firstError = profileError }

    // 5. NUX.
    if markNuxComplete {
      do {
        try await actions.upsertNux(
          id: OnboardingConstants.onboardingNuxID, completed: true, data: nil)
      } catch {
        firstError = firstError ?? OnboardingErrorMapper.map(error)
      }
    }

    // The step is settled regardless: onboarding must not be able to fail out.
    var settled = currentWizard
    settled.settle(.finished, skipped: false)
    settled.move(to: .finished)
    setWizard(settled)

    if let firstError { return .failed(firstError) }
    return .advanced
  }

  /// The resolved pieces of a joined starter pack.
  private struct ResolvedStarterPack {
    var ref: StarterPackRef?
    var feedURIs: [String] = []
    var memberDIDs: [String] = []
    var error: OnboardingError?
  }

  /// Resolves the joined starter pack, if one was chosen.
  ///
  /// RN logs and continues when a pack cannot be resolved, because failing to
  /// read a pack must not block the user from entering the app. The error is
  /// returned rather than thrown so the caller can carry it alongside the
  /// remaining writes.
  private func resolveJoinedStarterPack(uri: String?) async -> ResolvedStarterPack {
    guard let uri else { return ResolvedStarterPack() }
    do {
      let detail = try await actions.getStarterPack(uri: uri)
      let members: [String]
      if let listURI = detail.listURI {
        members = try await actions.getListMemberDIDs(listURI: listURI)
      } else {
        members = []
      }
      return ResolvedStarterPack(
        ref: detail.ref, feedURIs: detail.feedURIs, memberDIDs: members)
    } catch {
      return ResolvedStarterPack(error: OnboardingErrorMapper.map(error))
    }
  }

  /// Uploads the avatar (when present) and writes the profile record.
  private func writeCompletionProfile(
    displayName: String,
    avatarImageData: Data?,
    avatarMimeType: String?,
    starterPackRef: StarterPackRef?
  ) async -> OnboardingError? {
    do {
      var avatar: OnboardingBlobRef?
      if let avatarImageData, let avatarMimeType {
        avatar = try await actions.uploadAvatar(
          data: avatarImageData, mimeType: avatarMimeType)
      }
      try await actions.upsertProfile(
        avatar: avatar, displayName: displayName, joinedViaStarterPack: starterPackRef)
      return nil
    } catch {
      return .profileWriteFailed(underlying: OnboardingErrorMapper.map(error).underlying)
    }
  }

  // MARK: - Internals

  private func storeProfileResult(_ result: ProfileStepResult) {
    lock.lock()
    wizard.setProfileResult(result)
    lock.unlock()
  }

  private func storeInterestsResult(_ result: InterestsStepResult) {
    lock.lock()
    wizard.setInterestsResult(result)
    lock.unlock()
  }

  private func storeSuggestedAccountsResult(_ result: SuggestedAccountsStepResult) {
    lock.lock()
    wizard.setSuggestedAccountsResult(result)
    lock.unlock()
  }

  private func storeStarterPacksResult(_ result: StarterPacksStepResult) {
    lock.lock()
    wizard.setStarterPacksResult(result)
    lock.unlock()
  }
}

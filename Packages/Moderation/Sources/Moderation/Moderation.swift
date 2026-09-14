import Foundation

/// Runs the engine over a profile: merges the account and profile decisions so
/// a single call covers both account-level and self-profile labels.
public func moderateProfile(
  _ subject: ProfileViewBasic,
  opts: ModerationOpts
) -> ModerationDecision {
  ModerationDecision.merge([decideAccount(subject, opts: opts), decideProfile(subject, opts: opts)])
}

public func moderatePost(_ subject: PostView, opts: ModerationOpts) -> ModerationDecision {
  decidePost(subject, opts: opts)
}

public func moderateNotification(
  _ subject: NotificationView,
  opts: ModerationOpts
) -> ModerationDecision {
  decideNotification(subject, opts: opts)
}

public func moderateFeedGenerator(
  _ subject: FeedGeneratorView,
  opts: ModerationOpts
) -> ModerationDecision {
  decideFeedGenerator(subject, opts: opts)
}

public func moderateUserList(_ subject: ListView, opts: ModerationOpts) -> ModerationDecision {
  decideUserList(subject, opts: opts)
}

public func moderateStatus(_ subject: StatusView, opts: ModerationOpts) -> ModerationDecision {
  decideStatus(subject, opts: opts)
}

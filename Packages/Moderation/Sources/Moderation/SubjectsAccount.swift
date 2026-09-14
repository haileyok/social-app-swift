/// Decides an account's moderation state from viewer state and account labels.
public func decideAccount(
  did: String,
  viewer: ActorViewerState?,
  labels: [Label]?,
  opts: ModerationOpts
) -> ModerationDecision {
  var acc = ModerationDecision()
  acc.setDid(did)
  acc.setIsMe(did == opts.userDid)
  if viewer?.muted == true {
    if let list = viewer?.mutedByList {
      acc.addMutedByList(list)
    } else {
      acc.addMuted(viewer?.muted)
    }
  }
  if viewer?.blocking?.isEmpty == false {
    if let list = viewer?.blockingByList {
      acc.addBlockingByList(list)
    } else {
      acc.addBlocking(viewer?.blocking != nil)
    }
  }
  acc.addBlockedBy(viewer?.blockedBy)
  for label in filterAccountLabels(labels) {
    acc.addLabel(target: .account, label: label, opts: opts)
  }
  return acc
}

/// Convenience overload for any subject exposing the account fields.
public func decideAccount(_ subject: ProfileViewBasic, opts: ModerationOpts) -> ModerationDecision {
  decideAccount(did: subject.did, viewer: subject.viewer, labels: subject.labels, opts: opts)
}

/// Convenience overload for status views.
public func decideAccount(_ subject: StatusView, opts: ModerationOpts) -> ModerationDecision {
  decideAccount(did: subject.did, viewer: nil, labels: nil, opts: opts)
}

/// Excludes self-profile labels (they belong to the profile target) unless the
/// label is `!no-unauthenticated`, which must still apply at account level.
public func filterAccountLabels(_ labels: [Label]?) -> [Label] {
  guard let labels else { return [] }
  return labels.filter {
    !$0.uri.hasSuffix("/app.bsky.actor.profile/self") || $0.val == "!no-unauthenticated"
  }
}

/// Decides a profile's moderation state from its self-profile labels.
public func decideProfile(_ subject: ProfileViewBasic, opts: ModerationOpts) -> ModerationDecision {
  var acc = ModerationDecision()
  acc.setDid(subject.did)
  acc.setIsMe(subject.did == opts.userDid)
  for label in filterProfileLabels(subject.labels) {
    acc.addLabel(target: .profile, label: label, opts: opts)
  }
  return acc
}

/// Keeps only labels attached to the account's self-profile record.
public func filterProfileLabels(_ labels: [Label]?) -> [Label] {
  guard let labels else { return [] }
  return labels.filter { $0.uri.hasSuffix("/app.bsky.actor.profile/self") }
}

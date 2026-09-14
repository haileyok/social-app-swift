import Foundation

/// Decides a user list's moderation state from its creator's account/profile
/// and the labels attached to the list itself.
public func decideUserList(_ subject: ListView, opts: ModerationOpts) -> ModerationDecision {
  var acc = ModerationDecision()
  let creator: ProfileViewBasic? = subject.creator
  if let creator {
    acc.setDid(creator.did)
    acc.setIsMe(creator.did == opts.userDid)
    if let labels = subject.labels, !labels.isEmpty {
      for label in labels {
        acc.addLabel(target: .content, label: label, opts: opts)
      }
    }
    return ModerationDecision.merge([acc, decideAccount(creator, opts: opts), decideProfile(creator, opts: opts)])
  }
  let creatorDid = atUriHostname(subject.uri)
  acc.setDid(creatorDid)
  acc.setIsMe(creatorDid == opts.userDid)
  if let labels = subject.labels, !labels.isEmpty {
    for label in labels {
      acc.addLabel(target: .content, label: label, opts: opts)
    }
  }
  return acc
}

/// Decides a feed generator's moderation state.
public func decideFeedGenerator(
  _ subject: FeedGeneratorView,
  opts: ModerationOpts
) -> ModerationDecision {
  var acc = ModerationDecision()
  acc.setDid(subject.creator.did)
  acc.setIsMe(subject.creator.did == opts.userDid)
  if let labels = subject.labels, !labels.isEmpty {
    for label in labels {
      acc.addLabel(target: .content, label: label, opts: opts)
    }
  }
  return ModerationDecision.merge([
    acc, decideAccount(subject.creator, opts: opts), decideProfile(subject.creator, opts: opts),
  ])
}

/// Decides a notification's moderation state from its author and labels.
public func decideNotification(
  _ subject: NotificationView,
  opts: ModerationOpts
) -> ModerationDecision {
  var acc = ModerationDecision()
  acc.setDid(subject.author.did)
  acc.setIsMe(subject.author.did == opts.userDid)
  if let labels = subject.labels, !labels.isEmpty {
    for label in labels {
      acc.addLabel(target: .content, label: label, opts: opts)
    }
  }
  return ModerationDecision.merge([
    acc, decideAccount(subject.author, opts: opts), decideProfile(subject.author, opts: opts),
  ])
}

/// Decides a status view's moderation state from its labels and its account.
public func decideStatus(_ subject: StatusView, opts: ModerationOpts) -> ModerationDecision {
  var acc = ModerationDecision()
  acc.setDid(subject.did)
  acc.setIsMe(subject.did == opts.userDid)
  if let labels = subject.status?.labels, !labels.isEmpty {
    for label in labels {
      acc.addLabel(target: .content, label: label, opts: opts)
    }
  }
  return ModerationDecision.merge([
    acc, decideAccount(subject, opts: opts), decideProfile(profileView(subject), opts: opts),
  ])
}

/// Builds a minimal profile from a status view so the shared account/profile
/// deciders can be reused. Status views carry no labels or viewer state of
/// their own in practice, so those fields are left empty.
private func profileView(_ subject: StatusView) -> ProfileViewBasic {
  ProfileViewBasic(did: subject.did, handle: subject.did)
}

/// Extracts the repository (actor) DID from an `at://` URI.
func atUriHostname(_ uri: String) -> String {
  guard uri.hasPrefix("at://") else { return "" }
  let rest = uri.dropFirst("at://".count)
  return String(rest.prefix { $0 != "/" })
}

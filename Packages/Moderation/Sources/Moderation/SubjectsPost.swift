import Foundation

/// Decides a post's moderation state.
///
/// The embed decision contributes a *downgraded* set of causes: labels and
/// viewer state on a quoted post should filter it out of a list but must not
/// blur or alert on the quoting post itself.
public func decidePost(_ subject: PostView, opts: ModerationOpts) -> ModerationDecision {
  ModerationDecision.merge([
    decideSubject(subject, opts: opts),
    decideEmbed(subject.embed, opts: opts)?.downgraded(),
    decideAccount(subject.author, opts: opts),
    decideProfile(subject.author, opts: opts),
  ])
}

private func decideSubject(_ subject: PostView, opts: ModerationOpts) -> ModerationDecision {
  var acc = ModerationDecision()
  acc.setDid(subject.author.did)
  acc.setIsMe(subject.author.did == opts.userDid)
  if let labels = subject.labels, !labels.isEmpty {
    for label in labels {
      acc.addLabel(target: .content, label: label, opts: opts)
    }
  }
  acc.addHidden(checkHiddenPost(subject, hiddenPosts: opts.prefs.hiddenPosts))
  if !acc.isMe {
    acc.addMutedWord(matchAllMuteWords(subject, mutedWords: opts.prefs.mutedWords))
  }
  return acc
}

private func decideEmbed(_ embed: PostViewEmbed?, opts: ModerationOpts) -> ModerationDecision? {
  guard let embed else { return nil }
  switch embed {
  case .record(let record):
    if let viewRecord = record.record?.viewRecord {
      // quote post
      return decideQuotedPost(viewRecord, opts: opts)
    }
    if let blocked = record.record?.viewBlocked {
      // blocked quote post
      return decideBlockedQuotedPost(blocked, opts: opts)
    }
  case .recordWithMedia(let media):
    if let viewRecord = media.record?.record?.viewRecord {
      // quoted post with media
      return decideQuotedPost(viewRecord, opts: opts)
    }
    if let blocked = media.record?.record?.viewBlocked {
      // blocked quoted post with media
      return decideBlockedQuotedPost(blocked, opts: opts)
    }
  default:
    break
  }
  return nil
}

private func decideQuotedPost(
  _ subject: EmbedViewRecord,
  opts: ModerationOpts
) -> ModerationDecision? {
  guard let author = subject.author else { return nil }
  var acc = ModerationDecision()
  acc.setDid(author.did)
  acc.setIsMe(author.did == opts.userDid)
  if let labels = subject.labels, !labels.isEmpty {
    for label in labels {
      acc.addLabel(target: .content, label: label, opts: opts)
    }
  }
  return ModerationDecision.merge([acc, decideAccount(author, opts: opts), decideProfile(author, opts: opts)])
}

private func decideBlockedQuotedPost(
  _ subject: EmbedViewBlocked,
  opts: ModerationOpts
) -> ModerationDecision? {
  guard let author = subject.author else { return nil }
  var acc = ModerationDecision()
  acc.setDid(author.did)
  acc.setIsMe(author.did == opts.userDid)
  if author.viewer?.muted == true {
    if let list = author.viewer?.mutedByList {
      acc.addMutedByList(list)
    } else {
      acc.addMuted(author.viewer?.muted)
    }
  }
  if author.viewer?.blocking?.isEmpty == false {
    if let list = author.viewer?.blockingByList {
      acc.addBlockingByList(list)
    } else {
      acc.addBlocking(author.viewer?.blocking != nil)
    }
  }
  acc.addBlockedBy(author.viewer?.blockedBy)
  return acc
}

private func checkHiddenPost(_ subject: PostView, hiddenPosts: [String]) -> Bool {
  if hiddenPosts.isEmpty { return false }
  if hiddenPosts.contains(subject.uri) { return true }
  guard let embed = subject.embed else { return false }
  if case .record(let record) = embed,
    let viewRecord = record.record?.viewRecord,
    let uri = viewRecord.uri,
    hiddenPosts.contains(uri) {
    return true
  }
  if case .recordWithMedia(let media) = embed,
    let viewRecord = media.record?.record?.viewRecord,
    let uri = viewRecord.uri,
    hiddenPosts.contains(uri) {
    return true
  }
  return false
}

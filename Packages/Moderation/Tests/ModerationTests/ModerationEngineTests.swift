import Foundation
import Testing

@testable import Moderation

/// Focused tests for engine semantics the golden corpus exercises only
/// indirectly.
@Suite struct ModerationEngineTests {
  static let me = "did:plc:me"
  static let author = "did:plc:author"
  static let labeler = "did:plc:labeler"

  /// An options value with the labeler configured, as the engine requires.
  static func opts(
    adultContentEnabled: Bool = true,
    labels: [String: LabelPreference] = [:],
    labelers: [LabelerPrefs]? = nil,
    mutedWords: [MutedWord] = [],
    hiddenPosts: [String] = [],
    userDid: String = me
  ) -> ModerationOpts {
    ModerationOpts(
      userDid: userDid,
      prefs: ModerationPrefs(
        adultContentEnabled: adultContentEnabled,
        labels: labels,
        labelers: labelers ?? [LabelerPrefs(did: labeler)],
        mutedWords: mutedWords,
        hiddenPosts: hiddenPosts
      )
    )
  }

  static func authorProfile(
    did: String = author,
    viewer: ActorViewerState? = nil,
    labels: [Label]? = nil
  ) -> ProfileViewBasic {
    ProfileViewBasic(
      did: did,
      handle: "author.test",
      displayName: "Author",
      viewer: viewer,
      labels: labels
    )
  }

  static func post(
    text: String = "hello",
    author: ProfileViewBasic? = nil,
    labels: [Label]? = nil,
    embed: PostViewEmbed? = nil
  ) -> PostView {
    PostView(
      uri: "at://\(author?.did ?? Self.author)/app.bsky.feed.post/1",
      cid: "bafy",
      author: author ?? authorProfile(),
      record: FeedPostRecord(text: text, langs: ["en"]),
      embed: embed,
      labels: labels
    )
  }

  static func contentLabel(_ value: String, src: String = labeler) -> Label {
    Label(
      ver: 1,
      src: src,
      uri: "at://\(Self.author)/app.bsky.feed.post/1",
      val: value,
      cts: "2024-01-01T00:00:00.000Z"
    )
  }

  // MARK: merge

  @Test func mergeTakesIdentityFromFirstDecisionAndConcatenatesCauses() {
    var first = ModerationDecision()
    first.setDid("did:plc:first")
    first.setIsMe(true)
    first.addBlockedBy(true)

    var second = ModerationDecision()
    second.setDid("did:plc:second")
    second.addMuted(true)

    var third = ModerationDecision()
    third.setDid("did:plc:third")
    third.addHidden(true)

    let merged = ModerationDecision.merge([first, second, third])
    #expect(merged.did == "did:plc:first")
    #expect(merged.isMe)
    #expect(merged.causes.map(\.type) == [.blockedBy, .muted, .hidden])
  }

  @Test func mergeSkipsNilDecisions() {
    var only = ModerationDecision()
    only.setDid("did:plc:only")
    only.addMuted(true)
    let merged = ModerationDecision.merge([nil, only, nil])
    #expect(merged.did == "did:plc:only")
    #expect(merged.causes.count == 1)
  }

  @Test func mergeOfNothingIsAnEmptyDecision() {
    let merged = ModerationDecision.merge([nil])
    #expect(merged.did.isEmpty)
    #expect(!merged.isMe)
    #expect(merged.causes.isEmpty)
  }

  // MARK: downgrade

  @Test func downgradeMarksEveryCauseAndSuppressesBlursButKeepsFilters() {
    let opts = Self.opts()
    let subject = Self.post(
      author: Self.authorProfile(viewer: ActorViewerState(blockedBy: true))
    )
    var decision = moderatePost(subject, opts: opts)

    let before = decision.ui(.contentView)
    #expect(before.blur)
    #expect(before.noOverride)

    decision.downgrade()
    #expect(decision.causes.allSatisfy { $0.downgraded == true })
    // blur/alert/inform are suppressed, but the list filter survives
    let after = decision.ui(.contentView)
    #expect(!after.blur)
    #expect(!after.noOverride)
    let listUI = decision.ui(.contentList)
    #expect(listUI.filter)
    #expect(!listUI.blur)
    // blocked stays true: the block cause still exists
    #expect(decision.blocked)
  }

  // MARK: label preference ladder

  @Test func labelerScopedPreferenceBeatsGlobalPreference() {
    let opts = Self.opts(
      labels: ["porn": .warn],
      labelers: [LabelerPrefs(did: Self.labeler, labels: ["porn": .hide])]
    )
    let decision = moderatePost(Self.post(labels: [Self.contentLabel("porn")]), opts: opts)
    let cause = try! #require(decision.labelCauses.first)
    #expect(cause.setting == .hide)
    // hide upgrades the priority from 7 (medium behavior) to 2 (setting)
    #expect(cause.priority == 2)
  }

  @Test func globalPreferenceBeatsDefinitionDefault() {
    let opts = Self.opts(labels: ["porn": .warn])
    let decision = moderatePost(Self.post(labels: [Self.contentLabel("porn")]), opts: opts)
    #expect(decision.labelCauses.first?.setting == .warn)
  }

  @Test func definitionDefaultAppliesWithoutAnyViewerPreference() {
    // `gore` defaults to `warn`; `porn` defaults to `hide`.
    let gore = moderatePost(Self.post(labels: [Self.contentLabel("gore")]), opts: Self.opts())
    #expect(gore.labelCauses.first?.setting == .warn)
    let porn = moderatePost(Self.post(labels: [Self.contentLabel("porn")]), opts: Self.opts())
    #expect(porn.labelCauses.first?.setting == .hide)
  }

  @Test func selfLabelsUseTheDefinitionDefaultNotALabelerScopedPref() {
    // src == subject did -> isSelf, so the labeler ladder does not apply.
    let opts = Self.opts(
      labels: ["porn": .warn],
      labelers: [LabelerPrefs(did: Self.author, labels: ["porn": .hide])]
    )
    let decision = moderatePost(
      Self.post(labels: [Self.contentLabel("porn", src: Self.author)]),
      opts: opts
    )
    let cause = try! #require(decision.labelCauses.first)
    #expect(cause.source == .user)
    #expect(cause.setting == .warn)
  }

  @Test func ignorePreferenceProducesNoCause() {
    let opts = Self.opts(labels: ["porn": .ignore])
    let decision = moderatePost(Self.post(labels: [Self.contentLabel("porn")]), opts: opts)
    #expect(decision.causes.isEmpty)
  }

  // MARK: unconfigured labeler

  @Test func labelsFromAnUnconfiguredLabelerAreSkipped() {
    let opts = Self.opts(labelers: [])
    let decision = moderatePost(Self.post(labels: [Self.contentLabel("porn")]), opts: opts)
    #expect(decision.causes.isEmpty)
  }

  @Test func labelsFromTheOnlyConfiguredLabelerApply() {
    let decision = moderatePost(
      Self.post(labels: [Self.contentLabel("porn")]),
      opts: Self.opts()
    )
    #expect(decision.labelCauses.count == 1)
  }

  // MARK: adult content forcing

  @Test func adultContentDisabledForcesHideAndNoOverrideOnAdultLabels() {
    let opts = Self.opts(adultContentEnabled: false, labels: ["porn": .warn])
    let decision = moderatePost(Self.post(labels: [Self.contentLabel("porn")]), opts: opts)
    let cause = try! #require(decision.labelCauses.first)
    #expect(cause.setting == .hide)
    #expect(cause.priority == 1)
    #expect(cause.noOverride == true)
    let media = decision.ui(.contentMedia)
    #expect(media.blur)
    #expect(media.noOverride)
  }

  @Test func adultContentDisabledDoesNotAffectNonAdultLabels() {
    // `nudity` has no `adult` flag, so its ignore default still applies.
    let opts = Self.opts(adultContentEnabled: false)
    let decision = moderatePost(Self.post(labels: [Self.contentLabel("nudity")]), opts: opts)
    #expect(decision.causes.isEmpty)
  }

  // MARK: filterAccountLabels

  @Test func filterAccountLabelsDropsSelfProfileLabelsExceptNoUnauthenticated() {
    let accountLevel = Label(ver: 1, src: Self.labeler, uri: Self.author, val: "porn")
    let selfProfile = Label(
      ver: 1,
      src: Self.labeler,
      uri: "at://\(Self.author)/app.bsky.actor.profile/self",
      val: "porn"
    )
    let selfProfileNoUnauthed = Label(
      ver: 1,
      src: Self.labeler,
      uri: "at://\(Self.author)/app.bsky.actor.profile/self",
      val: "!no-unauthenticated"
    )
    let kept = filterAccountLabels([accountLevel, selfProfile, selfProfileNoUnauthed])
    #expect(kept.map(\.val) == ["porn", "!no-unauthenticated"])
    #expect(kept.count == 2)
  }

  @Test func filterAccountLabelsHandlesNil() {
    #expect(filterAccountLabels(nil).isEmpty)
  }

  @Test func profileLabelsKeepOnlyBecauseSelfProfileLabels() {
    let selfProfile = Label(
      ver: 1,
      src: Self.labeler,
      uri: "at://\(Self.author)/app.bsky.actor.profile/self",
      val: "porn"
    )
    let accountLevel = Label(ver: 1, src: Self.labeler, uri: Self.author, val: "porn")
    #expect(filterProfileLabels([selfProfile, accountLevel]).count == 1)
    #expect(filterProfileLabels(nil).isEmpty)
  }

  @Test func unauthenticatedLabelsAreSkippedForAnAuthenticatedViewer() {
    let opts = Self.opts()
    let decision = moderateProfile(
      Self.authorProfile(labels: [Self.contentLabel("!no-unauthenticated")]),
      opts: opts
    )
    #expect(decision.causes.isEmpty)
  }

  // MARK: blocks, mutes, and list sources

  @Test func mutedByListUsesTheListAsTheCauseSource() {
    let list = ListViewBasic(
      uri: "at://\(Self.me)/app.bsky.graph.list/1",
      name: "noisy"
    )
    let subject = Self.post(
      author: Self.authorProfile(viewer: ActorViewerState(muted: true, mutedByList: list))
    )
    let decision = moderatePost(subject, opts: Self.opts())
    let cause = try! #require(decision.muteCause)
    #expect(cause.source == .list(list))
    #expect(decision.muted)
  }

  @Test func blockingByListIsABlockCauseWithAListSource() {
    let list = ListViewBasic(
      uri: "at://\(Self.me)/app.bsky.graph.list/2",
      name: "bad"
    )
    let subject = Self.post(
      author: Self.authorProfile(
        viewer: ActorViewerState(
          blocking: "at://\(Self.me)/app.bsky.graph.list/2",
          blockingByList: list
        )
      )
    )
    let decision = moderatePost(subject, opts: Self.opts())
    let cause = try! #require(decision.blockCause)
    #expect(cause.type == .blocking)
    #expect(cause.source == .list(list))
  }

  // MARK: mute-word surfaces beyond the post text

  static let spoiler = MutedWord(
    value: "spoiler",
    targets: [.content],
    actorTarget: .all
  )

  static func optsWithMutedWords(_ words: [MutedWord]) -> ModerationOpts {
    opts(mutedWords: words)
  }

  /// A post whose record carries a raw (non-view) embed, which is where the
  /// engine reads image and gallery alt text from.
  static func recordEmbedPost(embed: RecordEmbed) -> PostView {
    PostView(
      uri: "at://\(author)/app.bsky.feed.post/1",
      cid: "bafy",
      author: authorProfile(),
      record: FeedPostRecord(text: "no keyword here", langs: ["en"], embed: embed)
    )
  }

  static func imagePost(embed: PostViewEmbed) -> PostView {
    PostView(
      uri: "at://\(author)/app.bsky.feed.post/1",
      cid: "bafy",
      author: authorProfile(),
      record: FeedPostRecord(text: "no keyword here", langs: ["en"], embed: nil),
      embed: embed
    )
  }

  @Test func muteWordMatchesImageAltText() {
    let subject = Self.recordEmbedPost(embed: .images([EmbedImage(alt: "spoiler alert")]))
    let decision = moderatePost(subject, opts: Self.optsWithMutedWords([Self.spoiler]))
    #expect(decision.causes.map(\.type) == [.muteWord])
  }

  @Test func muteWordMatchesGalleryAltText() {
    let subject = Self.recordEmbedPost(
      embed: .gallery([.image(EmbedImage(alt: "spoiler ahead"))])
    )
    let decision = moderatePost(subject, opts: Self.optsWithMutedWords([Self.spoiler]))
    #expect(decision.causes.map(\.type) == [.muteWord])
  }

  @Test func muteWordMatchesLinkCardTitleAndDescription() {
    let titleOnly = Self.imagePost(
      embed: .external(EmbedExternal(title: "spoiler", description: ""))
    )
    #expect(
      moderatePost(titleOnly, opts: Self.optsWithMutedWords([Self.spoiler])).causes.map(\.type)
        == [.muteWord]
    )
    let descriptionOnly = Self.imagePost(
      embed: .external(EmbedExternal(title: "", description: "a spoiler"))
    )
    #expect(
      moderatePost(descriptionOnly, opts: Self.optsWithMutedWords([Self.spoiler])).causes.map(\.type)
        == [.muteWord]
    )
  }

  @Test func muteWordMatchesQuotedPostText() {
    let quoted = EmbedViewRecord(
      uri: "at://\(Self.author)/app.bsky.feed.post/2",
      author: Self.authorProfile(),
      value: FeedPostRecord(text: "spoiler inside", langs: ["en"])
    )
    let subject = Self.imagePost(embed: .record(EmbedRecordView(record: .viewRecord(quoted))))
    let decision = moderatePost(subject, opts: Self.optsWithMutedWords([Self.spoiler]))
    #expect(decision.causes.map(\.type) == [.muteWord])
  }

  @Test func excludeFollowingMutedWordUsesTheQuotedPostAuthor() {
    // The outer author is not followed, but the quoted author is. With
    // exclude-following the quoted text must therefore not match, which only
    // holds if the quoted post's author (not the outer one) is consulted.
    let quoted = EmbedViewRecord(
      uri: "at://\(Self.author)/app.bsky.feed.post/2",
      author: Self.authorProfile(viewer: ActorViewerState(following: "at://\(Self.me)/f/1")),
      value: FeedPostRecord(text: "spoiler inside", langs: ["en"])
    )
    var outer = Self.imagePost(embed: .record(EmbedRecordView(record: .viewRecord(quoted))))
    outer.author = Self.authorProfile()
    let excludeFollowing = MutedWord(
      value: "spoiler",
      targets: [.content],
      actorTarget: .excludeFollowing
    )
    let decision = moderatePost(outer, opts: Self.optsWithMutedWords([excludeFollowing]))
    #expect(decision.causes.isEmpty)
  }

  @Test func quotedPostWithMediaMatchesMediaAltText() {
    let quoted = EmbedViewRecord(
      uri: "at://\(Self.author)/app.bsky.feed.post/2",
      author: Self.authorProfile(),
      value: FeedPostRecord(text: "no keyword here", langs: ["en"])
    )
    let subject = Self.imagePost(
      embed: .recordWithMedia(
        EmbedRecordWithMediaView(
          record: EmbedRecordView(record: .viewRecord(quoted)),
          media: .images([EmbedImage(alt: "spoiler in media")])
        )
      )
    )
    let decision = moderatePost(subject, opts: Self.optsWithMutedWords([Self.spoiler]))
    #expect(decision.causes.map(\.type) == [.muteWord])
  }

  @Test func hiddenPostMatchesOnlyItsOwnUriByDefault() {
    let subject = Self.post()
    let decision = moderatePost(
      subject,
      opts: Self.opts(hiddenPosts: ["at://did:plc:other/app.bsky.feed.post/9"])
    )
    #expect(decision.causes.isEmpty)
  }
}

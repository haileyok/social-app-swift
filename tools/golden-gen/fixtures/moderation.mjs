// Moderation golden fixtures.
//
// Each case is run through the REAL TypeScript engine (@bsky/sdk@1.1.0,
// exactly the version the RN social-app pins) by generate.mjs, which emits
// both the serialized input and the engine's decision projection into
// Packages/TestSupport/Fixtures/Golden/moderation.json. The Swift Moderation
// port must reproduce the outputs from the inputs.
//
// Engine contract notes (learned from dist/moderation/decision.js addLabel):
//  - a label whose src is NOT the subject's own did MUST have its labeler
//    configured in opts.prefs.labelers, otherwise the engine ignores it;
//  - labeler-scoped settings live in prefs.labelers[].labels (a map of
//    label value -> preference), custom label values are defined via
//    opts.labelDefs[labelerDid] (InterpretedLabelValueDefinition[]);
//  - all ids/timestamps are fixed here; never use Date.now()/randomness.

const mockMod = await import(new URL('../node_modules/@bsky/sdk/dist/moderation/mock.js', import.meta.url).href)
const pubMod = await import('@bsky/sdk/moderation')
const mockBuilders = mockMod.mock
const interpret = pubMod.interpretLabelValueDefinition

const ME = 'did:plc:memoderator'
const AUTHOR = 'did:plc:author123'
const AUTHOR_HANDLE = 'author.test'
const OTHER = 'did:plc:other456'
const LABELER = 'did:plc:labeler789'
const POST_URI = `at://${AUTHOR}/app.bsky.feed.post/3kttw`

/** Fixed-timestamp content label on the post's own uri. */
function contentLabel(val, src = LABELER, uri = POST_URI) {
  return { ver: 1, src, uri, val, cts: '2024-01-01T00:00:00.000Z' }
}

/** Fixed-timestamp account label (uri = the account's did). */
function accountLabel(val, src = LABELER, did = AUTHOR) {
  return { ver: 1, src, uri: did, val, cts: '2024-01-01T00:00:00.000Z' }
}

/** ProfileViewBasic with our fixed did (mock's own did is did:web:<handle>). */
function author({ viewer, labels, did = AUTHOR, displayName = 'Author' } = {}) {
  return {
    ...mockBuilders.profileViewBasic({ handle: AUTHOR_HANDLE, displayName, viewer, labels }),
    did,
  }
}

/** PostView with our fixed uri (mock's own is .../fake). */
function postView({ text, author: a, labels, viewer, embed } = {}) {
  const pv = mockBuilders.postView({
    record: mockBuilders.post({ text }),
    author: a ?? author({ viewer }),
    labels,
    embed,
  })
  return { ...pv, uri: POST_URI }
}

/** prefs with LABELER configured (required for non-self labels to apply). */
function withLabeler(prefs = {}) {
  return { ...prefs, labelers: [{ did: LABELER, labels: {} }, ...(prefs.labelers ?? [])] }
}

export const cases = [
  {
    name: 'clean-post',
    fn: 'moderatePost',
    subject: postView({ text: 'just a normal post' }),
    opts: { userDid: ME, prefs: { adultContentEnabled: true } },
  },
  {
    name: 'content-label-porn-hide',
    fn: 'moderatePost',
    subject: postView({ text: 'explicit post', labels: [contentLabel('porn')] }),
    opts: {
      userDid: ME,
      prefs: withLabeler({ adultContentEnabled: true, labels: { porn: 'hide' } }),
    },
  },
  {
    name: 'content-label-porn-warn',
    fn: 'moderatePost',
    subject: postView({ text: 'explicit post', labels: [contentLabel('porn')] }),
    opts: {
      userDid: ME,
      prefs: withLabeler({ adultContentEnabled: true, labels: { porn: 'warn' } }),
    },
  },
  {
    name: 'content-label-porn-ignore',
    fn: 'moderatePost',
    subject: postView({ text: 'explicit post', labels: [contentLabel('porn')] }),
    opts: {
      userDid: ME,
      prefs: withLabeler({ adultContentEnabled: true, labels: { porn: 'ignore' } }),
    },
  },
  {
    name: 'adult-content-disabled-forces-hide',
    fn: 'moderatePost',
    subject: postView({ text: 'explicit post', labels: [contentLabel('porn')] }),
    opts: {
      userDid: ME,
      prefs: withLabeler({ adultContentEnabled: false, labels: { porn: 'warn' } }),
    },
  },
  {
    name: 'labeler-not-configured-label-ignored',
    fn: 'moderatePost',
    subject: postView({ text: 'post with label from unconfigured labeler', labels: [contentLabel('gore')] }),
    opts: {
      userDid: ME,
      prefs: { adultContentEnabled: true, labelers: [] },
    },
  },
  {
    name: 'account-label-porn-blurs-profile-surfaces',
    fn: 'moderateProfile',
    subject: author({ labels: [accountLabel('porn')] }),
    opts: {
      userDid: ME,
      prefs: withLabeler({ adultContentEnabled: true, labels: { porn: 'hide' } }),
    },
  },
  {
    name: 'muted-by-viewer',
    fn: 'moderatePost',
    subject: postView({
      text: 'muted author post',
      viewer: mockBuilders.actorViewerState({ muted: true }),
    }),
    opts: { userDid: ME, prefs: { adultContentEnabled: true } },
  },
  {
    name: 'blocking-by-viewer',
    fn: 'moderatePost',
    subject: postView({
      text: 'blocked author post',
      author: author({ viewer: mockBuilders.actorViewerState({ blocking: `at://${ME}/app.bsky.graph.block/3kabc` }) }),
    }),
    opts: { userDid: ME, prefs: { adultContentEnabled: true } },
  },
  {
    name: 'blocked-by-author',
    fn: 'moderatePost',
    subject: postView({
      text: 'post from someone who blocked me',
      author: author({ viewer: mockBuilders.actorViewerState({ blockedBy: true }) }),
    }),
    opts: { userDid: ME, prefs: { adultContentEnabled: true } },
  },
  {
    name: 'muted-by-list',
    fn: 'moderatePost',
    subject: postView({
      text: 'list-muted author post',
      author: author({
        viewer: mockBuilders.actorViewerState({
          muted: true,
          mutedByList: { uri: `at://${ME}/app.bsky.graph.list/3klst`, name: 'noisy', blocked: false },
        }),
      }),
    }),
    opts: { userDid: ME, prefs: { adultContentEnabled: true } },
  },
  {
    name: 'blocking-by-list',
    fn: 'moderatePost',
    subject: postView({
      text: 'list-blocked author post',
      author: author({
        viewer: mockBuilders.actorViewerState({
          blocking: `at://${ME}/app.bsky.graph.list/3klst2`,
          blockingByList: { uri: `at://${ME}/app.bsky.graph.list/3klst2`, name: 'bad', blocked: true },
        }),
      }),
    }),
    opts: { userDid: ME, prefs: { adultContentEnabled: true } },
  },
  {
    name: 'muted-word-content-match',
    fn: 'moderatePost',
    subject: postView({ text: 'a post about spoiler definitely' }),
    opts: {
      userDid: ME,
      prefs: {
        adultContentEnabled: true,
        mutedWords: [{ value: 'spoiler', targets: ['content'], actorTarget: 'all' }],
      },
    },
  },
  {
    name: 'quote-post-muted-word-in-embed',
    fn: 'moderatePost',
    subject: postView({
      text: 'look at this quote',
      embed: mockBuilders.embedRecordView({
        record: mockBuilders.post({ text: 'big spoiler inside the quote' }),
        author: author(),
      }),
    }),
    opts: {
      userDid: ME,
      prefs: {
        adultContentEnabled: true,
        mutedWords: [{ value: 'spoiler', targets: ['content'], actorTarget: 'all' }],
      },
    },
  },
  {
    name: 'muted-word-no-match',
    fn: 'moderatePost',
    subject: postView({ text: 'a post about nothing in particular' }),
    opts: {
      userDid: ME,
      prefs: {
        adultContentEnabled: true,
        mutedWords: [{ value: 'spoiler', targets: ['content'], actorTarget: 'all' }],
      },
    },
  },
  {
    name: 'muted-word-exclude-following-follows-so-no-match',
    fn: 'moderatePost',
    subject: postView({
      text: 'spoiler talk from a friend',
      author: author({ viewer: mockBuilders.actorViewerState({ following: `at://${ME}/app.bsky.graph.follow/3kfol` }) }),
    }),
    opts: {
      userDid: ME,
      prefs: {
        adultContentEnabled: true,
        mutedWords: [{ value: 'spoiler', targets: ['content'], actorTarget: 'exclude-following' }],
      },
    },
  },
  {
    name: 'hidden-post-filtered',
    fn: 'moderatePost',
    subject: postView({ text: 'post I hid' }),
    opts: {
      userDid: ME,
      prefs: { adultContentEnabled: true, hiddenPosts: [POST_URI] },
    },
  },
  {
    name: 'label-gore-default-hide',
    fn: 'moderatePost',
    subject: postView({ text: 'gory post', labels: [contentLabel('gore')] }),
    opts: { userDid: ME, prefs: withLabeler({ adultContentEnabled: true }) },
  },
  {
    name: 'unknown-label-value-ignored',
    fn: 'moderatePost',
    subject: postView({ text: 'weird label', labels: [contentLabel('some-unknown-val')] }),
    opts: { userDid: ME, prefs: withLabeler({ adultContentEnabled: true }) },
  },
  {
    name: 'custom-labeler-definition',
    fn: 'moderatePost',
    subject: postView({ text: 'custom labeled post', labels: [contentLabel('self-ghi')] }),
    opts: {
      userDid: ME,
      prefs: withLabeler({ adultContentEnabled: true }),
      labelDefs: {
        [LABELER]: [
          interpret(
            {
              identifier: 'self-ghi',
              severity: 'inform',
              blurs: 'content',
              defaultSetting: 'warn',
              adult: false,
              noOverride: false,
            },
            LABELER
          ),
        ],
      },
    },
  },
  {
    name: 'custom-labeler-labeler-scoped-setting',
    fn: 'moderatePost',
    subject: postView({ text: 'custom labeled post, scoped to hide', labels: [contentLabel('self-ghi')] }),
    opts: {
      userDid: ME,
      prefs: {
        adultContentEnabled: true,
        labelers: [{ did: LABELER, labels: { 'self-ghi': 'hide' } }],
      },
      labelDefs: {
        [LABELER]: [
          interpret(
            {
              identifier: 'self-ghi',
              severity: 'inform',
              blurs: 'content',
              defaultSetting: 'warn',
              adult: false,
              noOverride: false,
            },
            LABELER
          ),
        ],
      },
    },
  },
  {
    name: 'content-self-label-by-author',
    fn: 'moderatePost',
    subject: postView({ text: 'self labeled post', labels: [contentLabel('porn', AUTHOR)] }),
    opts: {
      userDid: ME,
      prefs: { adultContentEnabled: true, labels: { porn: 'hide' } },
    },
  },
  {
    name: 'is-me-own-account-label',
    fn: 'moderatePost',
    subject: postView({
      text: 'my own post',
      author: author({ did: ME, labels: [accountLabel('porn', LABELER, ME)] }),
    }),
    opts: {
      userDid: ME,
      prefs: withLabeler({ adultContentEnabled: true, labels: { porn: 'hide' } }),
    },
  },
  {
    name: 'multiple-causes-priority-order',
    fn: 'moderatePost',
    subject: postView({
      text: 'spoiler: gore content',
      labels: [contentLabel('gore')],
      author: author({ viewer: mockBuilders.actorViewerState({ muted: true, blockedBy: true }) }),
    }),
    opts: {
      userDid: ME,
      prefs: withLabeler({
        adultContentEnabled: true,
        mutedWords: [{ value: 'spoiler', targets: ['content'], actorTarget: 'all' }],
        hiddenPosts: [POST_URI],
      }),
    },
  },
  {
    name: 'profile-with-forced-hide-label',
    fn: 'moderateProfile',
    subject: author({ labels: [accountLabel('!hide')] }),
    opts: { userDid: ME, prefs: withLabeler({ adultContentEnabled: true }) },
  },
  {
    name: 'user-list-with-label',
    fn: 'moderateUserList',
    subject: {
      uri: `at://${OTHER}/app.bsky.graph.list/3klstx`,
      cid: 'bafylst',
      name: 'A List',
      purpose: 'app.bsky.graph.defs.modlist',
      viewer: { muted: false, blocked: false },
      labels: [contentLabel('gore', LABELER, `at://${OTHER}/app.bsky.graph.list/3klstx`)],
    },
    opts: { userDid: ME, prefs: withLabeler({ adultContentEnabled: true }) },
  },
  {
    name: 'feed-generator-with-label',
    fn: 'moderateFeedGenerator',
    subject: {
      uri: `at://${OTHER}/app.bsky.feed.generator/myskyline`,
      cid: 'bafygen',
      did: `did:web:feed.${OTHER}`,
      displayName: 'My Skyline',
      creator: author({ viewer: mockBuilders.actorViewerState({}) }),
      viewer: { like: undefined },
      labels: [contentLabel('gore', LABELER, `at://${OTHER}/app.bsky.feed.generator/myskyline`)],
    },
    opts: { userDid: ME, prefs: withLabeler({ adultContentEnabled: true }) },
  },
]

// Extra: exercise ModerationDecision.downgrade() on the blocked-by case.
export const downgradeCase = {
  name: 'downgrade-softens-blur-to-inform',
  fn: 'moderatePost',
  subject: postView({
    text: 'post from someone who blocked me',
    author: author({ viewer: mockBuilders.actorViewerState({ blockedBy: true }) }),
  }),
  opts: { userDid: ME, prefs: { adultContentEnabled: true } },
  downgrade: true,
}

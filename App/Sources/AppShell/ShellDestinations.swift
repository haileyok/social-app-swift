import ATProtoClient
import ComposerLogic
import ComposerViews
import DesignSystem
import Foundation
import HomeFeedLogic
import HomeFeedViews
import Lexicons
import MessagesLogic
import MessagesViews
import Moderation
import PostThreadLogic
import PostThreadViews
import Preferences
import ProfileLogic
import ProfileViews
import QueryStore
import RichText
import SearchLogic
import SearchViews
import StarterPacksLogic
import StarterPacksViews
import SwiftUI
import UIComponents
import UIComponentsCore

/**
 Registers every ``ShellRouter/Route`` a tab's `NavigationStack` can push.

 Attached once per tab, directly under the stack's root content, so pushed
 screens can themselves push (a thread opens a profile, a profile opens a
 feed) through the same router.
 */
struct ShellDestinations: ViewModifier {
  @Environment(ShellRouter.self) private var router

  func body(content: Content) -> some View {
    content.navigationDestination(for: ShellRouter.Route.self) { route in
      ShellDestinationView(route: route)
    }
  }
}

/** Maps one route to its screen. */
struct ShellDestinationView: View {
  let route: ShellRouter.Route

  var body: some View {
    switch route {
    case .thread(let uri):
      ThreadRouteView(uri: uri)
    case .profile(let actor):
      ProfileRouteView(actor: actor)
    case .feed(let uri, let name):
      FeedRouteView(uri: uri, name: name)
    case .starterPack(let uri, let name):
      StarterPackRouteView(uri: uri, name: name)
    case .search(let query):
      SearchRouteView(query: query)
    case .conversation(let convoId):
      ConversationRouteView(convoId: convoId)
    }
  }
}

// MARK: - Thread

/**
 A pushed thread: fetches, flattens, renders.

 The RN screen hydrates through its query cache; here the fetch runs on entry
 (the skeleton stands in while it loads), because the pushed screen owns its
 lifecycle and has no cache entry to hydrate from until the shell shares the
 store with a thread query key.
 */
private struct ThreadRouteView: View {
  let uri: String

  @Environment(ShellRouter.self) private var router
  @State private var thread: FlattenedThread?
  @State private var failed = false
  @State private var replyTarget: ComposerReplyTarget?

  var body: some View {
    Group {
      if let thread {
        PostThreadScreen(
          thread: thread,
          onOpen: { router.open($0) },
          onReply: { content in replyTarget = makeReplyTarget(for: content) },
          onLike: { content in Task { await toggleLike(content) } },
          onRepost: { content in Task { await toggleRepost(content) } })
      } else if failed {
        RetryRow(message: "Could not load this post.", retry: { Task { await load() } })
      } else {
        ListSkeleton()
      }
    }
    .navigationTitle("Post")
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .sheet(item: $replyTarget) { target in
      if let clients = router.clients {
        LiveComposerSheet(
          clients: clients,
          replyTarget: target,
          onPublished: { await load() })
      }
    }
  }

  private func makeReplyTarget(for content: ThreadPostContent) -> ComposerReplyTarget {
    let parent = RecordReference(
      uri: content.post.uri.rawValue,
      cid: content.post.cid.rawValue)
    let root: RecordReference
    if let rootRef = content.record?.reply?.root {
      root = RecordReference(uri: rootRef.uri.rawValue, cid: rootRef.cid.rawValue)
    } else {
      root = parent
    }
    let handle = content.post.author.handle.rawValue
    return ComposerReplyTarget(
      parent: parent,
      root: root,
      display: ComposerReplyContext(
        displayName: content.post.author.displayName ?? handle,
        handle: handle,
        text: content.record?.text ?? ""))
  }

  private func toggleLike(_ content: ThreadPostContent) async {
    guard let clients = router.clients else { return }
    do {
      if let uri = content.post.viewer?.like?.rawValue, let rkey = recordKey(uri) {
        _ = try await clients.pds.deleteRecord(
          repo: clients.did, collection: "app.bsky.feed.like", rkey: rkey)
      } else {
        _ = try await clients.pds.createRecord(
          repo: clients.did,
          collection: "app.bsky.feed.like",
          record: ReactionRecord(
            type: "app.bsky.feed.like",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            subject: reactionSubject(content)))
      }
      await load()
    } catch {}
  }

  private func toggleRepost(_ content: ThreadPostContent) async {
    guard let clients = router.clients else { return }
    do {
      if let uri = content.post.viewer?.repost?.rawValue, let rkey = recordKey(uri) {
        _ = try await clients.pds.deleteRecord(
          repo: clients.did, collection: "app.bsky.feed.repost", rkey: rkey)
      } else {
        _ = try await clients.pds.createRecord(
          repo: clients.did,
          collection: "app.bsky.feed.repost",
          record: ReactionRecord(
            type: "app.bsky.feed.repost",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            subject: reactionSubject(content)))
      }
      await load()
    } catch {}
  }

  private struct ReactionRecord: Encodable, Sendable {
    let type: String
    let createdAt: String
    let subject: ReactionSubject

    enum CodingKeys: String, CodingKey {
      case type = "$type"
      case createdAt
      case subject
    }
  }

  private struct ReactionSubject: Encodable, Sendable {
    let uri: String
    let cid: String
  }

  private func reactionSubject(_ content: ThreadPostContent) -> ReactionSubject {
    ReactionSubject(uri: content.post.uri.rawValue, cid: content.post.cid.rawValue)
  }

  private func recordKey(_ uri: String) -> String? {
    uri.split(separator: "/").last.map(String.init)
  }

  private func load() async {
    guard let clients = router.clients else {
      failed = true
      return
    }
    do {
      let output = try await PostThreadFetcher(client: clients.appview)
        .callAsFunction(PostThreadParams(uri: uri))
      let fetchedAt = Int(Date().timeIntervalSince1970)
      let moderationOpts = ModerationOpts(userDid: clients.did, prefs: ModerationPrefs())
      let options = ThreadFlattenOptions(
        hasSession: true,
        moderationOpts: moderationOpts,
        fetchedAt: fetchedAt)
      thread = ThreadPresentationPipeline.prepare(
        ThreadTreeBuilder.build(output: output),
        order: .hotness,
        inputs: ThreadSortInputs(currentDid: clients.did, fetchedAt: fetchedAt),
        options: options)
      failed = false
    } catch {
      failed = true
    }
  }
}

// MARK: - Profile

/** A pushed profile for any actor (handles and DIDs both resolve). */
private struct ProfileRouteView: View {
  let actor: String

  @Environment(ShellRouter.self) private var router
  @State private var headerData: ProfileHeaderViewData?
  @State private var profileContent = ProfileContentLoader.loading
  @State private var failed = false
  @State private var showsEdit = false
  @State private var isMutatingFollow = false

  var body: some View {
    Group {
      if let headerData {
        ProfileScreen(
          headerData: headerData,
          content: profileContent,
          onOpen: { router.open($0) },
          onLikePost: { target in await react(.like, target: target) },
          onRepostPost: { target in await react(.repost, target: target) },
          onAction: handle)
      } else if failed {
        RetryRow(message: "Could not load this profile.", retry: { Task { await load() } })
      } else {
        ListSkeleton()
      }
    }
    .navigationTitle("Profile")
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .sheet(isPresented: $showsEdit) {
      if let clients = router.clients, let headerData,
        case .detailed(let profile) = headerData.unshadowedProfile
      {
        EditProfileSheet(
          profile: profile,
          onCancel: { showsEdit = false },
          onSave: { edit in
            showsEdit = false
            Task { try? await ProfileEditor.save(clients: clients, edit: edit) }
          })
      }
    }
  }

  private func handle(_ action: ProfileHeaderAction) {
    switch action {
    case .editProfile:
      showsEdit = true
    case .follow:
      Task { await setFollowing(true) }
    case .unfollow:
      Task { await setFollowing(false) }
    case .showFollowers, .showFollows:
      // List screens exist in ProfileViews; wiring them is the next seam.
      break
    default:
      break
    }
  }

  private func react(_ kind: ShellPostReaction, target: ProfilePostInteraction) async {
    guard let clients = router.clients else { return }
    let existingRecordURI: String?
    switch kind {
    case .like: existingRecordURI = target.likeURI
    case .repost: existingRecordURI = target.repostURI
    }
    try? await clients.toggleReaction(
      kind,
      uri: target.uri,
      cid: target.cid,
      existingRecordURI: existingRecordURI)
    await load()
  }

  /** Applies a follow intent to the viewer's PDS, then reloads server state. */
  private func setFollowing(_ shouldFollow: Bool) async {
    guard !isMutatingFollow, let clients = router.clients, let headerData,
      case .detailed(let profile) = headerData.unshadowedProfile
    else { return }

    isMutatingFollow = true
    defer { isMutatingFollow = false }
    do {
      let writer = ProfileClient(client: clients.pds)
      if shouldFollow {
        _ = try await writer.follow(
          subject: profile.did.rawValue, repo: clients.did, createdAt: Date())
      } else if let followURI = profile.viewer?.following?.rawValue {
        try await writer.unfollow(repo: clients.did, followUri: followURI)
      }
      await load()
    } catch {
      failed = false
    }
  }

  private func load() async {
    guard let clients = router.clients else {
      failed = true
      return
    }
    do {
      let profile = try await ProfileClient(client: clients.appview)
        .getProfile(actor: actor)
      headerData = ProfileHeaderViewData(
        profile: .detailed(profile),
        moderationOpts: ModerationOpts(userDid: clients.did, prefs: ModerationPrefs()),
        viewerDid: clients.did,
        hasSession: true)
      profileContent = await ProfileContentLoader.load(actor: actor, clients: clients)
      failed = false
    } catch {
      failed = true
    }
  }
}

// MARK: - Feed

/** A pushed custom feed (feed generator). */
private struct FeedRouteView: View {
  let uri: String
  let name: String

  @Environment(ShellRouter.self) private var router
  @State private var model: HomeFeedModel?

  var body: some View {
    Group {
      if let model {
        HomeFeedScreen(
          model: HomeFeedViewModel(model: model, presentation: .feeds, viewerDid: router.clients?.did),
          onOpenRichText: { router.open($0) },
          onOpenPost: { router.open(.thread(uri: $0)) },
          onReplyToPost: { router.open(.thread(uri: $0)) },
          onLikePost: { target in
            guard let clients = router.clients else { return }
            try? await clients.toggleReaction(
              .like,
              uri: target.uri,
              cid: target.cid,
              existingRecordURI: target.likeURI)
            try? await model.selectedQuery?.refresh()
          },
          onRepostPost: { target in
            guard let clients = router.clients else { return }
            try? await clients.toggleReaction(
              .repost,
              uri: target.uri,
              cid: target.cid,
              existingRecordURI: target.repostURI)
            try? await model.selectedQuery?.refresh()
          })
      } else {
        ListSkeleton()
      }
    }
    .navigationTitle(name)
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
  }

  private func load() async {
    guard let clients = router.clients else { return }
    model = await ShellFeedFactory.buildModel(clients: clients, pinnedOverride: [
      PinnedFeed(
        config: SavedFeedEntry(id: uri, type: .feed, value: uri, pinned: true),
        displayName: name)
    ])
  }
}

// MARK: - Starter pack

/** A pushed starter pack hydrated from the shared query store. */
private struct StarterPackRouteView: View {
  let uri: String
  let name: String

  @Environment(ShellRouter.self) private var router
  @State private var detail: StarterPackDetail?
  @State private var failed = false

  var body: some View {
    Group {
      if let detail {
        StarterPackScreen(detail: detail)
      } else if failed {
        RetryRow(message: "Could not load this starter pack.", retry: { Task { await load() } })
      } else {
        ListSkeleton()
      }
    }
    .navigationTitle(name)
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
  }

  private func load() async {
    guard let clients = router.clients else { return }
    failed = false
    do {
      let query = StarterPackQuery(
        store: clients.store,
        xrpc: LiveStarterPackXrpc(appview: clients.appview, pds: clients.pds),
        target: .uri(uri),
        scope: clients.did)
      guard let view = try await query.load(),
        StarterPackViewBuilder.isValid(view, viewerDID: clients.did)
      else {
        failed = true
        return
      }
      detail = StarterPackViewBuilder.detail(view, viewerDID: clients.did)
    } catch {
      failed = true
    }
  }
}

// MARK: - Search

/** A committed search: the topic or query typed into a trending row. */
private struct SearchRouteView: View {
  let query: String

  @Environment(ShellRouter.self) private var router
  @State private var viewModel: SearchViewModel?

  var body: some View {
    Group {
      if let viewModel {
        SearchScreen(
          viewModel: viewModel,
          onSelectProfile: { router.open(.profile(actor: $0.did.rawValue)) },
          onSelectFeed: { router.open(.feed(uri: $0.uri.rawValue, name: $0.displayName ?? "Feed")) },
          onSelectStarterPack: {
            router.open(.starterPack(uri: $0.uri.rawValue, name: $0.record.starterPackRecord?.name ?? "Starter Pack"))
          })
      } else {
        ListSkeleton()
      }
    }
    .navigationTitle(query)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      guard let clients = router.clients else { return }
      let vm = SearchViewModel(
        service: LiveSearchService(fetchers: SearchFetchers(client: clients.appview)))
      vm.type(query)
      viewModel = vm
      await vm.submit()
    }
  }
}

// MARK: - Conversation

/** A pushed chat conversation. */
private struct ConversationRouteView: View {
  let convoId: String

  @Environment(ShellRouter.self) private var router

  var body: some View {
    Group {
      if let clients = router.clients {
        ConversationScreen(
          viewModel: ConversationViewModel(
            model: ConversationModel(
              convoId: convoId,
              client: LiveChatXrpc(client: clients.chat),
              senderDid: clients.did),
            currentAccountDid: clients.did),
          showsBackButton: false)
      } else {
        ListSkeleton()
      }
    }
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: - Profile content

enum ProfileContentLoader {
  static let loading = ProfileScreenContent(
    states: Dictionary(
      uniqueKeysWithValues: ProfileTab.allCases.map { (section(for: $0), .loading) }))

  static func load(actor: String, clients: AppSessionClients) async -> ProfileScreenContent {
    let client = ProfileClient(client: clients.appview)
    var items: [ProfileTab: [FeedItemViewData]] = [:]
    var interactions: [ProfileTab: [ProfilePostInteraction]] = [:]
    var states: [ProfileSection: ListState] = [:]

    for tab in ProfileTab.allCases {
      do {
        let page = try await client.getAuthorFeedPage(
          actor: actor, tab: tab, cursor: nil, limit: tab.pageSize)
        let rows = page.items.map { item in
          let subject = LexiconModeration.subject(item.post)
          return feedItemViewData(
            subject,
            counts: FeedItemCounts(
              replyCount: item.post.replyCount,
              repostCount: item.post.repostCount,
              likeCount: item.post.likeCount),
            decision: moderatePost(
              subject,
              opts: ModerationOpts(userDid: clients.did, prefs: ModerationPrefs())),
            options: FeedItemRenderOptions(
              isReposted: item.post.viewer?.repost != nil,
              isLiked: item.post.viewer?.like != nil))
        }
        items[tab] = rows
        interactions[tab] = page.items.map { item in
          ProfilePostInteraction(
            uri: item.post.uri.rawValue,
            cid: item.post.cid.rawValue,
            likeURI: item.post.viewer?.like?.rawValue,
            repostURI: item.post.viewer?.repost?.rawValue)
        }
        states[section(for: tab)] = rows.isEmpty ? .empty : .content
      } catch {
        states[section(for: tab)] = .error(
          .init(title: "Could not load posts", message: error.localizedDescription))
      }
    }
    return ProfileScreenContent(feedItems: items, interactions: interactions, states: states)
  }

  private static func section(for tab: ProfileTab) -> ProfileSection {
    switch tab {
    case .posts: .posts
    case .replies: .replies
    case .media: .media
    case .videos: .videos
    case .likes: .likes
    }
  }
}

// MARK: - Feed model factory

/**
 Builds a live `HomeFeedModel` for a pinned-feed list.

 The Home tab resolves the account's pinned feeds; a pushed feed screen builds
 a single-feed model with the same fetcher/tuner wiring. One factory keeps the
 two constructions identical.
 */
enum ShellFeedFactory {
  /** Builds the model for `pinnedOverride`, or the account's pinned feeds when nil. */
  static func buildModel(clients: AppSessionClients, pinnedOverride: [PinnedFeed]? = nil) async -> HomeFeedModel? {
    var pinned = pinnedOverride ?? []

    if pinnedOverride == nil {
      let timeline = PinnedFeed(
        config: SavedFeedEntry(id: "home", type: .timeline, value: "following", pinned: true),
        displayName: "Following")
      pinned = [timeline]
      if let engine = try? PreferencesEngine(client: clients.pds),
        let preferences = try? await engine.getPreferences()
      {
        let resolver = PinnedFeedsResolver(
          store: clients.store, xrpc: LiveFeedXrpc(client: clients.appview),
          scope: clients.did, isAuthenticated: true)
        pinned.append(
          contentsOf: (try? await resolver.resolve(
            savedItems: SavedFeedReader.entries(from: preferences))) ?? [])
      }
      var seen = Set<FeedDescriptor>()
      pinned = pinned.filter { seen.insert($0.descriptor).inserted }
    }

    var fetchers: [String: any FeedPageFetcher] = [:]
    var tuners: [String: FeedTunerOptions] = [:]
    for feed in pinned {
      let key = feed.descriptor.description
      tuners[key] = FeedTunerOptions(userDid: clients.did)
      switch feed.descriptor {
      case .following:
        fetchers[key] = FollowingFeedFetcher(xrpc: LiveFeedXrpc(client: clients.appview))
      case .feedgen(let uri):
        fetchers[key] = CustomFeedFetcher(xrpc: LiveFeedXrpc(client: clients.appview), feedURI: uri)
      case .list(let uri):
        fetchers[key] = ListFeedFetcher(xrpc: LiveFeedXrpc(client: clients.appview), listURI: uri)
      }
    }

    return HomeFeedModel(
      store: clients.store,
      pinnedFeeds: pinned,
      fetchersByDescriptor: fetchers,
      tunerOptionsByDescriptor: tuners,
      scope: clients.did)
  }
}

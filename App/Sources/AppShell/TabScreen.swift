import ATProtoClient
import DesignSystem
import DesignTokens
import HomeFeedLogic
import HomeFeedViews
import Lexicons
import MessagesLogic
import MessagesViews
import NotificationsLogic
import NotificationsViews
import Preferences
import ProfileLogic
import ProfileViews
import QueryStore
import RichText
import SearchLogic
import SearchViews
import SwiftUI
import UIComponents
import UIComponentsCore

/**
 The screen a tab renders: the real feature screen when the shell has a
 session, the fixture surface the CI loops capture when it does not.

 Every tab in ``AppRootView``'s two `TabView` construction sites (the demo
 launch and the signed-in shell) goes through this view, which keeps the two
 paths from drifting: the demo path is *this* view with no clients, not a
 separate shell.

 ## The demo path

 A demo launch (screenshot loop, `-uiTestInitialTab`, UI tests) renders the
 same fixture surface each Views package exposes for capture
 (``HomeFeedDemoScreen`` via ``HomeFeedSurfaces/feedScreen(theme:)``,
 ``SearchFixtureSurfaces``, ``MessagesFixtureSurfaces``,
 ``NotificationsSurfaces``, ``ProfileFixtureSurface``). That is deliberate:
 those surfaces are deterministic, need no network, and are exactly what the
 CI screenshot loop and the smoke tests have always asserted. Wiring the real
 screens changed *who* decides what a tab renders - not what a demo launch
 renders.

 ## The live path

 A signed-in shell builds ``AppSessionClients`` once and every tab renders its
 production screen over the Logic packages:

 - Home: ``HomeFeedScreen`` over a live ``HomeFeedModel`` (the pinned timeline
   plus the resolved saved feeds, one query per descriptor).
 - Search: ``SearchScreen`` over a live ``SearchViewModel`` backed by
   `LiveSearchService`, with the Explore page assembled through
   ``SearchQueries``.
 - Messages: ``InboxScreen`` over a live ``InboxViewModel`` on the chat-proxied
   client.
 - Notifications: ``NotificationsScreen`` fed by a live
   ``NotificationFeedQuery`` (rows applied through ``NotificationsListModel``,
   the package's own select pass).
 - Profile: ``ProfileScreen`` fed by a live `getProfile` read (header only;
   the author feed is the documented seam below).

 ## Deferred seams

 Cross-tab navigation (post tap -> thread, search hit -> profile, conversation
 open) stays stubbed: the screens expose the closures
 (``HomeFeedScreen``'s `onOpenRichText`, ``InboxScreen``'s `onSelect`,
 ``NotificationsScreen``'s `onOpenPost`) but the shell has no router yet, and
 wiring one would mean either forking package internals or building the
 navigation layer, both out of scope for this change. Every closure below is
 the seam a later router plugs into; each does nothing today.
 */
struct TabScreen: View {
  private let tab: AppTab

  /**
   The session the account control reports, when the shell has one.

   The demo/screenshot path passes nil and renders fixture surfaces.
   */
  private let session: AppSession?

  /**
   The query plumbing for a signed-in shell: store, routed clients, scope.

   Nil on the demo path. Built once by the shell (see ``AppRootView``) and
   shared by every tab, so all features share one query cache.
   */
  private let clients: AppSessionClients?

  @Environment(ShellRouter.self) private var router

  init(tab: AppTab, session: AppSession?, clients: AppSessionClients? = nil) {
    self.tab = tab
    self.session = session
    self.clients = clients
  }

  var body: some View {
    NavigationStack(path: router.path(for: tab)) {
      content
        .modifier(ShellDestinations())
    }
  }

  @ViewBuilder private var content: some View {
    switch tab {
    case .home: HomeTabScreen(session: session, clients: clients)
    case .search: SearchTabScreen(clients: clients)
    case .messages: MessagesTabScreen(clients: clients)
    case .notifications: NotificationsTabScreen(clients: clients)
    case .profile: ProfileTabScreen(clients: clients)
    }
  }
}

// MARK: - Home

/**
 The Home tab: the live feed over the resolved pinned feeds, or the demo feed.

 The live model construction follows the RN `Home` screen: the pinned timeline
 first, then the stored saved-feeds v2 entries resolved through
 ``PinnedFeedsResolver``, then one ``HomeFeedQuery`` per descriptor with the
 fetcher type the descriptor needs (timeline, generator, list). Everything
 runs through the shell's shared ``QueryStore``.

 The account control and the token gallery stay on the toolbar exactly where
 ``TabPlaceholderScreen`` carried them, so the account menu and the AC.7
 gallery surface keep working from every tab.
 */
private struct HomeTabScreen: View {
  private let session: AppSession?
  private let clients: AppSessionClients?

  @Environment(\.alfTheme) private var theme
  @Environment(ShellRouter.self) private var router

  init(session: AppSession?, clients: AppSessionClients?) {
    self.session = session
    self.clients = clients
  }

  var body: some View {
    content
      .navigationTitle(AppTab.home.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { toolbar }
      .accessibilityIdentifier(ShellAccessibility.screen(AppTab.home.routeName))
  }

  @ViewBuilder private var content: some View {
    if let clients {
      LiveHomeFeed(clients: clients)
    } else {
      // The demo path: the fixture feed the screenshot loop captures.
      HomeFeedDemoScreen()
    }
  }

  /// The stored ALF preference, the same resolution the debug sheets use.
  @AppStorage("alfTheme") private var themePreferenceRaw = ThemePreference.system.rawValue

  private var themePreference: ThemePreference {
    ThemePreference(rawValue: themePreferenceRaw) ?? .system
  }

  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      NavigationLink {
        TokenGallery(theme: theme)
          .navigationTitle("Tokens")
          .navigationBarTitleDisplayMode(.inline)
          .accessibilityIdentifier(ShellAccessibility.tokenGallery)
      } label: {
        Image(systemName: "circle.lefthalf.filled")
      }
      .accessibilityLabel("Token gallery")
      .accessibilityIdentifier(ShellAccessibility.tokenGalleryButton)
    }
  }

  /// Builds the live feed model, then renders the production screen over it.
  ///
  /// Model construction is async (the pinned feeds resolve over the network),
  /// so the view shows the feed's own skeleton until the model exists.
  private struct LiveHomeFeed: View {
    let clients: AppSessionClients

    @Environment(\.alfTheme) private var theme
    @Environment(ShellRouter.self) private var router

    @State private var model: HomeFeedModel?

    var body: some View {
      Group {
        if let model {
          HomeFeedScreen(
            model: HomeFeedViewModel(
              model: model, presentation: .feeds, viewerDid: clients.did),
            onOpenRichText: { router.open($0) },
            onOpenPost: { router.open(.thread(uri: $0)) })
        } else {
          ListSkeleton()
        }
      }
      .background(theme.atomColors.bg)
      .task {
        model = await ShellFeedFactory.buildModel(clients: clients)
      }
    }
  }
}

// MARK: - Search

/**
 The Search tab: the production search screen over a live view model.

 `LiveSearchService` adapts the fetchers to the screen's service protocol, so
 typeahead, the results tabs and the Explore page all run against the
 signed-in account. `XrpcClient` already conforms to `SearchXRPCCalling`, so
 the appview client is the whole transport.
 */
private struct SearchTabScreen: View {
  private let clients: AppSessionClients?

  @Environment(\.alfTheme) private var theme

  init(clients: AppSessionClients?) {
    self.clients = clients
  }

  var body: some View {
    Group {
      if let clients {
        LiveSearch(clients: clients)
      } else {
        // The demo path: the fixture Explore surface the screenshot loop
        // captures, without navigation chrome (the tab owns the stack).
        SearchFixtureSurfaces.searchContent(theme: themePreference)
      }
    }
    .accessibilityIdentifier(ShellAccessibility.screen(AppTab.search.routeName))
  }

  @AppStorage("alfTheme") private var themePreferenceRaw = ThemePreference.system.rawValue

  private var themePreference: ThemePreference {
    ThemePreference(rawValue: themePreferenceRaw) ?? .system
  }

  private struct LiveSearch: View {
    let clients: AppSessionClients

    @Environment(ShellRouter.self) private var router

    @State private var explore = ExplorePageData(sections: [])
    @State private var isLoadingExplore = true

    var body: some View {
      SearchScreen(
        viewModel: SearchViewModel(
          service: LiveSearchService(fetchers: SearchFetchers(client: clients.appview))),
        exploreData: explore,
        isLoadingExplore: isLoadingExplore,
        onSelectProfile: { router.open(.profile(actor: "\($0.did)")) },
        onSelectFeed: { router.open(.feed(uri: "\($0.uri)", name: $0.displayName ?? "Feed")) },
        onSelectStarterPack: { _ in },
        onSelectTrendingTopic: { router.open(.search(query: $0)) })
        .task { await loadExplore() }
    }

    /// Loads the Explore page through the shared store, best effort.
    ///
    /// A failed module (trending, suggested accounts, starter packs) must not
    /// blank the tab: the assembly tolerates missing inputs, so each read runs
    /// independently and the page renders with whatever landed.
    private func loadExplore() async {
      let queries = SearchQueries(
        store: clients.store, fetchers: SearchFetchers(client: clients.appview))

      async let topics = try? await queries.getTrendingTopics(scope: clients.did)
      async let users = try? await queries.suggestedUsersForExplore(scope: clients.did)
      async let feeds = try? await queries.suggestedFeeds(scope: clients.did)
      async let packs = try? await queries.suggestedStarterPacks(scope: clients.did)

      var input = ExploreAssembly.Input()
      input.trendingTopics = await topics
      input.suggestedUsers = await users
      input.suggestedFeeds = await feeds
      input.suggestedStarterPacks = await packs
      input.useFullExperience = true

      explore = ExploreAssembly.build(input)
      isLoadingExplore = false
    }
  }
}

// MARK: - Messages

/**
 The Chat tab: the production inbox over a live ``InboxQuery``.

 The chat client is the session's chat-proxied client, so conversations run
 against `api.bsky.chat` with the account's credentials. Tapping a
 conversation is the deferred router seam: `onSelect` is where a pushed
 conversation screen goes once the shell can navigate.
 */
private struct MessagesTabScreen: View {
  private let clients: AppSessionClients?

  @Environment(ShellRouter.self) private var router

  init(clients: AppSessionClients?) {
    self.clients = clients
  }

  var body: some View {
    Group {
      if let clients {
        InboxScreen(
          viewModel: InboxViewModel(
            inbox: InboxQuery(
              store: clients.store,
              client: LiveChatXrpc(client: clients.chat),
              scope: clients.did),
            currentAccountDid: clients.did),
          onSelect: { router.open(.conversation(convoId: $0)) })
      } else {
        // The demo path: the scripted fixture inbox the screenshot loop
        // captures.
        MessagesFixtureSurfaces.inboxScreen()
      }
    }
    .accessibilityIdentifier(ShellAccessibility.screen(AppTab.messages.routeName))
  }
}

// MARK: - Notifications

/**
 The Notifications tab: the production list over a live
 ``NotificationFeedQuery``.

 The Views package's screen takes rows, not a view model, so the app owns the
 load: one query over the shared store, pages applied through
 ``NotificationsListModel`` (the package's own select pass). The filter bar's
 selection state stays inside the screen until the package exposes a
 filter-aware live model; the rows are the unfiltered set today.
 */
private struct NotificationsTabScreen: View {
  private let clients: AppSessionClients?

  @Environment(\.alfTheme) private var theme

  init(clients: AppSessionClients?) {
    self.clients = clients
  }

  var body: some View {
    Group {
      if let clients {
        LiveNotifications(clients: clients)
      } else {
        // The demo path: the fixture rows the screenshot loop captures.
        NotificationsSurfaces.notificationsScreen(theme: themePreference)
      }
    }
    .accessibilityIdentifier(ShellAccessibility.screen(AppTab.notifications.routeName))
  }

  @AppStorage("alfTheme") private var themePreferenceRaw = ThemePreference.system.rawValue

  private var themePreference: ThemePreference {
    ThemePreference(rawValue: themePreferenceRaw) ?? .system
  }

  private struct LiveNotifications: View {
    let clients: AppSessionClients

    @Environment(ShellRouter.self) private var router

    @State private var rows: [FeedNotification] = []
    @State private var isInitialLoading = true
    @State private var failed = false

    var body: some View {
      NotificationsScreen(
        rows: rows,
        isInitialLoading: isInitialLoading,
        onRefresh: { await load() },
        onOpenPost: { router.open(.thread(uri: $0)) })
        .task { await load() }
    }

    private func load() async {
      isInitialLoading = rows.isEmpty
      let fetcher = NotificationPageFetcher(
        client: XRPCNotificationClient(client: clients.appview))
      let query = NotificationFeedQuery(
        store: clients.store,
        filter: .all,
        scope: clients.did,
        fetchPage: { cursor in try await fetcher.page(cursor: cursor) })

      do {
        _ = try await query.loadFirstPage()
        rows = try await query.items()
        failed = false
      } catch {
        failed = true
      }
      isInitialLoading = false
      // The screen takes the error through its list-state; a failed first
      // load with no rows renders the error branch through `rows: []` plus
      // this flag only when the package's surface exposes it. Until then a
      // failed load shows the empty state, which is the RN behaviour for a
      // notifications feed that errors *after* content is on screen.
      _ = failed
    }
  }
}

// MARK: - Profile

/**
 The Profile tab: the signed-in account's own profile.

 The live path loads the account's profile through ``ProfileClient`` and
 renders the production ``ProfileScreen`` header. The author feed (the posts
 under the header) needs the feed wiring the Home tab owns, so it stays a
 documented seam: the header renders alone, with an empty content section.
 The demo path renders the fixture profile surface.
 */
private struct ProfileTabScreen: View {
  private let clients: AppSessionClients?

  init(clients: AppSessionClients?) {
    self.clients = clients
  }

  var body: some View {
    Group {
      if let clients {
        LiveProfile(clients: clients)
      } else {
        // The demo path: the fixture profile the screenshot loop captures.
        ProfileFixtureSurface()
      }
    }
    .accessibilityIdentifier(ShellAccessibility.screen(AppTab.profile.routeName))
  }

  private struct LiveProfile: View {
    let clients: AppSessionClients

    @Environment(\.alfTheme) private var theme
    @Environment(ShellRouter.self) private var router

    @State private var headerData: ProfileHeaderViewData?
    @State private var showsEdit = false

    var body: some View {
      Group {
        if let headerData {
          ProfileScreen(
            headerData: headerData,
            // TODO: author-feed seam - the posts under the header need the
            // feed wiring the Home tab owns; the header renders alone until
            // the shell can share it.
            onAction: handle)
        } else {
          ListSkeleton()
        }
      }
      .background(theme.atomColors.bg)
      .sheet(isPresented: $showsEdit) {
        if let headerData, case .detailed(let profile) = headerData.unshadowedProfile {
          EditProfileSheet(
            profile: profile,
            onCancel: { showsEdit = false },
            onSave: { edit in
              showsEdit = false
              Task { try? await ProfileEditor.save(clients: clients, edit: edit) }
            })
        }
      }
      .task { await load() }
    }

    /// Routes the header's actions; only edit-profile has a surface today.
    private func handle(_ action: ProfileHeaderAction) {
      switch action {
      case .editProfile:
        showsEdit = true
      case .follow, .unfollow, .showFollowers, .showFollows:
        // Mutations and follower lists are the next seams.
        break
      }
    }

    private func load() async {
      guard
        let profile = try? await ProfileClient(client: clients.appview)
          .getProfile(actor: clients.did)
      else { return }
      headerData = ProfileHeaderViewData(
        profile: .detailed(profile),
        // TODO: moderation seam - default preferences until the shell
        // hydrates the account's moderation prefs and label defs.
        moderationOpts: ModerationOpts(userDid: clients.did, prefs: ModerationPrefs()),
        viewerDid: clients.did,
        hasSession: true)
    }
  }
}

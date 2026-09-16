import SwiftUI
import UIComponents

/**
 The shell's navigation: one typed route enum, one path per tab.

 `AppRootView`'s two `TabView` construction sites each own a router, inject it
 into the environment, and keep its `activeTab` in sync with the tab selection
 so ``open(_:)-43fj3`` pushes onto the stack the user is looking at. Each tab
 screen wraps its content in a `NavigationStack(path:)` bound to its slice of
 the router and registers ``ShellDestinations`` for the route type.

 The RN app navigates through a central navigator with ~90 typed routes; this
 is the same shape, scoped to the routes the wired surfaces actually produce
 today.
 */
@MainActor
@Observable
final class ShellRouter {

  /** A pushed screen. */
  enum Route: Hashable {
    /** A post's thread, by `at://` URI. */
    case thread(uri: String)
    /** A profile, by handle or DID. */
    case profile(actor: String)
    /** A custom feed, by generator URI. */
    case feed(uri: String, name: String)
    /** A starter pack, by record URI. */
    case starterPack(uri: String, name: String)
    /** A committed search (trending topics arrive here). */
    case search(query: String)
    /** A chat conversation, by convo id. */
    case conversation(convoId: String)
  }

  /// The tab whose stack receives ``open(_:)`` pushes; kept in sync by the
  /// owning `TabView`'s selection.
  var activeTab: AppTab

  /// One navigation path per tab, so switching tabs preserves each stack.
  private var pathsByTab: [AppTab: [Route]] = [:]

  /// The signed-in session's query bundle, set by `SessionGateView` when the
  /// clients are (re)built. Route screens read it to load their content.
  var clients: AppSessionClients?

  init(activeTab: AppTab = .home) {
    self.activeTab = activeTab
  }

  /// The path binding a tab's `NavigationStack` uses.
  func path(for tab: AppTab) -> Binding<[Route]> {
    Binding(
      get: { [weak self] in self?.pathsByTab[tab] ?? [] },
      set: { [weak self] in self?.pathsByTab[tab] = $0 })
  }

  /** Pushes a route onto the active tab's stack. */
  func open(_ route: Route) {
    pathsByTab[activeTab, default: []].append(route)
  }

  /** Pops the active tab's stack by one. */
  func pop() {
    _ = pathsByTab[activeTab]?.popLast()
  }

  /// Opens a rich-text tap target: internal targets push, external ones leave
  /// the app through the system handler.
  func open(_ target: RichTextTarget) {
    switch target {
    case .profile(let did):
      open(.profile(actor: did))
    case .hashtag(let tag):
      open(.search(query: "#\(tag)"))
    case .post(let uri):
      open(.thread(uri: uri))
    case .external(let url):
      UIApplication.shared.open(url)
    }
  }
}

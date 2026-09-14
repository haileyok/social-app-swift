import Foundation

/// The state a list surface is in.
///
/// The RN app models these with separate components plus a `QueryState`
/// switch; the port keeps the switch as data so a list view is one exhaustive
/// switch and the loading/empty/error copy sits in one place.
public enum ListState: Equatable, Sendable {
  /// First load, nothing to show yet.
  case loading
  /// Loading a subsequent page over existing content.
  case loadingMore
  /// Loaded, with at least one item.
  case content
  /// Loaded, with no items.
  case empty
  /// The last load failed. `hasContent` distinguishes a first-page failure
  /// (full-surface error) from a pagination failure (inline retry).
  case error(ListErrorState)

  /// The error payload.
  public struct ListErrorState: Equatable, Sendable {
    public let title: String
    public let message: String
    /// True when content is already on screen, so the retry affordance is a
    /// row rather than a full-screen state.
    public let hasContent: Bool

    public init(title: String, message: String, hasContent: Bool = false) {
      self.title = title
      self.message = message
      self.hasContent = hasContent
    }
  }
}

extension ListState {
  /// Derives the state from an item count and an optional error.
  ///
  /// Errors win over an empty-but-loaded list because a failed load is not an
  /// empty result: retrying is the right affordance, not "follow people".
  public static func resolve(
    itemCount: Int,
    isInitialLoading: Bool,
    error: ListErrorState? = nil
  ) -> ListState {
    if let error { return .error(error) }
    if isInitialLoading, itemCount == 0 { return .loading }
    return itemCount == 0 ? .empty : .content
  }

  /// The number of skeleton rows a full-surface loading state renders. Enough to
  /// fill a phone viewport so the list does not jump when real content lands.
  public static let skeletonRowCount = 6
}

/// The copy a v1 list surface shows. Kept here so empty and error states read
/// the same everywhere and are testable without a view.
public struct ListStrings: Equatable, Sendable {
  public let emptyTitle: String
  public let emptyMessage: String
  public let errorTitle: String
  public let errorMessage: String
  public let retryLabel: String

  public init(
    emptyTitle: String,
    emptyMessage: String,
    errorTitle: String,
    errorMessage: String,
    retryLabel: String = "Retry"
  ) {
    self.emptyTitle = emptyTitle
    self.emptyMessage = emptyMessage
    self.errorTitle = errorTitle
    self.errorMessage = errorMessage
    self.retryLabel = retryLabel
  }

  /// The default feed copy.
  public static let feed = ListStrings(
    emptyTitle: "Nothing here yet",
    emptyMessage: "Follow some people to see their posts.",
    errorTitle: "Could not load this feed",
    errorMessage: "Something went wrong. Check your connection and try again.")

  /// The default profile-feed copy.
  public static let profile = ListStrings(
    emptyTitle: "No posts yet",
    emptyMessage: "When this account posts, you will see it here.",
    errorTitle: "Could not load this profile",
    errorMessage: "Something went wrong. Check your connection and try again.")

  /// The default notification copy.
  public static let notifications = ListStrings(
    emptyTitle: "No notifications yet",
    emptyMessage: "When someone replies, likes or follows you, it will show up here.",
    errorTitle: "Could not load notifications",
    errorMessage: "Something went wrong. Check your connection and try again.")
}

/// Message-content classification for a failed list load, so the retry copy is
/// specific without the view inspecting error types.
public enum ListFailureKind: String, Sendable, CaseIterable {
  case offline
  case server
  case unknown

  /// The user-facing message for this failure kind.
  public var message: String {
    switch self {
    case .offline: "You appear to be offline. Check your connection and try again."
    case .server: "The server could not be reached. Try again in a moment."
    case .unknown: "Something went wrong. Try again."
    }
  }
}

/// The toast queue's presentation model.
///
/// A toast is a short-lived bottom banner. The core owns the data (what a toast
/// is, how long it lives, whether one is showing) so the SwiftUI modifier is a
/// pure render of ``ToastState``.
public struct Toast: Equatable, Identifiable, Sendable {
  public let id: UUID
  public let message: String
  public let kind: ToastKind
  /// How long the toast stays up before auto-dismissing.
  public let duration: TimeInterval

  public init(
    id: UUID = UUID(),
    message: String,
    kind: ToastKind = .neutral,
    duration: TimeInterval = 3
  ) {
    self.id = id
    self.message = message
    self.kind = kind
    self.duration = duration
  }
}

/// The toast flavours the v1 scaffold supports.
public enum ToastKind: String, Sendable, CaseIterable {
  case neutral
  case success
  case error
}

/// The presentation state for the toast modifier: at most one toast is visible,
/// with newer toasts replacing older ones.
public struct ToastState: Equatable, Sendable {
  public private(set) var current: Toast?
  /// Toasts waiting behind ``current``.
  public private(set) var queue: [Toast]

  public init(current: Toast? = nil, queue: [Toast] = []) {
    self.current = current
    self.queue = queue
  }

  /// True when a toast should be on screen.
  public var isPresented: Bool { current != nil }

  /// Shows a toast, replacing the visible one and queueing the rest.
  public mutating func show(_ toast: Toast) {
    if let current {
      queue.append(current)
    }
    current = toast
  }

  /// Dismisses the visible toast and promotes the next queued one.
  public mutating func dismiss() {
    current = queue.isEmpty ? nil : queue.removeFirst()
  }

  /// Dismisses everything.
  public mutating func clear() {
    current = nil
    queue.removeAll()
  }
}

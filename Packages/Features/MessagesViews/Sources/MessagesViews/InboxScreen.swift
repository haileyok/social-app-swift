import DesignSystem
import DesignTokens
import Foundation
import Lexicons
import MessagesLogic
import SwiftUI
import UIComponents

/// The conversation list: one row per 1:1 conversation, newest first.
///
/// The screen owns no data logic: it renders ``InboxViewModel/convos`` and calls
/// back for the first page, the next page and a row tap. Group and join surfaces
/// do not exist in this scope; the inbox query has already dropped group convos,
/// so a row is always a 1:1 conversation.
public struct InboxScreen: View {
  @Environment(\.alfTheme) private var theme

  @State private var viewModel: InboxViewModel

  private let onSelect: (Chat.Bsky.ConvoDefs_ConvoView) -> Void

  /// Creates the inbox screen.
  ///
  /// - Parameters:
  ///   - viewModel: the adapter over ``InboxQuery``.
  ///   - onSelect: invoked with a conversation id when a row is tapped.
  public init(
    viewModel: InboxViewModel,
    onSelect: @escaping (Chat.Bsky.ConvoDefs_ConvoView) -> Void
  ) {
    _viewModel = State(initialValue: viewModel)
    self.onSelect = onSelect
  }

  public var body: some View {
    Group {
      switch viewModel.state {
      case .loading:
        ListSkeleton()
      case .empty:
        EmptyStateView(
          icon: "bubble.left.and.bubble.right",
          title: MessagesCopy.inboxEmptyTitle,
          message: MessagesCopy.inboxEmptyMessage)
        .accessibilityIdentifier(MessagesAccessibility.inboxEmpty)
      case .error(let error) where !error.hasContent:
        ErrorStateView(error: error) {
          Task { await viewModel.load() }
        }
      default:
        list
      }
    }
    .background(theme.atomColors.bg)
    .accessibilityIdentifier(MessagesAccessibility.inbox)
    .task { await viewModel.runVisibleSync() }
  }

  private var list: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(viewModel.convos, id: \.id) { convo in
          let row = InboxRow.make(convo, currentAccountDid: viewModel.currentAccountDid)
          Button {
            onSelect(convo)
          } label: {
            InboxRowView(row: row)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier(MessagesAccessibility.inboxRow(convo.id))
          Divider()
            .overlay(theme.atomColors.borderContrastLow)
        }

        if case .loadingMore = viewModel.state {
          LoadMoreSpinner()
        } else if case .error(let error) = viewModel.state, error.hasContent {
          RetryRow(message: error.title) {
            Task { await viewModel.loadMoreIfNeeded() }
          }
        }
      }
    }
    .refreshable { await viewModel.refresh() }
  }
}

/// Pending direct-message requests with explicit server-backed decisions.
public struct ChatRequestsScreen: View {
  @Environment(\.alfTheme) private var theme
  @State private var viewModel: InboxViewModel
  @State private var updating = Set<String>()

  private let onAccept: (Chat.Bsky.ConvoDefs_ConvoView) async -> Bool
  private let onDelete: (Chat.Bsky.ConvoDefs_ConvoView) async -> Bool

  public init(
    viewModel: InboxViewModel,
    onAccept: @escaping (Chat.Bsky.ConvoDefs_ConvoView) async -> Bool,
    onDelete: @escaping (Chat.Bsky.ConvoDefs_ConvoView) async -> Bool
  ) {
    _viewModel = State(initialValue: viewModel)
    self.onAccept = onAccept
    self.onDelete = onDelete
  }

  public var body: some View {
    Group {
      switch viewModel.state {
      case .loading:
        ListSkeleton()
      case .empty:
        EmptyStateView(
          icon: "tray",
          title: "No chat requests",
          message: "New message requests will appear here.")
      case .error(let error) where !error.hasContent:
        ErrorStateView(error: error) { Task { await viewModel.load() } }
      default:
        list
      }
    }
    .background(theme.atomColors.bg)
    .navigationTitle("Chat requests")
    .navigationBarTitleDisplayMode(.inline)
    .task { await viewModel.runVisibleSync() }
  }

  private var list: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(viewModel.convos, id: \.id) { convo in
          VStack(spacing: Spacing.sm) {
            InboxRowView(
              row: InboxRow.make(convo, currentAccountDid: viewModel.currentAccountDid))
            HStack(spacing: Spacing.sm) {
              Button("Delete", role: .destructive) {
                Task { await decide(convo, accepting: false) }
              }
              .buttonStyle(.bordered)
              Button("Accept") {
                Task { await decide(convo, accepting: true) }
              }
              .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, Spacing.lg)
          }
          .padding(.bottom, Spacing.sm)
          .disabled(updating.contains(convo.id))
          Divider().overlay(theme.atomColors.borderContrastLow)
        }
        if viewModel.hasMore {
          LoadMoreSpinner().task { await viewModel.loadMoreIfNeeded() }
        }
      }
    }
    .refreshable { await viewModel.refresh() }
  }

  private func decide(
    _ convo: Chat.Bsky.ConvoDefs_ConvoView,
    accepting: Bool
  ) async {
    guard updating.insert(convo.id).inserted else { return }
    defer { updating.remove(convo.id) }
    let succeeded = accepting ? await onAccept(convo) : await onDelete(convo)
    if succeeded { viewModel.remove(convoId: convo.id) }
  }
}

/// Full-height account search for starting a direct conversation.
public struct NewConversationScreen: View {
  @Environment(\.alfTheme) private var theme
  @State private var query = ""
  @State private var actors: [App.Bsky.ActorDefs_ProfileViewBasic] = []
  @State private var isSearching = false
  @State private var startingDid: String?
  @State private var errorMessage: String?

  private let currentAccountDid: String
  private let search: @Sendable (String) async throws -> [App.Bsky.ActorDefs_ProfileViewBasic]
  private let start: @Sendable (String) async throws -> Chat.Bsky.ConvoDefs_ConvoView
  private let onOpen: (Chat.Bsky.ConvoDefs_ConvoView) -> Void

  public init(
    currentAccountDid: String,
    search: @escaping @Sendable (String) async throws
      -> [App.Bsky.ActorDefs_ProfileViewBasic],
    start: @escaping @Sendable (String) async throws -> Chat.Bsky.ConvoDefs_ConvoView,
    onOpen: @escaping (Chat.Bsky.ConvoDefs_ConvoView) -> Void
  ) {
    self.currentAccountDid = currentAccountDid
    self.search = search
    self.start = start
    self.onOpen = onOpen
  }

  public var body: some View {
    VStack(spacing: 0) {
      searchField
      Divider().overlay(theme.atomColors.borderContrastLow)
      content
    }
    .background(theme.atomColors.bg)
    .navigationTitle("New chat")
    .navigationBarTitleDisplayMode(.inline)
    .task(id: query) { await searchIfNeeded() }
  }

  private var searchField: some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(theme.atomColors.textContrastMedium)
      TextField("Search people", text: $query)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
      if !query.isEmpty {
        Button { query = "" } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(theme.atomColors.textContrastMedium)
        }
        .accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, Spacing.md)
    .frame(minHeight: 46)
    .background(theme.atomColors.bgContrast25)
    .clipShape(.rect(cornerRadius: 12))
    .padding(Spacing.md)
  }

  @ViewBuilder private var content: some View {
    if let errorMessage {
      VStack(spacing: Spacing.md) {
        Image(systemName: "exclamationmark.circle")
          .font(.system(size: 30))
          .foregroundStyle(theme.atomColors.textContrastMedium)
        AlfText(errorMessage, scale: .sm, color: theme.atomColors.textContrastMedium)
          .multilineTextAlignment(.center)
        Button("Try again") { Task { await performSearch() } }
          .buttonStyle(.borderedProminent)
      }
      .padding(Spacing.xl)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if isSearching {
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      EmptyStateView(
        icon: "person.crop.circle.badge.plus",
        title: "Start a new chat",
        message: "Search for someone by their name or handle.")
    } else if actors.isEmpty {
      EmptyStateView(
        icon: "person.slash",
        title: "No people found",
        message: "Try another name or handle.")
    } else {
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(actors, id: \.did.rawValue) { actor in
            Button { Task { await open(actor) } } label: {
              actorRow(actor)
            }
            .buttonStyle(.plain)
            .disabled(startingDid != nil)
            Divider().overlay(theme.atomColors.borderContrastLow)
          }
        }
      }
    }
  }

  private func actorRow(_ actor: App.Bsky.ActorDefs_ProfileViewBasic) -> some View {
    HStack(spacing: Spacing.md) {
      Avatar(
        avatar: actor.avatar?.rawValue,
        handle: actor.handle.rawValue,
        displayName: actor.displayName,
        size: .lg)
      VStack(alignment: .leading, spacing: 2) {
        AlfText(
          actor.displayName?.isEmpty == false ? actor.displayName! : actor.handle.rawValue,
          scale: .md,
          weight: Scales.FontWeight.semiBold)
          .lineLimit(1)
        AlfText(
          "@\(actor.handle.rawValue)", scale: .sm,
          color: theme.atomColors.textContrastMedium)
          .lineLimit(1)
      }
      Spacer()
      if startingDid == actor.did.rawValue {
        ProgressView()
      } else {
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(theme.atomColors.textContrastMedium)
      }
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.vertical, Spacing.md)
    .contentShape(.rect)
  }

  private func searchIfNeeded() async {
    do {
      try await Task.sleep(for: .milliseconds(250))
    } catch { return }
    guard !Task.isCancelled else { return }
    await performSearch()
  }

  private func performSearch() async {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else {
      actors = []
      errorMessage = nil
      isSearching = false
      return
    }
    isSearching = true
    errorMessage = nil
    do {
      let found = try await search(term)
      guard term == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
      actors = found.filter { $0.did.rawValue != currentAccountDid }
      isSearching = false
    } catch is CancellationError {
      return
    } catch {
      guard term == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
      actors = []
      isSearching = false
      errorMessage = "We couldn't search for people. Check your connection and try again."
    }
  }

  private func open(_ actor: App.Bsky.ActorDefs_ProfileViewBasic) async {
    guard startingDid == nil else { return }
    startingDid = actor.did.rawValue
    errorMessage = nil
    do {
      let convo = try await start(actor.did.rawValue)
      onOpen(convo)
    } catch let failure as NewConversationFailure {
      errorMessage = failure.message
      startingDid = nil
    } catch {
      errorMessage = NewConversationFailure.unknown.message
      startingDid = nil
    }
  }
}

/// One conversation row: avatar, name, preview, unread badge, muted indicator.
public struct InboxRowView: View {
  @Environment(\.alfTheme) private var theme

  private let row: InboxRow

  public init(row: InboxRow) {
    self.row = row
  }

  public var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Avatar(avatar: row.avatarURL, handle: row.handle, displayName: row.name, size: .lg)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          AlfText(row.name, scale: .md, weight: Scales.FontWeight.semiBold)
            .lineLimit(1)
          if row.muted {
            Image(systemName: "bell.slash.fill")
              .font(.system(size: 11))
              .foregroundStyle(theme.atomColors.textContrastMedium)
              .accessibilityLabel(MessagesCopy.mutedAccessibilityLabel)
          }
          Spacer(minLength: 8)
          if let timestamp = row.timestamp {
            AlfText(
              MessageDateSeparator.relativeLabel(for: timestamp),
              scale: .xs,
              color: theme.atomColors.textContrastMedium
            )
            .lineLimit(1)
          }
        }

        HStack(alignment: .top, spacing: 8) {
          AlfText(
            row.preview,
            scale: .sm,
            weight: row.unreadCount > 0
              ? Scales.FontWeight.medium : Scales.FontWeight.normal,
            color: row.unreadCount > 0
              ? theme.atomColors.text : theme.atomColors.textContrastMedium
          )
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)

          if row.unreadCount > 0 {
            unreadBadge
          }
        }
      }
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.vertical, Spacing.md)
    .contentShape(.rect)
  }

  private var unreadBadge: some View {
    Text(badgeText)
      .font(TypeScale.xxs.font(weight: Scales.FontWeight.semiBold))
      .foregroundStyle(theme.atomColors.textInverted)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .frame(minWidth: 20)
      .background(theme.colors.primary500)
      .clipShape(.capsule)
      .accessibilityLabel(MessagesCopy.unreadAccessibilityLabel(row.unreadCount))
  }

  /// The badge label, capped at "99+" the way every badge in the app is.
  private var badgeText: String {
    row.unreadCount > 99 ? "99+" : "\(row.unreadCount)"
  }
}

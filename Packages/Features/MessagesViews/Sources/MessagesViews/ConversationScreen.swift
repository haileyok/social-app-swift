import DesignSystem
import DesignTokens
import Lexicons
import MessagesLogic
import SwiftUI
import UIComponents

/// A conversation: the message list, date separators, the send bar, and the
/// load-older / scroll-to-bottom affordances.
///
/// The screen renders ``ConversationViewModel`` and forwards every action to it;
/// no paging, send or reaction rule lives here. Group and join surfaces do not
/// exist in this scope, so the header is always the 1:1 partner.
public struct ConversationScreen: View {
  @Environment(\.alfTheme) private var theme

  @State private var viewModel: ConversationViewModel
  /// True when the user has scrolled away from the newest message, so the
  /// scroll-to-bottom control is showing.
  @State private var isScrolledAway = false

  private let onBack: (() -> Void)?

  /// Creates the conversation screen.
  ///
  /// - Parameters:
  ///   - viewModel: the adapter over ``ConversationModel``.
  ///   - showsBackButton: whether to render a leading back control.
  ///   - onBack: invoked when the back control is tapped.
  public init(
    viewModel: ConversationViewModel,
    showsBackButton: Bool = true,
    onBack: (() -> Void)? = nil
  ) {
    _viewModel = State(initialValue: viewModel)
    self.showsBackButton = showsBackButton
    self.onBack = onBack
  }

  private let showsBackButton: Bool

  public var body: some View {
    VStack(spacing: 0) {
      messages
      ComposerBar(
        text: $viewModel.draft,
        canSend: viewModel.canSend,
        failure: viewModel.sendFailure,
        onSend: { Task { await viewModel.send() } },
        onRetry: { Task { await viewModel.retrySend() } })
    }
    .background(theme.atomColors.bg)
    .navigationTitle(viewModel.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if showsBackButton {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            onBack?()
          } label: {
            Image(systemName: "chevron.left")
          }
          .accessibilityLabel("Back")
          .accessibilityIdentifier(MessagesAccessibility.conversationBack)
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          Task { await viewModel.setMuted(!viewModel.isMuted) }
        } label: {
          Image(systemName: viewModel.isMuted ? "bell.slash.fill" : "bell")
        }
        .accessibilityLabel(viewModel.isMuted ? "Unmute" : "Mute")
      }
    }
    .accessibilityIdentifier(MessagesAccessibility.conversation)
    .task {
      await viewModel.loadIfNeeded()
      await viewModel.markRead()
    }
  }

  @ViewBuilder
  private var messages: some View {
    ScrollViewReader { proxy in
      ZStack(alignment: .bottomTrailing) {
        ScrollView {
          LazyVStack(spacing: 0) {
            loadOlderRow
            ForEach(viewModel.rows) { row in
              switch row {
              case .separator(_, let label):
                DateSeparatorRow(label: label)
              case .item(let item):
                itemRow(item)
                  .id(row.id)
              }
            }
          }
          .padding(.vertical, Spacing.sm)
        }
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: Bool.self) { geometry in
          // True when the newest row is off the bottom of the viewport.
          geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
            > 120
        } action: { _, isAway in
          isScrolledAway = isAway
        }
        .onChange(of: viewModel.rows.count) { _, _ in
          scrollToBottom(proxy, animated: true)
        }

        if isScrolledAway {
          Button {
            scrollToBottom(proxy, animated: true)
          } label: {
            Image(systemName: "arrow.down.circle.fill")
              .font(.system(size: 30))
              .foregroundStyle(theme.atomColors.textInverted, theme.colors.primary500)
          }
          .accessibilityLabel(MessagesCopy.scrollToBottom)
          .accessibilityIdentifier(MessagesAccessibility.scrollToBottom)
          .padding(Spacing.lg)
        }
      }
    }
  }

  /// The "load older" affordance at the top of the list.
  @ViewBuilder
  private var loadOlderRow: some View {
    if viewModel.isFetchingHistory {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
    } else if viewModel.hasAllHistory {
      AlfText(
        MessagesCopy.beginningOfConversation, scale: .xs,
        color: theme.atomColors.textContrastMedium
      )
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.md)
    } else {
      Button {
        Task { await viewModel.loadHistory() }
      } label: {
        AlfText(MessagesCopy.loadOlder, scale: .sm, color: theme.atomColors.textLink)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.md)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier(MessagesAccessibility.loadOlder)
    }
  }

  /// One message item, with the state and read receipt it carries.
  private func itemRow(_ item: ConvoItem) -> some View {
    let isMine = isMine(item)
    let state = sendState(item)
    return MessageBubble(
      item: item,
      isMine: isMine,
      sendState: state,
      showReadReceipt: isMine && state == .sent && isReadAhead(item),
      currentAccountDid: viewModel.currentAccountDid,
      onToggleReaction: { messageId, emoji, mine in
        Task { await viewModel.toggleReaction(messageId: messageId, emoji: emoji, mine: mine) }
      },
      onRetrySend: { Task { await viewModel.retrySend() } },
      onRetryHistory: { Task { await viewModel.loadHistory() } })
  }

  /// True when the message was sent by the signed-in account.
  private func isMine(_ item: ConvoItem) -> Bool {
    switch item {
    case .message(let view): view.sender.did.rawValue == viewModel.currentAccountDid
    case .pendingMessage: true
    case .deletedMessage(let view): view.sender.did.rawValue == viewModel.currentAccountDid
    case .systemMessage, .error: false
    }
  }

  /// The send state a message item carries. Only the outbox has a live state;
  /// an acknowledged message is `.sent`.
  private func sendState(_ item: ConvoItem) -> MessageSendState {
    switch item {
    case .pendingMessage(let pending): pending.failed ? .failed : .pending
    case .error(let code) where code == .firehoseFailed: .failed
    case .message, .deletedMessage, .systemMessage, .error: .sent
    }
  }

  /// Whether a "Read" receipt is warranted for this message.
  ///
  /// The wire data has no per-message read receipt: a convo carries only the
  /// viewer's own `unreadCount`. So the receipt here is derived the honest way -
  /// a sent message renders "Read" only when the conversation's unread count is
  /// zero, meaning the partner has read up to the newest rev - and is suppressed
  /// otherwise. When the server exposes a per-message read state this is the one
  /// place to widen.
  private func isReadAhead(_ item: ConvoItem) -> Bool {
    guard case .message = item else { return false }
    return (viewModel.convo?.unreadCount ?? 0) == 0
  }

  private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
    guard let last = viewModel.rows.last else { return }
    withAnimation(animated ? .easeOut(duration: 0.2) : nil) {
      proxy.scrollTo(last.id, anchor: .bottom)
    }
  }
}

/// A date separator chip.
struct DateSeparatorRow: View {
  @Environment(\.alfTheme) private var theme

  let label: String

  var body: some View {
    HStack {
      AlfText(label, scale: .xs, color: theme.atomColors.textContrastMedium)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 3)
        .background(theme.atomColors.bgContrast100)
        .clipShape(.capsule)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Spacing.sm)
  }
}

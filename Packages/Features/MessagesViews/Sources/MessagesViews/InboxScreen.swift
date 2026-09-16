import DesignSystem
import DesignTokens
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
    .task { await viewModel.loadIfNeeded() }
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

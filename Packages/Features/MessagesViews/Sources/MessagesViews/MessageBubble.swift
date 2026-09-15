import DesignSystem
import DesignTokens
import Lexicons
import MessagesLogic
import RichText
import SwiftUI
import UIComponents

/// One reaction value on one message, aggregated.
public struct ReactionGroup: Identifiable, Sendable, Equatable {
  /// The emoji.
  public let emoji: String
  /// How many people reacted with it.
  public let count: Int
  /// Whether the signed-in account is among them.
  public let mine: Bool

  public var id: String { emoji }

  /// Groups a message's reactions by value, most-reacted first.
  ///
  /// - Parameters:
  ///   - reactions: the message's reaction views.
  ///   - currentAccountDid: the signed-in DID, so `mine` is per group.
  public static func groups(
    _ reactions: [Chat.Bsky.ConvoDefs_ReactionView], currentAccountDid: String?
  ) -> [ReactionGroup] {
    var order: [String] = []
    var counts: [String: Int] = [:]
    var mine: Set<String> = []
    for reaction in reactions {
      if counts[reaction.value] == nil { order.append(reaction.value) }
      counts[reaction.value, default: 0] += 1
      if reaction.sender.did.rawValue == currentAccountDid {
        mine.insert(reaction.value)
      }
    }
    return order
      .map { ReactionGroup(emoji: $0, count: counts[$0] ?? 0, mine: mine.contains($0)) }
      .sorted { lhs, rhs in
        lhs.count == rhs.count ? lhs.emoji < rhs.emoji : lhs.count > rhs.count
      }
  }
}

/// A message row in the conversation list.
///
/// Renders every ``ConvoItem`` case the model emits: a user message (mine or
/// theirs, with reactions and, for mine, the send state), a deleted tombstone, a
/// system message, and the two error rows (history failed, outbox failed).
struct MessageBubble: View {
  @Environment(\.alfTheme) private var theme

  let item: ConvoItem
  let isMine: Bool
  let sendState: MessageSendState
  let showReadReceipt: Bool
  let currentAccountDid: String?
  let onToggleReaction: (String, String, Bool) -> Void
  let onRetrySend: () -> Void
  let onRetryHistory: () -> Void

  var body: some View {
    switch item {
    case .message(let view):
      bubble(view)
    case .deletedMessage:
      DeletedMessageRow()
    case .systemMessage(let view):
      SystemMessageRow(view: view)
    case .pendingMessage(let pending):
      pendingBubble(pending)
    case .error(let code):
      errorRow(code)
    }
  }

  // MARK: - Bubbles

  private func bubble(_ view: Chat.Bsky.ConvoDefs_MessageView) -> some View {
    let groups = ReactionGroup.groups(view.reactions ?? [], currentAccountDid: currentAccountDid)
    return HStack {
      if isMine { Spacer(minLength: 48) }
      VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
        bubbleBody(view.text, facets: view.facets, failed: false)
        if !groups.isEmpty {
          reactionRow(view: view, groups: groups)
        }
        metaRow(
          date: MessagesDate.date(from: view.sentAt.rawValue),
          state: sendState,
          showReadReceipt: showReadReceipt)
      }
      if !isMine { Spacer(minLength: 48) }
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, 3)
    .accessibilityIdentifier(MessagesAccessibility.bubble(view.id))
  }

  private func pendingBubble(_ pending: PendingMessage) -> some View {
    let failed = pending.failed
    return HStack {
      Spacer(minLength: 48)
      VStack(alignment: .trailing, spacing: 4) {
        bubbleBody(pending.message.text, facets: pending.message.facets, failed: failed)
        if failed {
          failedRow
        } else {
          metaRow(date: nil, state: .pending, showReadReceipt: false)
        }
      }
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, 3)
    .accessibilityIdentifier(MessagesAccessibility.bubble(pending.id))
  }

  /// The bubble's text surface. Mine is filled with the brand colour and the
  /// text is inverted; theirs is a contrast surface with normal text.
  private func bubbleBody(_ text: String, facets: [App.Bsky.RichtextFacet]?, failed: Bool)
    -> some View
  {
    let segments = MessageFacets.segments(text: text, facets: facets)
    return Group {
      if isMine {
        RichTextBody(segments: segments, scale: .md)
          .padding(.horizontal, Spacing.md)
          .padding(.vertical, Spacing.sm)
          .background(theme.colors.primary500)
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      } else {
        RichTextBody(segments: segments, scale: .md)
          .padding(.horizontal, Spacing.md)
          .padding(.vertical, Spacing.sm)
          .background(theme.atomColors.bgContrast100)
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      }
    }
    .opacity(failed ? 0.7 : 1)
  }

  // MARK: - Reactions

  private func reactionRow(
    view: Chat.Bsky.ConvoDefs_MessageView, groups: [ReactionGroup]
  ) -> some View {
    HStack(spacing: 4) {
      ForEach(groups) { group in
        Button {
          onToggleReaction(view.id, group.emoji, group.mine)
        } label: {
          HStack(spacing: 3) {
            Text(group.emoji)
            if group.count > 1 {
              AlfText("\(group.count)", scale: .xxs, color: theme.atomColors.textContrastMedium)
            }
          }
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(
            group.mine ? theme.colors.primary100 : theme.atomColors.bgContrast50)
          .clipShape(.capsule)
          .overlay(
            Capsule().stroke(
              group.mine ? theme.colors.primary400 : theme.atomColors.borderContrastLow,
              lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(MessagesAccessibility.reaction(view.id, emoji: group.emoji))
      }
      reactionPicker(view.id)
    }
  }

  /// The add-reaction affordance: a menu of the quick reaction set.
  private func reactionPicker(_ messageId: String) -> some View {
    Menu {
      ForEach(MessagesCopy.quickReactions, id: \.self) { emoji in
        Button(emoji) { onToggleReaction(messageId, emoji, false) }
      }
    } label: {
      Image(systemName: "face.smiling")
        .font(.system(size: 13))
        .foregroundStyle(theme.atomColors.textContrastMedium)
        .padding(5)
        .background(theme.atomColors.bgContrast50)
        .clipShape(.capsule)
    }
    .accessibilityLabel(MessagesCopy.addReactionAccessibilityLabel)
    .accessibilityIdentifier(MessagesAccessibility.reactionButton(messageId))
  }

  // MARK: - Metadata

  private func metaRow(date: Date?, state: MessageSendState, showReadReceipt: Bool) -> some View {
    HStack(spacing: 4) {
      if state == .pending {
        ProgressView().controlSize(.mini)
        AlfText(MessagesCopy.sendingAccessibilityLabel, scale: .xxs, color: theme.atomColors.textContrastMedium)
          .accessibilityLabel(MessagesCopy.sendingAccessibilityLabel)
      } else {
        if let date {
          AlfText(
            date.formatted(Date.FormatStyle(date: .omitted, time: .shortened)),
            scale: .xxs, color: theme.atomColors.textContrastMedium)
        }
        if showReadReceipt {
          Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(theme.atomColors.textContrastMedium)
          AlfText(MessagesCopy.readReceipt, scale: .xxs, color: theme.atomColors.textContrastMedium)
        }
      }
    }
  }

  private var failedRow: some View {
    HStack(spacing: 4) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 11))
        .foregroundStyle(theme.colors.negative500)
      Button(MessagesCopy.sendFailed, action: onRetrySend)
        .buttonStyle(.plain)
        .font(TypeScale.xs.font(weight: Scales.FontWeight.medium))
        .foregroundStyle(theme.colors.negative500)
        .accessibilityLabel(MessagesCopy.retrySendAccessibilityLabel)
        .accessibilityIdentifier(MessagesAccessibility.composerRetry)
    }
  }

  private func errorRow(_ code: ConvoItemErrorCode) -> some View {
    VStack(spacing: Spacing.sm) {
      AlfText(
        code == .historyFailed
          ? MessagesCopy.loadOlder : MessagesCopy.sendFailed,
        scale: .sm, color: theme.atomColors.textContrastMedium)
      Button(MessagesCopy.retry) {
        if code == .historyFailed {
          onRetryHistory()
        } else {
          onRetrySend()
        }
      }
      .buttonStyle(.alf(color: .secondary, size: .small))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Spacing.md)
  }
}

/// A deleted-message tombstone.
struct DeletedMessageRow: View {
  @Environment(\.alfTheme) private var theme

  var body: some View {
    AlfText(MessagesCopy.deletedMessage, scale: .sm, color: theme.atomColors.textContrastMedium)
      .italic()
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.xs)
  }
}

/// A system message (a member or metadata event).
struct SystemMessageRow: View {
  @Environment(\.alfTheme) private var theme

  let view: Chat.Bsky.ConvoDefs_SystemMessageView

  var body: some View {
    AlfText(Self.label(view.data), scale: .xs, color: theme.atomColors.textContrastMedium)
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.xs)
  }

  /// The copy for a system message.
  ///
  /// Every system-message kind in the lexicon is a group or lock event, and
  /// group/join surfaces are out of the 1:1 scope: a 1:1 convo does not produce
  /// one. The data layer still surfaces the item (it decodes tolerantly), so this
  /// renders a short generic line derived from the referred DID rather than
  /// reconstructing group metadata the product does not show.
  static func label(_ data: Chat.Bsky.ConvoDefs_SystemMessageView_Data) -> String {
    switch data {
    case .convoDefsSystemMessageDataAddMember(let add):
      "\(shortDid(add.member.did.rawValue)) was added"
    case .convoDefsSystemMessageDataRemoveMember(let removed):
      "\(shortDid(removed.member.did.rawValue)) was removed"
    case .convoDefsSystemMessageDataMemberJoin(let join):
      "\(shortDid(join.member.did.rawValue)) joined"
    case .convoDefsSystemMessageDataMemberLeave(let leave):
      "\(shortDid(leave.member.did.rawValue)) left"
    case .convoDefsSystemMessageDataLockConvo:
      "This chat was locked"
    case .convoDefsSystemMessageDataUnlockConvo:
      "This chat was unlocked"
    case .convoDefsSystemMessageDataLockConvoPermanently:
      "This chat was locked permanently"
    case .convoDefsSystemMessageDataEditGroup:
      "Chat details were updated"
    case .convoDefsSystemMessageDataCreateJoinLink,
      .convoDefsSystemMessageDataEditJoinLink,
      .convoDefsSystemMessageDataEnableJoinLink,
      .convoDefsSystemMessageDataDisableJoinLink:
      "A join link was updated"
    case ._other:
      "Chat updated"
    }
  }

  /// The trailing segment of a DID, so a system line stays readable.
  private static func shortDid(_ did: String) -> String {
    did.split(separator: ":").last.map(String.init) ?? did
  }
}

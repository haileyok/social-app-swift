import DesignSystem
import DesignTokens
import Lexicons
import MessagesLogic
import QueryStore
import SwiftUI

/// The fixture surfaces: a scripted 1:1 conversation rendered through the real
/// inbox and conversation screens.
///
/// This is the "fixture surfaces" deliverable from the task: a way to see and
/// drive every message treatment - mine vs theirs, a date separator boundary,
/// reactions, an optimistic pending echo, a failed send with retry, a read
/// receipt - with no session and no network. It is the same shape as the token
/// and component galleries: a self-contained SwiftUI surface the app root can
/// mount behind a debug control, and a set of `#Preview`s.
///
/// The screens it mounts are the production views; only the transport differs
/// (``ScriptedChatClient`` answering from ``MessagesFixtures``). That is the
/// point: the fixture path and the live path render through the exact same code.
public enum MessagesFixtureSurfaces {
  /// A view model over the scripted conversation, pre-seeded with the outbox
  /// treatments: one message that fails on its first attempt (left in the outbox
  /// so the failed-retry bubble renders) and one that succeeds.
  ///
  /// Returns the model without awaiting; the caller runs ``runFixtureScript(_:)``
  /// from a `.task` so the sends happen after the screen is on screen and the
  /// transitions (optimistic echo, failure, retry) are visible.
  @MainActor
  public static func scriptedConversationModel() -> ConversationViewModel {
    let convo = MessagesFixtures.convo()
    let client = ScriptedChatClient(
      convos: [convo, MessagesFixtures.secondConvo()],
      history: [MessagesFixtures.convoId: MessagesFixtures.history()],
      failingOnce: [MessagesFixtures.failedText])
    let model = ConversationModel(
      convoId: MessagesFixtures.convoId,
      client: client,
      senderDid: MessagesFixtures.selfDid,
      convo: convo)
    return ConversationViewModel(model: model, currentAccountDid: MessagesFixtures.selfDid)
  }

  /// Drives the fixture script: first a send that fails (filling the failed
  /// outbox), then a send that succeeds (a normal sent bubble). Idempotent per
  /// instance, so a re-run of `.task` does not double-send.
  @MainActor
  public static func runFixtureScript(_ viewModel: ConversationViewModel) async {
    guard !scripted.contains(ObjectIdentifier(viewModel)) else { return }
    scripted.insert(ObjectIdentifier(viewModel))
    await viewModel.send(MessagesFixtures.failedText)
    await viewModel.send("Great, see you at 10!")
  }

  /// The view models already scripted, so the script runs once each.
  @MainActor private static var scripted = Set<ObjectIdentifier>()

  /// A view model over the scripted inbox.
  @MainActor
  public static func scriptedInboxModel() -> InboxViewModel {
    let client = ScriptedChatClient(
      convos: [MessagesFixtures.convo(), MessagesFixtures.secondConvo()],
      history: [MessagesFixtures.convoId: MessagesFixtures.history()])
    let store = QueryStore()
    let inbox = InboxQuery(
      store: store, client: client, status: .accepted,
      scope: MessagesFixtures.selfDid)
    return InboxViewModel(inbox: inbox, currentAccountDid: MessagesFixtures.selfDid)
  }

  /// The conversation screen over the scripted conversation, with the fixture
  /// script wired to its `.task` so the pending/failed/reaction treatments are
  /// visible as soon as it appears.
  @MainActor
  public static func conversationScreen() -> some View {
    ScriptedConversationScreen()
  }

  /// The inbox screen over the scripted inbox.
  @MainActor
  public static func inboxScreen() -> some View {
    InboxScreen(viewModel: scriptedInboxModel(), onSelect: { _ in })
  }
}

/// A gallery that shows the fixture surfaces: the inbox list, then the scripted
/// conversation with its pending, failed and reacted messages.
///
/// Mountable from the app root the way the login sheet is:
///
/// ```swift
/// NavigationStack { MessagesFixtureGallery() }
/// ```
public struct MessagesFixtureGallery: View {
  @Environment(\.alfTheme) private var theme

  @State private var selection: Surface = .conversation

  /// The surfaces the gallery can show.
  public enum Surface: String, CaseIterable, Identifiable {
    case conversation
    case inbox
    case states

    public var id: String { rawValue }
    var title: String {
      switch self {
      case .conversation: "Conversation"
      case .inbox: "Inbox"
      case .states: "States"
      }
    }
  }

  public init() {}

  public var body: some View {
    VStack(spacing: 0) {
      Picker("Surface", selection: $selection) {
        ForEach(Surface.allCases) { surface in
          Text(surface.title).tag(surface)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      Divider().overlay(theme.atomColors.borderContrastLow)
      content
    }
  }

  @ViewBuilder
  private var content: some View {
    switch selection {
    case .conversation:
      MessagesFixtureSurfaces.conversationScreen()
    case .inbox:
      NavigationStack {
        MessagesFixtureSurfaces.inboxScreen()
          .navigationTitle(MessagesCopy.surfacesTitle)
          .navigationBarTitleDisplayMode(.inline)
      }
    case .states:
      MessagesStateGallery()
    }
  }
}

/// The scripted conversation screen: the production ``ConversationScreen`` with
/// the fixture script attached, so the pending, failed and reacted treatments are
/// on screen without a session.
struct ScriptedConversationScreen: View {
  @State private var viewModel = MessagesFixtureSurfaces.scriptedConversationModel()

  var body: some View {
    ConversationScreen(viewModel: viewModel, showsBackButton: false)
      .task { await MessagesFixtureSurfaces.runFixtureScript(viewModel) }
  }
}

/// The list-state surfaces (loading/empty/error) built from ``UIComponents`` with
/// the messages copy, so the inbox's states are previewable on their own.
struct MessagesStateGallery: View {
  @Environment(\.alfTheme) private var theme

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        section("Loading") {
          ListSkeleton(rowCount: 3)
        }
        section("Empty") {
          EmptyStateView(
            icon: "bubble.left.and.bubble.right",
            title: MessagesCopy.inboxEmptyTitle,
            message: MessagesCopy.inboxEmptyMessage)
          .frame(height: 220)
        }
        section("Error") {
          ErrorStateView(
            title: MessagesCopy.inboxErrorTitle,
            message: MessagesCopy.inboxErrorMessage
          ) {}
          .frame(height: 220)
        }
      }
      .padding(.vertical, Spacing.md)
    }
    .background(theme.atomColors.bg)
  }

  private func section<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      AlfText(title, scale: .sm, weight: Scales.FontWeight.semiBold)
        .padding(.horizontal, Spacing.md)
      content()
    }
    .padding(.bottom, Spacing.lg)
  }
}

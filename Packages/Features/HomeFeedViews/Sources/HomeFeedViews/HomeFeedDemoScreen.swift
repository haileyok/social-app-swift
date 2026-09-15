import DesignSystem
import DesignSystemCore
import HomeFeedLogic
import RichText
import SwiftUI
import UIComponents
import UIComponentsCore

/**
 The demo/feed-preview surface.

 The Home screen depends on a live session, an appview and a hydrated
 preferences store - none of which exist in a screenshot run. This view renders
 the same building blocks the real screen uses (``HomeFeedRowView``, the
 switcher, the pill, both empty states, both error states) over
 ``HomeFeedFixtures`` data, so the screenshot loop captures the production view
 path instead of a mock.

 It doubles as the diagnostic surface: it is the only place that renders every
 state side by side, so a visual regression in one of them shows up in a single
 image.
 */
public struct HomeFeedDemoScreen: View {
  /// Which state to show. The screenshot loop passes one of these in.
  public enum Variant: String, CaseIterable, Sendable {
    /// A populated feed with every embed variant, a repost, a pin and a thread.
    case feed
    /// The new-posts pill revealed.
    case pill
    /// The first-load skeleton.
    case loading
    /// A feed that returned nothing.
    case empty
    /// A feed whose posts were all filtered by moderation.
    case emptyFiltered
    /// The no-feeds-pinned state.
    case noFeeds
    /// The logged-out state.
    case loggedOut
    /// An offline failure.
    case error

    /// The launch-argument value the screenshot loop passes.
    public var argument: String { rawValue }
  }

  private let variant: Variant
  private let onOpenRichText: (RichTextTarget) -> Void

  @Environment(\.alfTheme) private var theme

  public init(
    variant: Variant = .feed,
    onOpenRichText: @escaping (RichTextTarget) -> Void = { _ in }
  ) {
    self.variant = variant
    self.onOpenRichText = onOpenRichText
  }

  /// Builds the variant named by a launch argument, defaulting to ``Variant/feed``.
  public init(argument: String?, onOpenRichText: @escaping (RichTextTarget) -> Void = { _ in }) {
    self.init(
      variant: argument.flatMap(Variant.init(rawValue:)) ?? .feed,
      onOpenRichText: onOpenRichText)
  }

  public var body: some View {
    VStack(spacing: 0) {
      if showsSwitcher {
        FeedSwitcherBar(
          feeds: HomeFeedFixtures.pinnedFeeds,
          selected: .following,
          onSelect: { _ in })
      }
      content
    }
    .background(theme.atomColors.bg)
    .overlay(alignment: .top) {
      if variant == .pill {
        NewPostsPill {}
          .padding(.top, showsSwitcher ? 96 : Spacing.md)
      }
    }
  }

  private var showsSwitcher: Bool {
    switch variant {
    case .feed, .pill, .loading, .empty, .emptyFiltered, .error:
      return true
    case .noFeeds, .loggedOut:
      return false
    }
  }

  @ViewBuilder
  private var content: some View {
    switch variant {
    case .feed, .pill:
      fixtureList(HomeFeedFixtures.slices)
    case .emptyFiltered:
      fixtureList([HomeFeedFixtures.allFilteredSlice])
    case .loading:
      ListSkeleton()
    case .empty:
      centred {
        HomeFeedEmptyState(reason: .following)
      }
    case .noFeeds:
      centred {
        HomeFeedEmptyState(reason: .noFeedsPinned)
      }
    case .loggedOut:
      centred {
        HomeFeedEmptyState(reason: .loggedOut)
      }
    case .error:
      centred {
        HomeFeedErrorState(error: .network) {}
      }
    }
  }

  /// The fixture rows, rendered through the production row view.
  private func fixtureList(_ slices: [HomeFeedSlice]) -> some View {
    let rows = HomeFeedViewData.rows(
      slices,
      moderationOpts: nil,
      viewerDid: nil,
      options: HomeFeedRenderOptions.fixture(now: HomeFeedFixtures.now))
    return List {
      ForEach(rows) { row in
        HomeFeedRowView(row: row, onOpenRichText: onOpenRichText)
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(theme.atomColors.bg)
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
  }

  private func centred<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack {
      Spacer(minLength: 0)
      content()
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// Render-option helpers shared by the demo and a fixture-driven screen.
public enum HomeFeedRenderOptions {
  /// Render options pinned to a fixed clock, so relative timestamps are stable.
  public static func fixture(now: Date) -> FeedItemRenderOptions {
    FeedItemRenderOptions(now: now)
  }
}

#Preview {
  HomeFeedDemoScreen()
    .theme(ThemePreference.light)
}

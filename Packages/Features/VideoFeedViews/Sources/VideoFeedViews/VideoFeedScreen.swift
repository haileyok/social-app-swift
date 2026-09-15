import DesignSystem
import SwiftUI
import UIComponents
import VideoFeedLogic

/// The immersive, full-screen vertical video feed.
///
/// The SwiftUI counterpart of `src/screens/VideoFeed/index.tsx`: a vertical pager
/// whose pages are video posts, with the pager state machine deciding which item
/// plays and the autoplay derivation deciding whether it may. Nothing about that
/// policy lives here - the screen owns the controller and the chrome, and both
/// read their answers from ``VideoFeedLogic``.
///
/// ```swift
/// VideoFeedScreen(items: videoItems)
/// ```
public struct VideoFeedScreen: View {
  /// The items to page through.
  private let items: [VideoItem]
  /// The autoplay inputs, from the persisted preference.
  private let settings: VideoAutoplaySettings
  /// The page to open on.
  private let initialIndex: Int

  /// The pager controller, created once the view has appeared so a rebuilding
  /// `body` never builds a fresh player pool.
  @State private var controller: VideoFeedController?

  @Environment(\.alfTheme) private var theme

  /// Creates the screen.
  ///
  /// - Parameters:
  ///   - items: the feed items, in pager order.
  ///   - settings: the autoplay inputs. Build them with
  ///     ``VideoAutoplayPreference/settings(account:did:)`` so the stored
  ///     preference and the platform's reduced-motion default apply.
  ///   - initialIndex: the page to open on.
  public init(
    items: [VideoItem],
    settings: VideoAutoplaySettings = VideoAutoplaySettings(),
    initialIndex: Int = 0
  ) {
    self.items = items
    self.settings = settings
    self.initialIndex = initialIndex
  }

  public var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if items.isEmpty {
        emptyState
      } else {
        pager
      }
    }
    .accessibilityIdentifier(VideoFeedAccessibility.screen)
    .task {
      guard controller == nil else { return }
      let created = VideoFeedController(
        items: items, settings: settings, initialIndex: initialIndex)
      created.start()
      controller = created
    }
    .onChange(of: items.map(\.id)) { _, _ in
      controller?.update(items: items)
    }
    .onChange(of: settings) { _, newValue in
      controller?.update(items: items, settings: newValue)
    }
    .onDisappear { controller?.stop() }
  }

  private var pager: some View {
    VideoFeedPager(
      items: items,
      index: controller?.currentIndex ?? initialIndex,
      onViewportChange: handleViewport,
      page: { index in
        AnyView(
          VideoFeedPage(
            item: items[index],
            index: index,
            isActive: (controller?.currentIndex ?? initialIndex) == index,
            controller: controller,
            onOpen: { _ in })
        )
      }
    )
    .ignoresSafeArea()
  }

  /// Feeds a settled viewport observation back into the controller.
  ///
  /// The delegate only reports a settled offset, and the pager's config requires
  /// a fully covered viewport, so a landed page moves the machine directly. A
  /// host that can report mid-scroll visibility would call
  /// ``VideoFeedController/observe(_:)`` instead and let
  /// ``VideoViewabilityConfig`` decide.
  private func handleViewport(_ index: Int, fraction: Double) {
    guard fraction >= 1 - Self.viewportEpsilon else { return }
    controller?.moveTo(index)
  }

  /// How far off a fully-covered viewport a settled page may be. The paging
  /// scroll view lands within a fraction of a point of the boundary.
  private static let viewportEpsilon = 0.001

  private var emptyState: some View {
    VStack(spacing: Spacing.sm) {
      Image(systemName: "film.stack")
        .font(.system(size: 28, weight: .semibold))
      Text(VideoFeedStrings.videoUnavailable)
        .font(TypeScale.md.font(weight: Scales.FontWeight.semiBold))
        .multilineTextAlignment(.center)
    }
    .foregroundStyle(theme.atomColors.textInverted)
    .padding(.xl)
  }
}

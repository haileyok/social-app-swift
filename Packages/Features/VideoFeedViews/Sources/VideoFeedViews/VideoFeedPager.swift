import DesignSystem
import SwiftUI
import UIKit
import VideoFeedLogic

/// The full-screen vertical pager.
///
/// `TabView(selection:)` with `.page` style cannot report a fractional viewport,
/// and the pager state machine needs one: RN reads `onViewableItemsChanged` with a
/// 100 percent threshold, which is exactly the "one page fully covers the
/// viewport" observation a `UIScrollView` content offset yields. Backing the
/// pager with a `UIScrollView` therefore keeps ``VideoPagerStateMachine`` - and
/// the ``VideoViewabilityConfig`` it enforces - the single source of truth for
/// which page is active, in both directions: a swipe reports an observation, and
/// a programmatic move scrolls the view.
struct VideoFeedPager: UIViewRepresentable {
  /// The items to page through.
  let items: [VideoItem]
  /// The index the pager should be showing.
  let index: Int
  /// Called when the offset settles, with the landed index and the fraction of
  /// the viewport that index covers.
  let onViewportChange: (Int, Double) -> Void
  /// Builds one page. The index is passed so the page can address its own slots.
  let page: (Int) -> AnyView

  func makeCoordinator() -> Coordinator {
    Coordinator(onViewportChange: onViewportChange)
  }

  func makeUIView(context: Context) -> UIScrollView {
    let scrollView = UIScrollView()
    scrollView.isPagingEnabled = true
    scrollView.showsVerticalScrollIndicator = false
    scrollView.alwaysBounceVertical = false
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.delegate = context.coordinator
    scrollView.accessibilityIdentifier = VideoFeedAccessibility.pager
    return scrollView
  }

  func updateUIView(_ scrollView: UIScrollView, context: Context) {
    context.coordinator.update(items: items, index: index, page: page, in: scrollView)
  }

  /// Owns the hosting controllers, one per page.
  ///
  /// One controller per item rather than one reused page keeps each page's
  /// `@State` (caption expansion, drag state) attached to its own item, which is
  /// what the RN list does with its per-row component instances.
  @MainActor
  final class Coordinator: NSObject, UIScrollViewDelegate {
    private let onViewportChange: (Int, Double) -> Void
    private var hosts: [UIHostingController<AnyView>] = []
    private var itemIDs: [String] = []
    /// Set while a programmatic scroll is in flight, so the delegate callback it
    /// produces is not reported back as a user swipe.
    private var isProgrammaticScroll = false

    init(onViewportChange: @escaping (Int, Double) -> Void) {
      self.onViewportChange = onViewportChange
    }

    func update(
      items: [VideoItem],
      index: Int,
      page: (Int) -> AnyView,
      in scrollView: UIScrollView
    ) {
      let ids = items.map(\.id)
      if ids != itemIDs {
        rebuild(items: items, page: page, in: scrollView)
        itemIDs = ids
      } else {
        for (offset, host) in hosts.enumerated() {
          host.rootView = page(offset)
        }
      }
      scroll(to: index, in: scrollView)
    }

    private func rebuild(
      items: [VideoItem],
      page: (Int) -> AnyView,
      in scrollView: UIScrollView
    ) {
      for host in hosts {
        host.view.removeFromSuperview()
        host.removeFromParent()
      }
      hosts = items.enumerated().map { offset, _ in
        let host = UIHostingController(rootView: page(offset))
        host.view.backgroundColor = .black
        return host
      }
      for host in hosts { scrollView.addSubview(host.view) }
      layout(in: scrollView)
    }

    private func layout(in scrollView: UIScrollView) {
      let size = scrollView.bounds.size
      guard size.height > 0, size.width > 0 else { return }
      scrollView.contentSize = CGSize(width: size.width, height: size.height * Double(hosts.count))
      for (offset, host) in hosts.enumerated() {
        host.view.frame = CGRect(
          x: 0,
          y: size.height * Double(offset),
          width: size.width,
          height: size.height)
      }
    }

    /// Scrolls to `index` without reporting it back, so a state-driven move and a
    /// swipe-driven one converge instead of ping-ponging.
    private func scroll(to index: Int, in scrollView: UIScrollView) {
      layout(in: scrollView)
      let height = scrollView.bounds.height
      guard height > 0, hosts.indices.contains(index) else { return }
      let target = CGPoint(x: 0, y: height * Double(index))
      guard abs(scrollView.contentOffset.y - target.y) > 1 else { return }
      isProgrammaticScroll = true
      scrollView.setContentOffset(target, animated: false)
      isProgrammaticScroll = false
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
      report(scrollView)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
      report(scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
      guard !decelerate else { return }
      report(scrollView)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
      // A drag that has already settled on a whole page is the moment RN's
      // viewability callback fires; reporting mid-drag would hand the machine a
      // page it has not arrived at yet.
      guard !isProgrammaticScroll, !scrollView.isDragging, !scrollView.isDecelerating else {
        return
      }
      report(scrollView)
    }

    /// Reports the settled offset as an observation.
    ///
    /// The visible fraction is `1 - distance from the nearest page boundary`, so
    /// a page only clears the 100 percent threshold once it covers the viewport
    /// completely - the machine's config, not this view, decides what counts.
    private func report(_ scrollView: UIScrollView) {
      let height = scrollView.bounds.height
      guard height > 0 else { return }
      let raw = scrollView.contentOffset.y / height
      let index = Int(raw.rounded())
      guard hosts.indices.contains(index) else { return }
      let fraction = max(0, 1 - abs(raw - Double(index)))
      onViewportChange(index, fraction)
    }
  }
}

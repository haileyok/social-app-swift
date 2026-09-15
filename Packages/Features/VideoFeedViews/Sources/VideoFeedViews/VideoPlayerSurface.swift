import AVFoundation
import DesignSystem
import SwiftUI
import UIKit

/// A thin `AVPlayerLayer` host.
///
/// SwiftUI has no `AVPlayerLayer` view, so the surface is a `UIView` that swaps
/// its backing layer for the player's. The pool owns the players, so the layer
/// this view shows only ever points at an already-existing player: nothing here
/// creates, stops, or reconfigures playback.
struct VideoPlayerSurface: UIViewRepresentable {
  /// The slot whose layer is displayed.
  let slot: VideoPlayerSlot
  /// `.resizeAspectFill` for a tall (portrait) item, `.resizeAspect` otherwise.
  let fills: Bool

  func makeUIView(context: Context) -> VideoPlayerHostView {
    let view = VideoPlayerHostView()
    view.backgroundColor = .black
    view.playerLayer = slot.layer
    applyGravity(to: view)
    return view
  }

  func updateUIView(_ view: VideoPlayerHostView, context: Context) {
    if view.playerLayer !== slot.layer {
      view.playerLayer = slot.layer
    }
    applyGravity(to: view)
  }

  private func applyGravity(to view: VideoPlayerHostView) {
    let gravity: AVLayerVideoGravity = fills ? .resizeAspectFill : .resizeAspect
    guard slot.layer.videoGravity != gravity else { return }
    slot.layer.videoGravity = gravity
  }
}

/// The backing view for ``VideoPlayerSurface``.
final class VideoPlayerHostView: UIView {
  /// The player layer this view displays.
  var playerLayer: AVPlayerLayer? {
    didSet {
      guard playerLayer !== oldValue else { return }
      oldValue?.removeFromSuperlayer()
      guard let playerLayer else { return }
      playerLayer.frame = bounds
      layer.addSublayer(playerLayer)
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // The player layer is not driven by Auto Layout, so it follows the host's
    // bounds; disabling the implicit animation keeps a resize from sliding the
    // video across the screen.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    playerLayer?.frame = bounds
    CATransaction.commit()
  }
}

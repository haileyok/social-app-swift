import SwiftUI

/// A wrapping layout for the interest chips.
///
/// SwiftUI has no flow layout in the SDK's `Layout` protocol's standard set, and
/// the interest grid must wrap at any width (a 24-chip taxonomy is far wider
/// than the onboarding column). This is the minimal implementation: place
/// subviews left to right, wrapping to a new line when the proposed width is
/// exceeded, matching RN's `flex_wrap` chip row.
struct FlowLayout: Layout {
  var spacing: Double = 8
  var lineSpacing: Double = 8

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var origin = CGPoint.zero
    var lineHeight: Double = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if origin.x > 0, origin.x + size.width > maxWidth {
        origin.x = 0
        origin.y += lineHeight + lineSpacing
        lineHeight = 0
      }
      origin.x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
    return CGSize(width: maxWidth == .infinity ? origin.x : maxWidth, height: origin.y + lineHeight)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var origin = CGPoint(x: bounds.minX, y: bounds.minY)
    var lineHeight: Double = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if origin.x > bounds.minX, origin.x + size.width > bounds.maxX {
        origin.x = bounds.minX
        origin.y += lineHeight + lineSpacing
        lineHeight = 0
      }
      subview.place(
        at: origin, anchor: .topLeading,
        proposal: ProposedViewSize(width: size.width, height: size.height))
      origin.x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
  }
}

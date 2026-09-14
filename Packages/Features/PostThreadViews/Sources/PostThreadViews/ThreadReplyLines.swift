import DesignSystem
import PostThreadLogic
import SwiftUI

/// The indent gutter to the left of a thread row: the reply lines that connect
/// a row to its parent and to its children.
///
/// Port of the RN thread's `ThreadItemIndent`/`ThreadItemArrow` pair. The
/// geometry comes entirely from ``ThreadConnector``, which the logic package
/// computes in its flattening pass - the view only draws what it is told, so a
/// row never inspects the tree.
///
/// The gutter is one ``ThreadRowAdapter/indentStep`` wide per level. A level
/// draws a vertical line when the row has an ancestor chain above it
/// (`showParentReplyLine`) or descendants below it (`showChildReplyLine`); an
/// elbow is drawn into the row's own level when it is the last child of its
/// branch (`isLastChild`) so the line terminates instead of dangling.
struct ThreadReplyLines: View {
  let connector: ThreadConnector?

  @Environment(\.alfTheme) private var theme

  private var step: Double { ThreadRowAdapter.indentStep }

  var body: some View {
    let levels = max(0, connector?.indent ?? 0)
    ZStack(alignment: .topLeading) {
      ForEach(0..<levels, id: \.self) { level in
        // The column for this ancestor level. The last column is the row's own
        // level, which is where the elbow lives.
        let isOwnLevel = level == levels - 1
        lineOrElbow(at: Double(level) * step, isOwnLevel: isOwnLevel)
      }
    }
    .frame(width: Double(levels) * step, alignment: .topLeading)
    .frame(maxHeight: .infinity, alignment: .top)
    .accessibilityHidden(true)
  }

  /// A vertical line at `x`, terminated with a corner when this is the row's
  /// own level and the row is a last child.
  @ViewBuilder
  private func lineOrElbow(at x: Double, isOwnLevel: Bool) -> some View {
    let color = theme.atomColors.borderContrastMedium
    if isOwnLevel, connector?.isLastChild == true {
      // Last child: an elbow, so the branch visually ends here.
      Path { path in
        path.move(to: CGPoint(x: x + step / 2, y: 0))
        path.addLine(to: CGPoint(x: x + step / 2, y: 14))
        path.addLine(to: CGPoint(x: x + step, y: 14))
      }
      .stroke(color, lineWidth: 2)
      .frame(maxHeight: .infinity, alignment: .top)
    } else if isOwnLevel, connector?.showParentReplyLine != true {
      // The first row of a branch with nothing above it: no line yet.
      EmptyView()
    } else {
      Rectangle()
        .fill(color)
        .frame(width: 2)
        .frame(maxHeight: .infinity)
        .offset(x: x + step / 2)
    }
  }
}

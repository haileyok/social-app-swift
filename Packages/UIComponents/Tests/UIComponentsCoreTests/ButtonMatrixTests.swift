import Moderation
import Testing

@testable import UIComponentsCore

/// The button matrix is pure data, so every cell is asserted here rather than
/// eyeballed in the gallery.
@Suite("Button matrix")
struct ButtonMatrixTests {
  @Test("Every color resolves a total scheme")
  func colorSchemesAreTotal() {
    // A missing case would be a compile error in the switch; this asserts the
    // tokens the RN matrix actually uses so a rename is caught.
    #expect(ButtonColor.primary.scheme.background == .palette("primary_500"))
    #expect(ButtonColor.primary.scheme.hoverBackground == .palette("primary_600"))
    #expect(ButtonColor.primary.scheme.disabledBackground == .palette("primary_200"))

    #expect(ButtonColor.secondary.scheme.background == .atom("bgContrast50"))
    #expect(ButtonColor.secondary.scheme.foreground == .atom("textContrastMedium"))

    #expect(ButtonColor.secondaryInverted.scheme.background == .palette("contrast_900"))
    #expect(ButtonColor.secondaryInverted.scheme.foreground == .atom("textInverted"))

    #expect(ButtonColor.negative.scheme.background == .palette("negative_500"))
    #expect(ButtonColor.negative.scheme.disabledBackground == .palette("negative_700"))

    #expect(ButtonColor.primarySubtle.scheme.background == .palette("primary_50"))
    #expect(ButtonColor.primarySubtle.scheme.foreground == .palette("primary_600"))

    #expect(ButtonColor.negativeSubtle.scheme.background == .palette("negative_50"))
    #expect(ButtonColor.negativeSubtle.scheme.foreground == .palette("negative_600"))
  }

  @Test("The RN matrix has every documented color")
  func colorMatrixMatchesRN() {
    #expect(
      Set(ButtonColor.allCases.map(\.rawValue)) == [
        "primary", "secondary", "secondary_inverted", "negative", "primary_subtle",
        "negative_subtle",
      ])
  }

  @Test("The default resolve matches the RN defaults (primary/small/pill)")
  func defaultResolve() {
    let resolved = ResolvedButton.resolve()
    #expect(resolved.color == .primary)
    #expect(resolved.size == .small)
    #expect(resolved.shape == .`default`)
    #expect(resolved.metrics.isCapsule)
    #expect(resolved.metrics.paddingVertical == 8)
    #expect(resolved.metrics.paddingHorizontal == 14)
    #expect(resolved.metrics.gap == 5)
    #expect(resolved.metrics.textScale == .sm)
    #expect(resolved.metrics.fontWeight == .medium)
  }

  @Test("Pill metrics match the RN size table")
  func pillMetrics() {
    let large = ResolvedButton.resolve(size: .large).metrics
    #expect(large.paddingVertical == 12)
    #expect(large.paddingHorizontal == 24)
    #expect(large.gap == 6)
    #expect(large.textScale == .md)

    let medium = ResolvedButton.resolve(size: .medium).metrics
    #expect(medium.paddingVertical == 9)
    #expect(medium.paddingHorizontal == 28)

    let tiny = ResolvedButton.resolve(size: .tiny).metrics
    #expect(tiny.paddingVertical == 5)
    #expect(tiny.paddingHorizontal == 10)
    #expect(tiny.gap == 3)
    #expect(tiny.textScale == .xs)
    #expect(tiny.fontWeight == .semiBold)
  }

  @Test("Rectangular metrics carry a finite radius")
  func rectangularMetrics() {
    let large = ResolvedButton.resolve(size: .large, shape: .rectangular).metrics
    #expect(large.cornerRadius == 10)
    #expect(large.isCapsule == false)
    let tiny = ResolvedButton.resolve(size: .tiny, shape: .rectangular).metrics
    #expect(tiny.cornerRadius == 6)
  }

  @Test("Round shapes are circles at the RN side lengths")
  func roundMetrics() {
    #expect(ResolvedButton.resolve(size: .large, shape: .round).metrics.side == 44)
    #expect(ResolvedButton.resolve(size: .small, shape: .round).metrics.side == 33)
    #expect(ResolvedButton.resolve(size: .tiny, shape: .round).metrics.side == 25)
    // `round` has no radius because it clips to a circle.
    #expect(ResolvedButton.resolve(size: .tiny, shape: .round).metrics.cornerRadius == nil)
    // `square` uses `rounded_sm`, except the tiny step's 6pt.
    #expect(ResolvedButton.resolve(size: .small, shape: .square).metrics.cornerRadius == 8)
    #expect(ResolvedButton.resolve(size: .tiny, shape: .square).metrics.cornerRadius == 6)
  }

  @Test("Background resolution applies the RN fallbacks")
  func backgroundFallbacks() {
    let primary = ResolvedButton.resolve(color: .primary)
    #expect(primary.background(disabled: false, interacting: false) == .palette("primary_500"))
    #expect(primary.background(disabled: false, interacting: true) == .palette("primary_600"))
    #expect(primary.background(disabled: true, interacting: false) == .palette("primary_200"))
    // Disabled wins over interacting.
    #expect(primary.background(disabled: true, interacting: true) == .palette("primary_200"))
    #expect(primary.foreground(disabled: false) == .palette("white"))
    #expect(primary.foreground(disabled: true) == .atom("textInverted"))
  }
}

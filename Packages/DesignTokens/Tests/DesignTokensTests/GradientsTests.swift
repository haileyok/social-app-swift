import Testing

@testable import DesignTokens

/** Pins the eight gradient presets against `src/alf/tokens.ts`. */
@Suite struct GradientsTests {
  let g = GradientPreset.designTokens

  @Test func primary() {
    #expect(g.primary.colors == ["#054CFF", "#1085FE", "#1085FE", "#59B9FF"])
    #expect(g.primary.positions == [0, 0.4, 0.6, 1])
    #expect(g.primary.hoverColor == "#1085FE")
  }

  @Test func sky() {
    #expect(g.sky.colors == ["#0A7AFF", "#59B9FF"])
    #expect(g.sky.positions == [0, 1])
    #expect(g.sky.hoverColor == "#0A7AFF")
  }

  @Test func midnight() {
    #expect(g.midnight.colors == ["#022C5E", "#4079BC"])
    #expect(g.midnight.positions == [0, 1])
    #expect(g.midnight.hoverColor == "#022C5E")
  }

  @Test func sunrise() {
    #expect(g.sunrise.colors == ["#4E90AE", "#AEA3AB", "#E6A98F", "#F3A84C"])
    #expect(g.sunrise.positions == [0, 0.4, 0.8, 1])
    #expect(g.sunrise.hoverColor == "#AEA3AB")
  }

  @Test func sunset() {
    #expect(g.sunset.colors == ["#6772AF", "#B88BB6", "#FFA6AC"])
    #expect(g.sunset.positions == [0, 0.6, 1])
    #expect(g.sunset.hoverColor == "#B88BB6")
  }

  @Test func summer() {
    #expect(g.summer.colors == ["#FF6A56", "#FF9156", "#FFDD87"])
    #expect(g.summer.positions == [0, 0.3, 1])
    #expect(g.summer.hoverColor == "#FF9156")
  }

  @Test func nordic() {
    #expect(g.nordic.colors == ["#083367", "#9EE8C1"])
    #expect(g.nordic.positions == [0, 1])
    #expect(g.nordic.hoverColor == "#3A7085")
  }

  @Test func bonfire() {
    #expect(g.bonfire.colors == ["#203E4E", "#755B62", "#CD7765", "#EF956E"])
    #expect(g.bonfire.positions == [0, 0.4, 0.8, 1])
    #expect(g.bonfire.hoverColor == "#755B62")
  }

  @Test func allPresets() {
    #expect(g.all.count == 8)
    for gradient in g.all.values {
      #expect(gradient.stops.count >= 2)
      #expect(gradient.stops.first?.position == 0)
      #expect(gradient.stops.last?.position == 1)
    }
  }

  @Test func diagonalAxis() {
    #expect(GradientPreset.diagonalStart.x == 0)
    #expect(GradientPreset.diagonalStart.y == 0)
    #expect(GradientPreset.diagonalEnd.x == 1)
    #expect(GradientPreset.diagonalEnd.y == 1)
  }
}

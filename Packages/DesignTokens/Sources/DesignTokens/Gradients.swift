/**
 A linear-gradient preset. `stops` are `(position, hex)` pairs in the 0...1
 range; `hoverColor` is the single colour the RN app uses for hover states.
 */
public struct Gradient: Equatable, Sendable {
  public let stops: [(position: Double, color: String)]
  public let hoverColor: String

  /** Just the colours, in stop order. */
  public var colors: [String] { stops.map(\.color) }

  /** Just the stop positions, in order. */
  public var positions: [Double] { stops.map(\.position) }

  public static func == (lhs: Gradient, rhs: Gradient) -> Bool {
    lhs.hoverColor == rhs.hoverColor
      && lhs.stops.count == rhs.stops.count
      && zip(lhs.stops, rhs.stops).allSatisfy {
        $0.position == $1.position && $0.color == $1.color
      }
  }
}

/** The eight gradient presets from `src/alf/tokens.ts`. */
public struct GradientPreset: Sendable {
  public let primary: Gradient
  public let sky: Gradient
  public let midnight: Gradient
  public let sunrise: Gradient
  public let sunset: Gradient
  public let summer: Gradient
  public let nordic: Gradient
  public let bonfire: Gradient

  /** Every preset keyed by its ALF name, mirroring `tokens.gradients`. */
  public var all: [String: Gradient] {
    [
      "primary": primary, "sky": sky, "midnight": midnight, "sunrise": sunrise,
      "sunset": sunset, "summer": summer, "nordic": nordic, "bonfire": bonfire,
    ]
  }
}

extension GradientPreset {
  /**
   Gradient presets ported 1:1 from the RN app (`src/alf/tokens.ts`,
   `gradients`). These are app-level tokens, not part of `@bsky.app/alf`
   itself; the app consumes them via `GradientFill` and
   `LinearGradientBackground`.

   Neither the presets nor their consumers carry an angle: `GradientFill`
   uses `start=(0,0)`, `end=(1,1)` (a top-left to bottom-right diagonal),
   while `LinearGradientBackground` defaults to `sky` and `expo-linear-gradient`'s
   own default axis. The caller may pass `start`/`end` explicitly. We record
   only the stop positions and colours, which is all the token data holds.
   */
  public static let designTokens = GradientPreset(
    primary: Gradient(
      stops: [(0, "#054CFF"), (0.4, "#1085FE"), (0.6, "#1085FE"), (1, "#59B9FF")],
      hoverColor: "#1085FE"
    ),
    sky: Gradient(
      stops: [(0, "#0A7AFF"), (1, "#59B9FF")],
      hoverColor: "#0A7AFF"
    ),
    midnight: Gradient(
      stops: [(0, "#022C5E"), (1, "#4079BC")],
      hoverColor: "#022C5E"
    ),
    sunrise: Gradient(
      stops: [(0, "#4E90AE"), (0.4, "#AEA3AB"), (0.8, "#E6A98F"), (1, "#F3A84C")],
      hoverColor: "#AEA3AB"
    ),
    sunset: Gradient(
      stops: [(0, "#6772AF"), (0.6, "#B88BB6"), (1, "#FFA6AC")],
      hoverColor: "#B88BB6"
    ),
    summer: Gradient(
      stops: [(0, "#FF6A56"), (0.3, "#FF9156"), (1, "#FFDD87")],
      hoverColor: "#FF9156"
    ),
    nordic: Gradient(
      stops: [(0, "#083367"), (1, "#9EE8C1")],
      hoverColor: "#3A7085"
    ),
    bonfire: Gradient(
      stops: [(0, "#203E4E"), (0.4, "#755B62"), (0.8, "#CD7765"), (1, "#EF956E")],
      hoverColor: "#755B62"
    )
  )

  /**
   `GradientFill`'s axis: a top-left to bottom-right diagonal expressed as
   unit-square start/end points.
   */
  public static let diagonalStart: (x: Double, y: Double) = (0, 0)
  public static let diagonalEnd: (x: Double, y: Double) = (1, 1)
}

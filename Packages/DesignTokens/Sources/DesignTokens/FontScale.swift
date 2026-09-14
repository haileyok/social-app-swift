/**
 User font-scaling steps. The RN app stores a scale index and converts it to a
 multiplier that is applied to every resolved font size at render time
 (`src/alf/fonts.ts`, `computeFontScaleMultiplier`).
 */
public enum FontScale {
  /**
   The step between adjacent multipliers: `0.0625` (`1 - (15/16)`, per ALF's
   `factor`).
   */
  public static let step: Double = 0.0625

  /** The persisted scale index, matching `Device['fontScale']`. */
  public enum Step: String, Equatable, Sendable, CaseIterable {
    case minus2 = "-2"
    case minus1 = "-1"
    case zero = "0"
    case plus1 = "1"
    case plus2 = "2"
  }

  /**
   The multiplier for a step. Note ALF's implementation is deliberate: `-2`
   maps to `1 - step` (not `1 - 2 * step`) and `2` to `1 + step` (not
   `1 + 2 * step`); the extreme values are marked "unused" in the source and
   collapse onto their neighbours. Reproduced faithfully.
   */
  public static let multipliers: [Step: Double] = [
    .minus2: 1 - step,  // unused; same as -1
    .minus1: 1 - step,
    .zero: 1,  // default
    .plus1: 1 + step,
    .plus2: 1 + step,  // unused; same as +1
  ]

  /** The multiplier for a given step, equivalent to `computeFontScaleMultiplier`. */
  public static func multiplier(for step: Step) -> Double {
    multipliers[step] ?? 1
  }

  /// The multiplier applied to the `system` font family's letter spacing.
  public static let systemFontLetterSpacing: Double = 0.25
}

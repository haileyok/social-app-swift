/**
 Static measurement tokens ported 1:1 from `@bsky.app/alf@0.1.15`
 (`src/tokens.ts`). These are the theme-independent scales: spacing, type
 size, line height, corner radius, font weight and letter tracking.

 Values are plain data (points or unitless multipliers). Nothing in this
 package imports a UI framework so the whole surface is verifiable on Linux.
 */
public enum Scales {
  /**
   T-shirt spacing scale (`tokens.space`), in points.

   Note that ALF defines `_3xl`..`_5xl` beyond the `2xs`..`2xl` range the
   RN app documents; they are included here so the port is complete.
   */
  public enum Spacing {
    public static let xxs: Double = 2  // _2xs
    public static let xs: Double = 4
    public static let sm: Double = 8
    public static let md: Double = 12
    public static let lg: Double = 16
    public static let xl: Double = 20
    public static let xxl: Double = 24  // _2xl
    public static let xxxl: Double = 28  // _3xl
    public static let xxxxl: Double = 32  // _4xl
    public static let xxxxxl: Double = 40  // _5xl
  }

  /**
   Type size scale (`tokens.fontSize`), in points. These are the base sizes
   the RN app multiplies by the user font-scale multiplier at render time.
   */
  public enum FontSize {
    public static let xxs: Double = 9.4  // _2xs
    public static let xs: Double = 11.3
    public static let sm: Double = 13.1
    public static let md: Double = 15
    public static let lg: Double = 16.9
    public static let xl: Double = 18.8
    public static let xxl: Double = 20.6  // _2xl
    public static let xxxl: Double = 24.3  // _3xl
    public static let xxxxl: Double = 30  // _4xl
    public static let xxxxxl: Double = 37.5  // _5xl
  }

  /**
   Relative line heights (`tokens.lineHeight`). Values <= 2 are relative
   multipliers applied to the resolved font size; see ALF's
   `normalizeTextStyles`.
   */
  public enum LineHeight {
    public static let tight: Double = 1.15
    public static let snug: Double = 1.3
    public static let relaxed: Double = 1.5
  }

  /** Corner radius scale (`tokens.borderRadius`), in points. */
  public enum Radius {
    public static let xxs: Double = 2  // _2xs
    public static let xs: Double = 4
    public static let sm: Double = 8
    public static let md: Double = 12
    public static let lg: Double = 16
    public static let xl: Double = 20
    public static let full: Double = 999
  }

  /** Font weights (`tokens.fontWeight`), as CSS-style numeric strings. */
  public enum FontWeight {
    public static let normal = "400"
    public static let medium = "500"
    public static let semiBold = "600"
    public static let bold = "700"
  }

  /**
   Letter tracking (`tokens.TRACKING`), applied uniformly by ALF's text
   atoms. The RN app overrides this to `0.25` for the `system` font family
   only (see `src/alf/fonts.ts`); the token itself is `0`.
   */
  public static let tracking: Double = 0
}

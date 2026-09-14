#if canImport(SwiftUI)
import CoreText
import DesignSystemCore
import DesignTokens
import SwiftUI

/**
 Registers the bundled Inter variable font with the process-wide font manager.

 `Resources/InterVariable.ttf` is the SIL OFL licensed variable font (weights
 100-900, optical size axis 14-32; see the package README for provenance). It is
 registered once, lazily, the first time a themed `Font` is built. If
 registration fails for any reason the typography falls back to the system font,
 so a missing resource degrades instead of crashing.
 */
public enum InterFontRegistry {
  /** The PostScript name and the name `Font.custom` should be given. */
  public static let postScriptName = "InterVariable"

  /** The family name recorded in the font's `name` table. */
  public static let familyName = "Inter Variable"

  /**
   True when the bundled font registered successfully. Reading this triggers
   the (one-time) registration.
   */
  public static var isAvailable: Bool { registrationSucceeded }

  /**
   Registers the bundled font if it has not been registered yet. Idempotent:
   the registration runs at most once per process.
   */
  @discardableResult
  public static func registerIfNeeded() -> Bool {
    registrationSucceeded
  }

  private static let registrationSucceeded: Bool = {
    var registeredAny = false
    for name in ["InterVariable", "InterVariable-Italic"] {
      guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
      var error: Unmanaged<CFError>?
      let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
      if ok {
        registeredAny = true
      }
      if let error {
        // Already-registered fonts report an error; that is not a failure.
        let code = CFErrorGetCode(error.takeUnretainedValue())
        if code == CTFontManagerError.alreadyRegistered.rawValue {
          registeredAny = true
        }
      }
    }
    return registeredAny
  }()
}

/**
 A step of ALF's type scale (`atoms.text_2xs` ... `atoms.text_5xl`).

 Each step carries its base size and the relative line height ALF pairs with it
 in the RN app: body-ish steps use the default leading, headings use `snug`.
 */
public enum TypeScale: String, Equatable, Sendable, CaseIterable {
  case xxs
  case xs
  case sm
  case md
  case lg
  case xl
  case xxl
  case xxxl
  case xxxxl
  case xxxxxl

  /** Base size in points, from `Scales.FontSize` (before font scaling). */
  public var size: Double {
    switch self {
    case .xxs: Scales.FontSize.xxs
    case .xs: Scales.FontSize.xs
    case .sm: Scales.FontSize.sm
    case .md: Scales.FontSize.md
    case .lg: Scales.FontSize.lg
    case .xl: Scales.FontSize.xl
    case .xxl: Scales.FontSize.xxl
    case .xxxl: Scales.FontSize.xxxl
    case .xxxxl: Scales.FontSize.xxxxl
    case .xxxxxl: Scales.FontSize.xxxxxl
    }
  }

  /**
   The relative line height ALF's text atoms pair with this step. The small
   steps use the default `snug` leading; display steps tighten to `tight`.
   */
  public var relativeLineHeight: Double {
    switch self {
    case .xxs, .xs, .sm, .md, .lg, .xl, .xxl, .xxxl: Scales.LineHeight.snug
    case .xxxxl, .xxxxxl: Scales.LineHeight.tight
    }
  }

  /** The Dynamic Type style the step scales relative to. */
  public var textStyle: Font.TextStyle {
    switch self {
    case .xxs: .caption2
    case .xs: .caption
    case .sm: .footnote
    case .md: .body
    case .lg: .callout
    case .xl: .title3
    case .xxl: .title2
    case .xxxl: .title
    case .xxxxl, .xxxxxl: .largeTitle
    }
  }

  /**
   Resolves this step through the pure core, applying the font-scale
   multiplier, the weight token and the family-specific tracking rule
   (Inter uses the ALF tracking of `0`; the system family overrides to `0.25`).
   */
  public func metrics(
    fontScale: Double = 1,
    family: FontFamilyPreference = .theme,
    weight: String = Scales.FontWeight.normal
  ) -> TextMetrics {
    TextMetrics.resolve(
      size: size,
      relativeLineHeight: relativeLineHeight,
      fontScale: fontScale,
      weight: weight,
      tracking: family == .system ? FontScale.systemFontLetterSpacing : Scales.tracking)
  }

  /**
   The SwiftUI `Font` for this step.

   - `respectsDynamicType` (default true) makes the size scale with the user's
     Dynamic Type setting relative to `textStyle`; this is an intentional
     addition over the RN app, which only honors its own font-scale preference.
     The ALF multiplier from `fontScale` is applied either way.
   */
  public func font(
    fontScale: Double = 1,
    family: FontFamilyPreference = .theme,
    weight: String = Scales.FontWeight.normal,
    respectsDynamicType: Bool = true
  ) -> Font {
    let resolved = metrics(fontScale: fontScale, family: family, weight: weight)
    let fontWeight = Font.Weight(resolved.weight)
    switch family {
    case .theme where InterFontRegistry.isAvailable:
      if respectsDynamicType {
        return Font.custom(
          InterFontRegistry.postScriptName, size: resolved.size, relativeTo: textStyle
        )
        .weight(fontWeight)
      }
      return Font.custom(InterFontRegistry.postScriptName, size: resolved.size)
        .weight(fontWeight)
    case .theme, .system:
      if respectsDynamicType {
        return Font.system(textStyle, design: .default).weight(fontWeight)
      }
      return Font.system(size: resolved.size, weight: fontWeight)
    }
  }
}

extension Font.Weight {
  /**
   Builds a `Font.Weight` from a numeric weight. Only the four ALF tokens have
   named cases; other values are matched to the nearest named case, so a
   variable-font weight stays in the 400/500/600/700 family.
   */
  public init(_ numericWeight: Int) {
    switch numericWeight {
    case ..<450: self = .regular
    case ..<550: self = .medium
    case ..<650: self = .semibold
    default: self = .bold
    }
  }
}

extension Font {
  /**
   Builds a themed font in one call, reading nothing from the environment. Use
   the `View` helpers (`themedFont(_:weight:)`) inside views so the injected
   theme and font preferences apply.
   */
  public static func alf(
    _ scale: TypeScale,
    weight: String = Scales.FontWeight.normal,
    fontScale: Double = 1,
    family: FontFamilyPreference = .theme
  ) -> Font {
    scale.font(fontScale: fontScale, family: family, weight: weight)
  }
}
#endif

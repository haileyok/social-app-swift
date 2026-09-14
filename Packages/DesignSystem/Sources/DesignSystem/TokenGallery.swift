#if canImport(SwiftUI)
import DesignSystemCore
import DesignTokens
import SwiftUI

/**
 The internal token gallery: palette swatches, type samples, the spacing ladder
 and gradient presets, rendered for one theme.

 Not shipped UI. It exists so the screenshot loop can render the tokens on a
 device and so a reviewer can eyeball a theme change. Wrap it in `.theme(...)`
 to inspect a theme:

 ```swift
 TokenGallery(theme: .dim)
 TokenGallery(themeName: .light)
 ```
 */
public struct TokenGallery: View {
  private let theme: Theme

  public init(theme: Theme) {
    self.theme = theme
  }

  public init(themeName: ThemeName) {
    self.theme = ThemeResolver.theme(for: themeName)
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.xl) {
        header
        paletteSection
        atomSection
        typeSection
        spacingSection
        radiusSection
        gradientSection
        shadowSection
        breakpointSection
      }
      .padding(Spacing.lg)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(theme.atomColors.bg)
    .theme(theme)
  }

  // MARK: - Sections

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      AlfText("ALF tokens — \(theme.name.rawValue)", scale: .xxl, weight: Scales.FontWeight.bold)
      AlfText(
        "scheme \(theme.scheme.rawValue) · shadow opacity \(formatted(theme.shadowOpacity))",
        scale: .sm, color: theme.atomColors.textContrastMedium)
      AlfText(
        InterFontRegistry.isAvailable ? "Inter variable font loaded" : "Inter unavailable — system fallback",
        scale: .xs, color: theme.atomColors.textContrastLow)
    }
  }

  private var paletteSection: some View {
    GallerySection("Palette") {
      ForEach(PaletteSwatch.groups(palette: theme.colors), id: \.name) { group in
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          AlfText(group.name, scale: .xs, color: theme.atomColors.textContrastMedium)
          HStack(spacing: 0) {
            ForEach(group.swatches) { swatch in
              Rectangle()
                .fill(swatch.color)
                .frame(height: 36)
                .accessibilityLabel(Text(swatch.name))
            }
          }
          .clipShape(.rect(cornerRadius: Radius.sm, style: .continuous))
        }
      }
    }
  }

  private var atomSection: some View {
    GallerySection("Semantic atoms") {
      let atoms = theme.atomColors
      let pairs: [(String, Color)] = [
        ("text", atoms.text), ("textLink", atoms.textLink),
        ("textContrastLow", atoms.textContrastLow), ("textContrastMedium", atoms.textContrastMedium),
        ("textContrastHigh", atoms.textContrastHigh), ("textInverted", atoms.textInverted),
        ("bg", atoms.bg), ("bgContrast100", atoms.bgContrast100), ("bgContrast500", atoms.bgContrast500),
        ("bgContrast900", atoms.bgContrast900), ("borderContrastLow", atoms.borderContrastLow),
        ("borderContrastMedium", atoms.borderContrastMedium),
      ]
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: Spacing.sm) {
        ForEach(pairs, id: \.0) { entry in
          HStack(spacing: Spacing.xs) {
            RoundedRectangle(cornerRadius: Radius.xs)
              .fill(entry.1)
              .frame(width: 20, height: 20)
              .overlay(RoundedRectangle(cornerRadius: Radius.xs).strokeBorder(theme.atomColors.borderContrastLow))
            AlfText(entry.0, scale: .xs, color: theme.atomColors.textContrastMedium)
          }
        }
      }
    }
  }

  private var typeSection: some View {
    GallerySection("Type scale") {
      ForEach(TypeScale.allCases, id: \.self) { scale in
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
          AlfText(label(for: scale), scale: .xs, color: theme.atomColors.textContrastLow)
            .frame(width: 68, alignment: .leading)
          AlfText("The quick brown fox 0123", scale: scale)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        ForEach(
          [(Scales.FontWeight.normal, "normal"), (Scales.FontWeight.medium, "medium"),
           (Scales.FontWeight.semiBold, "semiBold"), (Scales.FontWeight.bold, "bold")],
          id: \.0
        ) { entry in
          AlfText("\(entry.1) (\(entry.0))", scale: .md, weight: entry.0)
        }
      }
    }
  }

  private var spacingSection: some View {
    GallerySection("Spacing ladder") {
      ForEach(Spacing.Step.allCases, id: \.self) { step in
        HStack(spacing: Spacing.sm) {
          AlfText("\(name(for: step)) · \(formatted(step.value))", scale: .xs, color: theme.atomColors.textContrastMedium)
            .frame(width: 110, alignment: .leading)
          Rectangle()
            .fill(theme.colors.primary500)
            .frame(width: step.value, height: 12)
        }
      }
    }
  }

  private var radiusSection: some View {
    GallerySection("Radius") {
      HStack(spacing: Spacing.md) {
        ForEach(Radius.Step.allCases, id: \.self) { step in
          VStack(spacing: Spacing.xxs) {
            RoundedRectangle(cornerRadius: min(step.value, 20))
              .fill(theme.colors.primary200)
              .frame(width: 44, height: 44)
            AlfText(name(for: step), scale: .xxs, color: theme.atomColors.textContrastMedium)
          }
        }
      }
    }
  }

  private var gradientSection: some View {
    GallerySection("Gradients") {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: Spacing.sm) {
        ForEach(GradientName.allCases, id: \.self) { name in
          VStack(alignment: .leading, spacing: Spacing.xxs) {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
              .fill(name.linearGradient)
              .frame(height: 56)
            AlfText(name.rawValue, scale: .xs, color: theme.atomColors.textContrastMedium)
          }
        }
      }
    }
  }

  private var shadowSection: some View {
    GallerySection("Shadows") {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: Spacing.lg) {
        ForEach(DesignSystemCore.ShadowGeometry.Size.allCases, id: \.self) { size in
          VStack(spacing: Spacing.xxs) {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
              .fill(theme.atomColors.bgContrast100)
              .alfShadow(size)
              .frame(height: 64)
            let resolved = theme.shadow(size)
            AlfText(
              "\(size.rawValue) · r\(formatted(resolved.radius)) y\(formatted(resolved.offsetY)) α\(formatted(resolved.alpha))",
              scale: .xxs, color: theme.atomColors.textContrastMedium)
          }
        }
      }
      .padding(.vertical, Spacing.sm)
    }
  }

  private var breakpointSection: some View {
    GallerySection("Breakpoints") {
      let widths: [Double] = [390, 500, 800, 1100, 1300, 1600]
      ForEach(widths, id: \.self) { width in
        let bp = ScreenBreakpoints(width: width, isRegularWidth: width >= 500)
        AlfText(
          "\(Int(width))pt · active \(bp.active?.rawValue ?? "none")",
          scale: .xs, color: theme.atomColors.textContrastMedium)
      }
    }
  }

  // MARK: - Helpers

  private func label(for scale: TypeScale) -> String {
    "\(name(for: scale)) \(formatted(scale.size))"
  }

  private func name(for scale: TypeScale) -> String {
    switch scale {
    case .xxs: "2xs"
    case .xs: "xs"
    case .sm: "sm"
    case .md: "md"
    case .lg: "lg"
    case .xl: "xl"
    case .xxl: "2xl"
    case .xxxl: "3xl"
    case .xxxxl: "4xl"
    case .xxxxxl: "5xl"
    }
  }

  private func name(for step: Spacing.Step) -> String {
    switch step {
    case .xxs: "2xs"
    case .xs: "xs"
    case .sm: "sm"
    case .md: "md"
    case .lg: "lg"
    case .xl: "xl"
    case .xxl: "2xl"
    case .xxxl: "3xl"
    case .xxxxl: "4xl"
    case .xxxxxl: "5xl"
    }
  }

  private func name(for step: Radius.Step) -> String {
    step == .full ? "full" : "\(step)"
  }

  private func formatted(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.3f", value)
  }
}

/** A titled block in the gallery. */
struct GallerySection<Content: View>: View {
  private let title: String
  private let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  @Environment(\.alfTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      AlfText(title, scale: .lg, weight: Scales.FontWeight.semiBold)
      VStack(alignment: .leading, spacing: Spacing.sm) { content }
        .padding(Spacing.md)
        .background(theme.atomColors.bgContrast50)
        .clipShape(.rect(cornerRadius: Radius.md, style: .continuous))
    }
  }
}

/** One palette ramp rendered as a swatch strip. */
struct PaletteSwatch: Identifiable {
  let name: String
  let color: Color
  var id: String { name }

  struct Group: Identifiable {
    let name: String
    let swatches: [PaletteSwatch]
    var id: String { name }
  }

  static func groups(palette: PaletteColors) -> [Group] {
    [
      Group(name: "contrast", swatches: [
        PaletteSwatch(name: "contrast0", color: palette.contrast0),
        PaletteSwatch(name: "contrast100", color: palette.contrast100),
        PaletteSwatch(name: "contrast200", color: palette.contrast200),
        PaletteSwatch(name: "contrast400", color: palette.contrast400),
        PaletteSwatch(name: "contrast600", color: palette.contrast600),
        PaletteSwatch(name: "contrast800", color: palette.contrast800),
        PaletteSwatch(name: "contrast1000", color: palette.contrast1000),
      ]),
      Group(name: "primary", swatches: [
        PaletteSwatch(name: "primary25", color: palette.primary25),
        PaletteSwatch(name: "primary100", color: palette.primary100),
        PaletteSwatch(name: "primary300", color: palette.primary300),
        PaletteSwatch(name: "primary500", color: palette.primary500),
        PaletteSwatch(name: "primary700", color: palette.primary700),
        PaletteSwatch(name: "primary900", color: palette.primary900),
        PaletteSwatch(name: "primary975", color: palette.primary975),
      ]),
      Group(name: "positive", swatches: [
        PaletteSwatch(name: "positive25", color: palette.positive25),
        PaletteSwatch(name: "positive300", color: palette.positive300),
        PaletteSwatch(name: "positive500", color: palette.positive500),
        PaletteSwatch(name: "positive700", color: palette.positive700),
        PaletteSwatch(name: "positive975", color: palette.positive975),
      ]),
      Group(name: "negative", swatches: [
        PaletteSwatch(name: "negative25", color: palette.negative25),
        PaletteSwatch(name: "negative300", color: palette.negative300),
        PaletteSwatch(name: "negative500", color: palette.negative500),
        PaletteSwatch(name: "negative700", color: palette.negative700),
        PaletteSwatch(name: "negative975", color: palette.negative975),
      ]),
      Group(name: "brand", swatches: [
        PaletteSwatch(name: "pink", color: palette.pink),
        PaletteSwatch(name: "yellow", color: palette.yellow),
        PaletteSwatch(name: "white", color: palette.white),
        PaletteSwatch(name: "black", color: palette.black),
      ]),
    ]
  }
}

#if DEBUG
#Preview("Light") { TokenGallery(themeName: .light) }
#Preview("Dark") { TokenGallery(themeName: .dark) }
#Preview("Dim") { TokenGallery(themeName: .dim) }
#endif
#endif

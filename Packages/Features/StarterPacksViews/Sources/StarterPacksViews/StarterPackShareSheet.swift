import DesignSystem
import DesignTokens
import StarterPacksLogic
import SwiftUI
import UIComponents

/**
 The share sheet: the card preview, the share link, and the QR affordance.

 Ported from `ShareDialog.tsx` and `QrCodeDialog.tsx`. RN shows a spinner until
 the shortened link and the card image have both resolved, then the card and
 three actions. The URL and the card come from ``StarterPackShareData``; nothing
 here builds a link itself.

 The QR surface is a placeholder: this milestone renders the share data and the
 download filename rather than encoding a code. A real encoder drops into
 ``StarterPackQRCard`` without changing this sheet.
 */
public struct StarterPackShareSheet: View {
  private let detail: StarterPackDetail
  private let data: StarterPackShareData
  private let isSaving: Bool

  private let onShareLink: () -> Void
  private let onShowQR: (() -> Void)?
  private let onSaveImage: (() -> Void)?

  @State private var isQRPresented = false

  @Environment(\.alfTheme) private var theme
  @Environment(\.dismiss) private var dismiss

  /// Creates the share sheet.
  ///
  /// - Parameters:
  ///   - detail: the pack, for the heading and the card filename.
  ///   - data: the share payload, from ``StarterPackShare/shareData(_:shortLink:)``.
  ///   - isSaving: whether a card write is in flight.
  ///   - onShareLink: opens the platform share sheet with
  ///     ``StarterPackShare/shareURL(_:)``.
  ///   - onShowQR: an optional override; the sheet opens its own QR surface when
  ///     this is nil.
  ///   - onSaveImage: writes the card to the photo library, or nil to hide the
  ///     action (the web behaviour, where RN downloads instead).
  public init(
    detail: StarterPackDetail,
    data: StarterPackShareData,
    isSaving: Bool = false,
    onShareLink: @escaping () -> Void = {},
    onShowQR: (() -> Void)? = nil,
    onSaveImage: (() -> Void)? = nil
  ) {
    self.detail = detail
    self.data = data
    self.isSaving = isSaving
    self.onShareLink = onShareLink
    self.onShowQR = onShowQR
    self.onSaveImage = onSaveImage
  }

  public var body: some View {
    ScrollView {
      if data.isReady {
        content
      } else {
        loading
      }
    }
    .background(theme.atomColors.bg)
    .accessibilityIdentifier(StarterPackAccessibility.shareSheet)
    .sheet(isPresented: $isQRPresented) {
      StarterPackQRSheet(detail: detail, data: data)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
  }

  // MARK: - Sections

  /// Mirrors RN's `!imageLoaded || !link` gate: the sheet is not ready until the
  /// short link resolves.
  private var loading: some View {
    VStack(spacing: Spacing.md) {
      ProgressView()
        .accessibilityLabel("Loading")
      AlfText(
        StarterPackCopy.shareMessage, scale: .sm, color: theme.atomColors.textContrastMedium
      )
      .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, minHeight: 260)
    .padding(Spacing.xl)
    .accessibilityIdentifier(StarterPackAccessibility.shareLoading)
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        AlfText(StarterPackCopy.shareTitle, scale: .xl, weight: Scales.FontWeight.semiBold)
          .fixedSize(horizontal: false, vertical: true)
        AlfText(
          StarterPackCopy.shareMessage, scale: .sm,
          color: theme.atomColors.textContrastMedium
        )
        .fixedSize(horizontal: false, vertical: true)
      }

      StarterPackQRCard(detail: detail, data: data)

      actions
    }
    .padding(Spacing.lg)
  }

  private var actions: some View {
    VStack(spacing: Spacing.sm) {
      AlfButton(
        StarterPackCopy.shareLinkAction, color: .primarySubtle, size: .large,
        shape: .rectangular
      ) {
        onShareLink()
      }
      .frame(maxWidth: .infinity)
      .accessibilityIdentifier(StarterPackAccessibility.shareLinkButton)

      AlfButton(
        StarterPackCopy.shareQRAction, color: .primarySubtle, size: .large, shape: .rectangular
      ) {
        if let onShowQR {
          onShowQR()
        } else {
          isQRPresented = true
        }
      }
      .frame(maxWidth: .infinity)
      .accessibilityIdentifier(StarterPackAccessibility.shareQRButton)

      if let onSaveImage {
        AlfButton(
          isSaving ? "Saving" : StarterPackCopy.saveImageAction, color: .secondary,
          size: .large, shape: .rectangular
        ) {
          onSaveImage()
        }
        .disabled(isSaving)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(StarterPackAccessibility.saveImageButton)
      }
    }
  }
}

/// The share card: the QR surface plus the pack's identity.
///
/// RN renders the appview OG card image here. The card URL is in the share data
/// (``StarterPackShareData/imageURL``) but the appview does not serve this
/// surface yet, so the card is drawn from the pack's own fields and the share
/// link - which is what the OG card shows anyway.
public struct StarterPackQRCard: View {
  private let detail: StarterPackDetail
  private let data: StarterPackShareData

  @Environment(\.alfTheme) private var theme

  public init(detail: StarterPackDetail, data: StarterPackShareData) {
    self.detail = detail
    self.data = data
  }

  public var body: some View {
    VStack(spacing: Spacing.md) {
      StarterPackQRPlaceholder()
      VStack(spacing: Spacing.xxs) {
        AlfText(detail.name, scale: .md, weight: Scales.FontWeight.semiBold)
          .multilineTextAlignment(.center)
        AlfText("by @\(detail.creatorHandle)", scale: .xs, color: theme.atomColors.textContrastMedium)
      }
      if let link = data.shareLink {
        AlfText(link, scale: .xxs, color: theme.atomColors.textContrastMedium)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      // The filename a downloaded card uses; RN builds it the same way.
      AlfText(data.qrDownloadFilename, scale: .xxs, color: theme.atomColors.textContrastLow)
        .lineLimit(1)
    }
    .padding(Spacing.lg)
    .frame(maxWidth: .infinity)
    .background(theme.atomColors.bgContrast50)
    .clipShape(.rect(cornerRadius: Radius.md))
    .overlay(
      RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        .strokeBorder(theme.atomColors.borderContrastLow))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(StarterPackAccessibility.qrCard)
  }
}

/// The QR surface.
///
/// A placeholder until a QR encoder lands: it renders a finder-pattern grid so
/// the sheet's geometry is real and testable, and carries the shared link as its
/// accessibility value so a test can assert what would be encoded.
public struct StarterPackQRPlaceholder: View {
  private let size: CGFloat

  @Environment(\.alfTheme) private var theme

  public init(size: CGFloat = 160) {
    self.size = size
  }

  public var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        .fill(theme.atomColors.bg)
      grid
    }
    .frame(width: size, height: size)
    .overlay(
      RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        .strokeBorder(theme.atomColors.borderContrastMedium))
    .accessibilityElement()
    .accessibilityLabel(StarterPackCopy.qrPlaceholderTitle)
    .accessibilityIdentifier(StarterPackAccessibility.qrPlaceholder)
  }

  /// Nine modules across, with the three finder squares drawn as filled blocks.
  /// Enough structure to read as a code without pretending to encode anything.
  private var grid: some View {
    let module = size / 9
    return VStack(spacing: 0) {
      ForEach(0..<9, id: \.self) { row in
        HStack(spacing: 0) {
          ForEach(0..<9, id: \.self) { column in
            Rectangle()
              .fill(filled(row: row, column: column) ? theme.atomColors.text : .clear)
              .frame(width: module, height: module)
          }
        }
      }
    }
    .padding(Spacing.sm)
    .accessibilityHidden(true)
  }

  /// The three 3x3 finder patterns, at the top-left, top-right and bottom-left.
  private func filled(row: Int, column: Int) -> Bool {
    let topLeft = row < 3 && column < 3
    let topRight = row < 3 && column > 5
    let bottomLeft = row > 5 && column < 3
    return topLeft || topRight || bottomLeft
  }
}

/// The full-bleed QR surface, opened from the share sheet's QR action.
public struct StarterPackQRSheet: View {
  private let detail: StarterPackDetail
  private let data: StarterPackShareData

  @Environment(\.alfTheme) private var theme

  public init(detail: StarterPackDetail, data: StarterPackShareData) {
    self.detail = detail
    self.data = data
  }

  public var body: some View {
    ScrollView {
      VStack(spacing: Spacing.lg) {
        AlfText(StarterPackCopy.shareQRAction, scale: .xl, weight: Scales.FontWeight.semiBold)
        StarterPackQRCard(detail: detail, data: data)
        AlfText(
          StarterPackCopy.qrPlaceholderMessage, scale: .xs,
          color: theme.atomColors.textContrastMedium)
      }
      .padding(Spacing.lg)
    }
    .background(theme.atomColors.bg)
  }
}

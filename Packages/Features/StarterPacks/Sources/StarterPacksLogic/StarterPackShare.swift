import Foundation
import Lexicons

/// What a QR code encodes, and what a share sheet opens.
///
/// Port of `QrCodeDialog` + `QrCode.tsx` + `ShareDialog`'s data flow: the screen
/// shortens the pack link, then hands the short link to the QR renderer and to
/// the share sheet.
public struct StarterPackShareData: Sendable, Equatable {
  /// The short link the app shares and encodes. RN's `useShortenLink` result.
  ///
  /// This is the value every share affordance uses; it is `nil` until the
  /// shorten call resolves, which is why RN renders a spinner until then.
  public let shareLink: String?
  /// The long app share link the shorten call is made against. Never nil.
  public let longLink: String
  /// The card image the share dialog previews and `saveImageToAlbum` writes.
  public let imageURL: String
  /// The filename a web download of the QR card uses.
  ///
  /// Port of `QrCodeDialog`'s `${record.name.replaceAll(' ', '_')}_Share_Card.png`.
  public let qrDownloadFilename: String

  /// Creates the share data.
  public init(
    shareLink: String?, longLink: String, imageURL: String, qrDownloadFilename: String
  ) {
    self.shareLink = shareLink
    self.longLink = longLink
    self.imageURL = imageURL
    self.qrDownloadFilename = qrDownloadFilename
  }

  /// Whether the dialog is still waiting on the short link.
  ///
  /// Port of the `!imageLoaded || !link` gate that shows the loader.
  public var isReady: Bool { shareLink != nil }
}

/// Builds the share and QR payloads for a pack.
///
/// The share link is derived from the pack's record, and the card image from the
/// creator's DID, matching `makeStarterPackLink` and `getStarterPackOgCard`.
public enum StarterPackShare {
  /// Builds the share data for a pack detail.
  ///
  /// - Parameters:
  ///   - detail: the pack.
  ///   - shortLink: the resolved `go.bsky.app` short link, or nil while it is
  ///     still being fetched.
  public static func shareData(_ detail: StarterPackDetail, shortLink: String? = nil)
    -> StarterPackShareData {
    let longLink = StarterPackURI.appShareLink(name: detail.creatorHandle, rkey: detail.rkey)
    return StarterPackShareData(
      shareLink: shortLink,
      longLink: longLink,
      imageURL: StarterPackURI.ogCardURL(creatorDID: detail.creatorDID, rkey: detail.rkey),
      qrDownloadFilename: qrDownloadFilename(packName: detail.name))
  }

  /// The filename a downloaded QR card uses.
  ///
  /// Port of `${record.name.replaceAll(' ', '_')}_Share_Card.png`. Only spaces
  /// are replaced; every other character is kept, matching RN.
  public static func qrDownloadFilename(packName: String) -> String {
    "\(packName.replacingOccurrences(of: " ", with: "_"))_Share_Card.png"
  }

  /// The URL a share sheet opens, or nil when the short link has not resolved.
  ///
  /// On web RN copies the link and toasts; on native it opens the share sheet.
  /// Both consume the same string, so the builder returns the string and the
  /// caller picks the affordance.
  public static func shareURL(_ data: StarterPackShareData) -> String? { data.shareLink }

  /// Whether a pack's share affordance should be offered.
  ///
  /// The share dialog is reachable only for a valid pack with a creator and a
  /// rkey, which is what the screen's `onOpenShareDialog` assumes when it builds
  /// the link.
  public static func canShare(_ detail: StarterPackDetail) -> Bool {
    !detail.creatorHandle.isEmpty && !detail.rkey.isEmpty
  }
}

/// The landing screen's derived state.
///
/// Port of `StarterPackLandingScreen`'s `isValid` gate and its follow copy. The
/// screen is the logged-out entry point, so it reads the same pack view the
/// signed-in screen does.
public struct StarterPackLandingState: Sendable {
  /// The pack's detail.
  public let detail: StarterPackDetail
  /// The members the screen previews, capped and labeler-filtered.
  public let sample: [App.Bsky.GraphDefs_ListItemView]
  /// The follow-count copy.
  public let followCopy: LandingFollowCopy
  /// The creator's handle, for the "Starter Pack by @handle" line.
  public let creatorHandle: String
  /// The pack name, for the header.
  public let name: String
  /// The description, rendered as rich text by the screen.
  public let description: String?

  /// Creates the landing state.
  public init(
    detail: StarterPackDetail,
    sample: [App.Bsky.GraphDefs_ListItemView],
    followCopy: LandingFollowCopy
  ) {
    self.detail = detail
    self.sample = sample
    self.followCopy = followCopy
    self.creatorHandle = detail.creatorHandle
    self.name = detail.name
    self.description = detail.description
  }
}

extension StarterPackViewBuilder {
  /// Whether the landing screen accepts this view.
  ///
  /// Port of `StarterPackLandingScreen`'s `isValid`: a full view with a backing
  /// list and a parsed starter-pack record. Unlike the signed-in screen, the
  /// list is required even for the creator.
  public static func landingIsValid(_ view: App.Bsky.GraphDefs_StarterPackView) -> Bool {
    view.list != nil && view.record.starterPackRecord != nil
  }

  /// Builds the landing state for a view, or nil when the view is not usable.
  public static func landingState(
    _ view: App.Bsky.GraphDefs_StarterPackView
  ) -> StarterPackLandingState? {
    guard landingIsValid(view) else { return nil }
    let detail = detail(view)
    return StarterPackLandingState(
      detail: detail,
      sample: landingSample(detail),
      followCopy: landingFollowCopy(detail))
  }
}

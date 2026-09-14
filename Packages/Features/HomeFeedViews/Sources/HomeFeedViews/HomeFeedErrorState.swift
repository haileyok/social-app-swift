import DesignSystem
import SwiftUI
import UIComponents

/// The Home feed's error surfaces.
///
/// `HomeFeedLogic` classifies a failure into ``HomeFeedLogic/HomeFeedError`` -
/// the port of `PostFeedErrorMessage`'s `KnownError` branches plus the network
/// case. This view maps that classification onto the shared `ErrorStateView`
/// copy and distinguishes a first-page failure (full surface) from a pagination
/// failure over existing content (an inline row).
public struct HomeFeedErrorState: View {
  private let error: HomeFeedError
  private let hasContent: Bool
  private let retry: () -> Void

  public init(error: HomeFeedError, hasContent: Bool = false, retry: @escaping () -> Void) {
    self.error = error
    self.hasContent = hasContent
    self.retry = retry
  }

  public var body: some View {
    if hasContent {
      RetryRow(message: message, retry: retry)
    } else {
      ErrorStateView(
        title: title, message: message, retryLabel: HomeFeedStrings.retry, retry: retry)
    }
  }

  /// The error's title, per classification.
  public var title: String {
    switch error {
    case .network: return HomeFeedStrings.errorNetworkTitle
    case .service: return HomeFeedStrings.errorServiceTitle
    case .signedInOnly: return HomeFeedStrings.errorSignedInOnlyTitle
    case .unknown: return HomeFeedStrings.errorUnknownTitle
    }
  }

  /// The error's body. A service error carries the appview's own message where
  /// it had one, so the user sees the real reason rather than generic copy.
  public var message: String {
    switch error {
    case .network:
      return HomeFeedStrings.errorNetworkMessage
    case .service(let detail):
      return detail ?? HomeFeedStrings.errorServiceMessage
    case .signedInOnly:
      return HomeFeedStrings.errorSignedInOnlyMessage
    case .unknown(let detail):
      return detail ?? HomeFeedStrings.errorUnknownMessage
    }
  }
}

#Preview {
  VStack {
    HomeFeedErrorState(error: .network) {}
    HomeFeedErrorState(error: .service(message: nil)) {}
  }
  .theme(.light)
}

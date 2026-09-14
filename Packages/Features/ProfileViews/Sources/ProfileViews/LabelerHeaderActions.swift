import DesignSystem
import DesignTokens
import ProfileLogic
import SwiftUI
import UIComponents

/// The action row of the labeler header variant.
///
/// Port of `HeaderLabelerButtons` in `ProfileHeaderLabeler.tsx`: edit-profile for
/// the owner, otherwise a subscribe toggle and a like control, with the message
/// button that the standard header also carries. Which of them render is decided
/// by ``LabelerProfileViewData``, so this view only draws the derived set.
public struct LabelerHeaderActions: View {
  private let labeler: LabelerProfileViewData
  private let strings: any ProfileStrings
  private let onAction: (ProfileHeaderAction) -> Void

  public init(
    labeler: LabelerProfileViewData,
    strings: any ProfileStrings = defaultProfileStrings,
    onAction: @escaping (ProfileHeaderAction) -> Void = { _ in }
  ) {
    self.labeler = labeler
    self.strings = strings
    self.onAction = onAction
  }

  public var body: some View {
    HStack(spacing: Spacing.sm) {
      if labeler.showsEditProfileButton {
        AlfButton(strings.editProfile, color: .secondary, size: .small) {
          onAction(.editProfile)
        }
      }
      if labeler.showsSubscribeButton {
        AlfButton(
          labeler.isSubscribed ? "Unsubscribe" : "Subscribe",
          color: labeler.isSubscribed ? .secondary : .primary,
          size: .small
        ) {
          onAction(.toggleLabelerSubscription( subscribed: labeler.isSubscribed))
        }
      }
      if labeler.showsLikeButton {
        AlfButton("Like", color: .secondary, size: .small) {
          onAction(.toggleLabelerLike(liked: labeler.likeURI != nil))
        }
        .disabled(!labeler.canLike)
      }
      Spacer(minLength: 0)
    }
  }
}

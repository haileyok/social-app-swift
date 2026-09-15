import DesignSystem
import DesignTokens
import Lexicons
import Moderation
import ModerationUILogic
import SwiftUI
import UIComponents

/// One row in the labeler directory.
///
/// A flattened projection of the labeler views the app has loaded, so the screen
/// does not need to know which of ``LabelerService``'s three reads produced it.
/// The subscription state and the cap decision still come from that package.
public struct LabelerRowModel: Equatable, Sendable, Identifiable {
  /// The labeler's did, which is also the row identity.
  public let did: String
  /// The labeler's display title.
  public let title: String
  /// The labeler's handle.
  public let handle: String
  /// The labeler's description, when it has one.
  public let description: String?
  /// Whether the viewer is subscribed.
  public let isSubscribed: Bool
  /// Whether the viewer may change the subscription (the app's own labelers and
  /// the regional authorities cannot be unsubscribed here).
  public let isConfigurable: Bool

  public var id: String { did }

  public init(
    did: String, title: String, handle: String, description: String?,
    isSubscribed: Bool, isConfigurable: Bool
  ) {
    self.did = did
    self.title = title
    self.handle = handle
    self.description = description
    self.isSubscribed = isSubscribed
    self.isConfigurable = isConfigurable
  }

  /// Builds a row from a detailed labeler view.
  public static func make(
    _ labeler: ModerationLabelerViewDetailed,
    appLabelers: [String],
    preferences: ModerationPrefs
  ) -> LabelerRowModel {
    let did = labeler.creator.did.rawValue
    let subscribed = LabelerService.isSubscribed(
      did: did, appLabelers: appLabelers, preferences: preferences)
    return LabelerRowModel(
      did: did,
      title: labeler.creator.displayName ?? labeler.creator.handle.rawValue,
      handle: labeler.creator.handle.rawValue,
      description: labeler.creator.description,
      isSubscribed: subscribed,
      // The app's own labelers are always on and the regional authorities are
      // configured by the app, so neither offers a toggle here.
      isConfigurable: !appLabelers.contains(did)
        && !isNonConfigurableModerationAuthority(did))
  }
}

/// The labeler directory: subscribed labelers first, then the rest.
///
/// Ported from the labeler listing in `screens/Moderation/index.tsx` and the
/// subscribe flow in `ProfileHeaderLabeler.tsx`. The cap preflight lives in
/// ``LabelerService/preflight(subscribe:currentDids:invalidDids:maxLabelers:)``;
/// this view calls it and surfaces ``ModerationCopy/maxLabelersMessage`` when it
/// refuses, rather than counting subscriptions itself.
public struct LabelerServicesScreen: View {
  private let subscribed: [LabelerRowModel]
  private let available: [LabelerRowModel]
  private let unavailable: [LabelerRowModel]
  private let isLoading: Bool
  private let onToggleSubscription: (LabelerRowModel) -> Void

  /// Creates the directory screen.
  ///
  /// - Parameters:
  ///   - subscribed: the viewer's current labelers.
  ///   - available: the rest of the directory.
  ///   - unavailable: subscribed dids that no longer resolve to a live labeler.
  ///   - isLoading: true while the directory is being read.
  ///   - onToggleSubscription: the subscribe/unsubscribe request for a row.
  public init(
    subscribed: [LabelerRowModel] = [],
    available: [LabelerRowModel] = [],
    unavailable: [LabelerRowModel] = [],
    isLoading: Bool = false,
    onToggleSubscription: @escaping (LabelerRowModel) -> Void = { _ in }
  ) {
    self.subscribed = subscribed
    self.available = available
    self.unavailable = unavailable
    self.isLoading = isLoading
    self.onToggleSubscription = onToggleSubscription
  }

  @Environment(\.alfTheme) private var theme

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        header

        if isLoading && subscribed.isEmpty && available.isEmpty {
          ListSkeleton()
        } else if subscribed.isEmpty && available.isEmpty {
          EmptyStateView(
            icon: "person.badge.shield.checkmark",
            title: ModerationCopy.labelersEmptyTitle,
            message: ModerationCopy.labelersEmptyMessage)
        } else {
          if !subscribed.isEmpty {
            ModerationSection(title: ModerationCopy.subscribedLabelersHeading) {
              VStack(spacing: 0) {
                ForEach(subscribed) { row in
                  labelerRow(row)
                  ModerationDivider()
                }
              }
            }
          }

          if !unavailable.isEmpty {
            ModerationSection(title: ModerationCopy.unavailableLabelersHeading) {
              VStack(spacing: 0) {
                ForEach(unavailable) { row in
                  labelerRow(row)
                  ModerationDivider()
                }
              }
            }
          }

          if !available.isEmpty {
            ModerationSection(title: ModerationCopy.allLabelersHeading) {
              VStack(spacing: 0) {
                ForEach(available) { row in
                  labelerRow(row)
                  ModerationDivider()
                }
              }
            }
          }
        }
      }
      .padding(.xl)
      .frame(maxWidth: 640)
      .frame(maxWidth: .infinity)
    }
    .background(theme.atomColors.bg)
    .accessibilityIdentifier(ModerationAccessibility.labelerServicesScreen)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      AlfText(
        ModerationCopy.labelerServicesTitle, scale: .xxl, weight: Scales.FontWeight.bold)
      AlfText(
        ModerationCopy.labelerServicesDescription, scale: .sm,
        color: theme.atomColors.textContrastMedium)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func labelerRow(_ row: LabelerRowModel) -> some View {
    ModerationRow(title: row.title, subtitle: "@\(row.handle)") {
      if row.isConfigurable {
        Button(row.isSubscribed ? ModerationCopy.unsubscribeAction : ModerationCopy.subscribeAction)
        {
          onToggleSubscription(row)
        }
        .buttonStyle(
          .alf(
            color: row.isSubscribed ? .secondary : .primary, size: .small,
            shape: .default))
      } else if row.isSubscribed {
        ModerationBadge(text: ModerationCopy.subscribedLabelersHeading)
      }
    }
  }
}

#Preview {
  LabelerServicesScreen(
    subscribed: ModerationFixtures.labelerRows(subscribed: true),
    available: ModerationFixtures.labelerRows(subscribed: false),
    unavailable: ModerationFixtures.labelerRows(subscribed: true, startIndex: 20))
}

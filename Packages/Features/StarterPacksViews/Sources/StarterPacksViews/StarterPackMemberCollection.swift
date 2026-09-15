import DesignSystem
import DesignTokens
import Lexicons
import StarterPacksLogic
import SwiftUI
import UIComponents

/// How a pack's members are laid out.
public enum StarterPackMemberLayout: String, CaseIterable, Sendable {
  /// A wrapping grid of avatars with names, which is what a small-sample pack
  /// shows.
  case grid
  /// One row per member, for the full paged read.
  case list
}

/// The members of a pack, in either of the two layouts the screen uses.
///
/// Reads only; the caller supplies the items. The grid is the sample the pack
/// view carries, the list is what ``StarterPackMembersQuery`` pages in.
public struct StarterPackMemberCollection: View {
  private let members: [App.Bsky.GraphDefs_ListItemView]
  private let layout: StarterPackMemberLayout
  private let optedOutDIDs: Set<String>

  @Environment(\.alfTheme) private var theme

  /// Creates a member collection.
  ///
  /// - Parameters:
  ///   - members: the list items to render, in wire order.
  ///   - layout: grid or list.
  ///   - optedOutDIDs: members who opted out, which the row badges.
  public init(
    members: [App.Bsky.GraphDefs_ListItemView],
    layout: StarterPackMemberLayout = .list,
    optedOutDIDs: Set<String> = []
  ) {
    self.members = members
    self.layout = layout
    self.optedOutDIDs = optedOutDIDs
  }

  public var body: some View {
    Group {
      switch layout {
      case .grid: grid
      case .list: list
      }
    }
    .accessibilityIdentifier(StarterPackAccessibility.memberList)
  }

  private var grid: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: Spacing.md)], spacing: Spacing.md) {
      ForEach(members, id: \.uri.rawValue) { item in
        StarterPackMemberTile(item: item, isOptedOut: isOptedOut(item))
      }
    }
    .padding(Spacing.md)
  }

  private var list: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      ForEach(members, id: \.uri.rawValue) { item in
        StarterPackMemberRow(item: item, isOptedOut: isOptedOut(item))
        Divider()
          .overlay(theme.atomColors.borderContrastLow)
      }
    }
  }

  private func isOptedOut(_ item: App.Bsky.GraphDefs_ListItemView) -> Bool {
    item.subjectOptedOut == true || optedOutDIDs.contains(item.subject.did.rawValue)
  }
}

/// One member as a grid tile: avatar over name.
public struct StarterPackMemberTile: View {
  private let item: App.Bsky.GraphDefs_ListItemView
  private let isOptedOut: Bool

  @Environment(\.alfTheme) private var theme

  public init(item: App.Bsky.GraphDefs_ListItemView, isOptedOut: Bool = false) {
    self.item = item
    self.isOptedOut = isOptedOut
  }

  public var body: some View {
    VStack(spacing: Spacing.xs) {
      Avatar(
        avatar: item.subject.avatar?.rawValue,
        handle: item.subject.handle.rawValue,
        displayName: item.subject.displayName,
        size: .lg)
      AlfText(name, scale: .sm, weight: Scales.FontWeight.semiBold)
        .lineLimit(2)
        .multilineTextAlignment(.center)
      AlfText(handle, scale: .xxs, color: theme.atomColors.textContrastMedium)
        .lineLimit(1)
      if isOptedOut {
        StarterPackOptedOutBadge()
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(StarterPackAccessibility.memberRow(item.subject.did.rawValue))
  }

  private var name: String {
    StarterPackStrings.enforceLen(
      StarterPackStrings.sanitizeDisplayName(item.subject.displayName ?? item.subject.handle.rawValue),
      40, ellipsis: true)
  }

  private var handle: String { "@\(item.subject.handle.rawValue)" }
}

/// One member as a list row: avatar, name, handle, optional badge.
public struct StarterPackMemberRow: View {
  private let item: App.Bsky.GraphDefs_ListItemView
  private let isOptedOut: Bool

  @Environment(\.alfTheme) private var theme

  public init(item: App.Bsky.GraphDefs_ListItemView, isOptedOut: Bool = false) {
    self.item = item
    self.isOptedOut = isOptedOut
  }

  public var body: some View {
    HStack(spacing: Spacing.sm) {
      Avatar(
        avatar: item.subject.avatar?.rawValue,
        handle: item.subject.handle.rawValue,
        displayName: item.subject.displayName,
        size: .md)

      VStack(alignment: .leading, spacing: Spacing.xxs) {
        AlfText(name, scale: .sm, weight: Scales.FontWeight.semiBold)
          .lineLimit(1)
        AlfText(handle, scale: .xs, color: theme.atomColors.textContrastMedium)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if isOptedOut {
        StarterPackOptedOutBadge()
      }
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(StarterPackAccessibility.memberRow(item.subject.did.rawValue))
  }

  private var name: String {
    StarterPackStrings.enforceLen(
      StarterPackStrings.sanitizeDisplayName(
        item.subject.displayName ?? item.subject.handle.rawValue),
      32, ellipsis: true)
  }

  private var handle: String { "@\(item.subject.handle.rawValue)" }
}

/// The badge a member who opted out of the reference list carries.
public struct StarterPackOptedOutBadge: View {
  @Environment(\.alfTheme) private var theme

  public init() {}

  public var body: some View {
    Text("Opted out")
      .font(TypeScale.xxs.font(weight: Scales.FontWeight.medium))
      .foregroundStyle(theme.atomColors.textContrastMedium)
      .padding(.horizontal, Spacing.xs)
      .padding(.vertical, 2)
      .background(theme.atomColors.bgContrast100)
      .clipShape(.capsule)
  }
}

/// One pinned feed, as the feeds tab and the wizard's feeds step both render it.
public struct StarterPackFeedRow: View {
  private let feed: App.Bsky.FeedDefs_GeneratorView

  @Environment(\.alfTheme) private var theme

  public init(feed: App.Bsky.FeedDefs_GeneratorView) {
    self.feed = feed
  }

  public var body: some View {
    HStack(spacing: Spacing.sm) {
      Avatar(
        avatar: feed.avatar?.rawValue,
        handle: feed.creator.handle.rawValue,
        displayName: feed.displayName,
        size: .md)

      VStack(alignment: .leading, spacing: Spacing.xxs) {
        AlfText(feed.displayName, scale: .sm, weight: Scales.FontWeight.semiBold)
          .lineLimit(1)
        AlfText(
          "@\(feed.creator.handle.rawValue)", scale: .xs, color: theme.atomColors.textContrastMedium
        )
        .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(StarterPackAccessibility.feedRow(feed.uri.rawValue))
  }
}

/// One wizard member, as the wizard's edit sheet lists it.
public struct StarterPackWizardProfileRow: View {
  private let profile: WizardProfile
  private let isOptedOut: Bool

  @Environment(\.alfTheme) private var theme

  public init(profile: WizardProfile, isOptedOut: Bool = false) {
    self.profile = profile
    self.isOptedOut = isOptedOut
  }

  public var body: some View {
    HStack(spacing: Spacing.sm) {
      Avatar(avatar: nil, handle: profile.handle, displayName: profile.displayName, size: .md)
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        // The Logic type already sanitizes and truncates the label the way RN's
        // `getName` does, so the view renders it verbatim.
        AlfText(profile.displayLabel, scale: .sm, weight: Scales.FontWeight.semiBold)
          .lineLimit(1)
        AlfText("@\(profile.handle)", scale: .xs, color: theme.atomColors.textContrastMedium)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if isOptedOut {
        StarterPackOptedOutBadge()
      }
    }
    .padding(.vertical, Spacing.xs)
    .accessibilityElement(children: .combine)
  }
}

/// One wizard feed, as the wizard's edit sheet lists it.
public struct StarterPackWizardFeedRow: View {
  private let feed: WizardFeed

  @Environment(\.alfTheme) private var theme

  public init(feed: WizardFeed) {
    self.feed = feed
  }

  public var body: some View {
    HStack(spacing: Spacing.sm) {
      Avatar(avatar: nil, handle: feed.displayName, displayName: nil, size: .md)
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        AlfText(feed.displayLabel, scale: .sm, weight: Scales.FontWeight.semiBold)
          .lineLimit(1)
        AlfText(feed.uri, scale: .xs, color: theme.atomColors.textContrastMedium)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, Spacing.xs)
    .accessibilityElement(children: .combine)
  }
}

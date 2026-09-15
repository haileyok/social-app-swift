import DesignSystem
import Lexicons
import SwiftUI
import UIComponents
import UIComponentsCore

/// The row components the search and Explore screens share.
///
/// Each is a pure render of presentation data: the name/handle/byline strings
/// are computed by ``SearchRowData`` (or come from `SearchLogic`'s models), so a
/// row never inspects a lexicon type or decides whether it should exist.
///
/// Rows take an optional `onSelect` rather than a navigation type, so the same
/// component serves the suggestions list, the results tabs and Explore without
/// the view layer importing a router.

// MARK: - Profile row

/// One account row: avatar, name, handle, and an optional bio line.
public struct SearchProfileRow: View {
  private let name: String
  private let handle: String
  private let avatar: AvatarSource
  private let bio: String?
  private let onSelect: () -> Void
  private let onRemove: (() -> Void)?

  @Environment(\.alfTheme) private var theme

  public init(
    name: String,
    handle: String,
    avatar: AvatarSource,
    bio: String? = nil,
    onSelect: @escaping () -> Void = {},
    onRemove: (() -> Void)? = nil
  ) {
    self.name = name
    self.handle = handle
    self.avatar = avatar
    self.bio = bio
    self.onSelect = onSelect
    self.onRemove = onRemove
  }

  /// Builds a row from a full profile view.
  public init(
    profile: App.Bsky.ActorDefs_ProfileView,
    onSelect: @escaping () -> Void = {},
    onRemove: (() -> Void)? = nil
  ) {
    self.init(
      name: SearchRowData.displayName(profile),
      handle: SearchRowData.handle(profile),
      avatar: SearchRowData.avatar(profile),
      bio: SearchRowData.bio(profile),
      onSelect: onSelect,
      onRemove: onRemove)
  }

  /// Builds a row from a basic profile view, which carries no bio.
  public init(
    profile: App.Bsky.ActorDefs_ProfileViewBasic,
    onSelect: @escaping () -> Void = {},
    onRemove: (() -> Void)? = nil
  ) {
    self.init(
      name: SearchRowData.displayName(profile),
      handle: SearchRowData.handle(profile),
      avatar: SearchRowData.avatar(profile),
      onSelect: onSelect,
      onRemove: onRemove)
  }

  public var body: some View {
    RowContainer(onSelect: onSelect, onRemove: onRemove) {
      HStack(alignment: .top, spacing: Spacing.sm) {
        Avatar(source: avatar, size: .md, label: name)
        VStack(alignment: .leading, spacing: Spacing.xs) {
          AlfText(name, scale: .md, weight: Scales.FontWeight.semiBold)
            .lineLimit(1)
          AlfText(handle, scale: .sm, color: theme.atomColors.textContrastMedium)
            .lineLimit(1)
          if let bio {
            AlfText(bio, scale: .sm, color: theme.atomColors.textContrastMedium)
              .lineLimit(2)
          }
        }
        Spacer(minLength: 0)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Feed generator row

/// One feed-generator row.
public struct SearchFeedRow: View {
  private let title: String
  private let byline: String
  private let description: String?
  private let avatar: AvatarSource
  private let onSelect: () -> Void

  @Environment(\.alfTheme) private var theme

  public init(
    title: String,
    byline: String,
    description: String? = nil,
    avatar: AvatarSource,
    onSelect: @escaping () -> Void = {}
  ) {
    self.title = title
    self.byline = byline
    self.description = description
    self.avatar = avatar
    self.onSelect = onSelect
  }

  /// Builds a row from a feed generator view.
  public init(feed: App.Bsky.FeedDefs_GeneratorView, onSelect: @escaping () -> Void = {}) {
    self.init(
      title: SearchRowData.title(feed),
      byline: SearchRowData.byline(feed),
      description: SearchRowData.description(feed),
      avatar: AvatarSource.resolve(
        avatar: feed.avatar?.rawValue,
        handle: feed.creator.handle.rawValue,
        displayName: feed.displayName),
      onSelect: onSelect)
  }

  public var body: some View {
    RowContainer(onSelect: onSelect) {
      HStack(alignment: .top, spacing: Spacing.sm) {
        Avatar(source: avatar, size: .md, label: title)
        VStack(alignment: .leading, spacing: Spacing.xs) {
          AlfText(title, scale: .md, weight: Scales.FontWeight.semiBold)
            .lineLimit(1)
          AlfText(byline, scale: .sm, color: theme.atomColors.textContrastMedium)
            .lineLimit(1)
          if let description {
            AlfText(description, scale: .sm, color: theme.atomColors.textContrastMedium)
              .lineLimit(2)
          }
        }
        Spacer(minLength: 0)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Starter pack row

/// One starter-pack row.
public struct SearchStarterPackRow: View {
  private let title: String
  private let byline: String
  private let onSelect: () -> Void

  @Environment(\.alfTheme) private var theme

  public init(title: String, byline: String, onSelect: @escaping () -> Void = {}) {
    self.title = title
    self.byline = byline
    self.onSelect = onSelect
  }

  /// Builds a row from a starter pack view.
  public init(
    pack: App.Bsky.GraphDefs_StarterPackView, onSelect: @escaping () -> Void = {}
  ) {
    self.init(
      title: SearchRowData.title(pack),
      byline: SearchRowData.byline(pack),
      onSelect: onSelect)
  }

  public var body: some View {
    RowContainer(onSelect: onSelect) {
      HStack(alignment: .center, spacing: Spacing.sm) {
        Image(systemName: "person.3.fill")
          .font(.system(size: 18))
          .foregroundStyle(theme.atomColors.textContrastMedium)
          .frame(width: AvatarSize.md.side, height: AvatarSize.md.side)
        VStack(alignment: .leading, spacing: Spacing.xs) {
          AlfText(title, scale: .md, weight: Scales.FontWeight.semiBold)
            .lineLimit(1)
          AlfText(byline, scale: .sm, color: theme.atomColors.textContrastMedium)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Trending row

/// One trending-topic or trending-video row.
public struct SearchTrendingRow: View {
  private let title: String
  private let detail: String?
  private let onSelect: () -> Void

  @Environment(\.alfTheme) private var theme

  public init(title: String, detail: String? = nil, onSelect: @escaping () -> Void = {}) {
    self.title = title
    self.detail = detail
    self.onSelect = onSelect
  }

  /// Builds a row from a trending topic.
  public init(
    topic: App.Bsky.UnspeccedDefs_TrendingTopic, onSelect: @escaping () -> Void = {}
  ) {
    self.init(
      title: SearchRowData.title(topic),
      detail: topic.description,
      onSelect: onSelect)
  }

  /// Builds a row from a trending video.
  public init(
    trend: App.Bsky.UnspeccedDefs_TrendView, onSelect: @escaping () -> Void = {}
  ) {
    self.init(
      title: SearchRowData.title(trend),
      detail: SearchRowData.postCount(trend),
      onSelect: onSelect)
  }

  public var body: some View {
    RowContainer(onSelect: onSelect) {
      HStack(alignment: .center, spacing: Spacing.sm) {
        Image(systemName: "chart.line.uptrend.xyaxis")
          .font(.system(size: 16))
          .foregroundStyle(theme.atomColors.textContrastMedium)
        VStack(alignment: .leading, spacing: Spacing.xs) {
          AlfText(title, scale: .md, weight: Scales.FontWeight.semiBold)
            .lineLimit(1)
          if let detail, !detail.isEmpty {
            AlfText(detail, scale: .sm, color: theme.atomColors.textContrastMedium)
              .lineLimit(2)
          }
        }
        Spacer(minLength: 0)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Shared row chrome

/// The tappable container every search row shares: full-width, themed, with a
/// hairline separator underneath and an optional trailing remove affordance.
struct RowContainer<Content: View>: View {
  let onSelect: () -> Void
  var onRemove: (() -> Void)?
  @ViewBuilder var content: Content

  @Environment(\.alfTheme) private var theme

  init(
    onSelect: @escaping () -> Void,
    onRemove: (() -> Void)? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.onSelect = onSelect
    self.onRemove = onRemove
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: Spacing.sm) {
        Button(action: onSelect) {
          content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)

        if let onRemove {
          Button(action: onRemove) {
            Image(systemName: "xmark")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(theme.atomColors.textContrastMedium)
              .frame(width: 32, height: 32)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(SearchCopy.removeHistoryEntryAction)
        }
      }
      .padding(.md, .horizontal)
      .padding(.sm, .vertical)

      Divider()
        .overlay(theme.atomColors.borderContrastLow)
    }
  }
}

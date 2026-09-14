#if canImport(SwiftUI)
import DesignSystem
import DesignSystemCore
import DesignTokens
import Moderation
import SwiftUI
import UIComponentsCore

/// The internal component gallery.
///
/// Not shipped: it exists so every component can be seen side by side, per
/// theme, on a simulator. The app shell mounts it behind a debug entry point.
/// It renders real ``PostFeedItem`` values built from ``GalleryFixtures``, so a
/// regression in the post layout shows up here.
public struct ComponentGallery: View {
  private let previewTheme: ThemePreference

  @State private var toastPresenter = ToastPresenter()

  public init(theme: ThemePreference = .system) {
    self.previewTheme = theme
  }

  public var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: Spacing.xxl) {
        GallerySection("Buttons") { ButtonMatrixSection() }
        GallerySection("Avatars") { AvatarSection() }
        GallerySection("Post - text") { TextPostSection() }
        GallerySection("Post - embeds") { EmbedSection() }
        GallerySection("Post - moderation") { ModerationSection() }
        GallerySection("Lists") { ListStateSection() }
        GallerySection("Toasts") { ToastSection(presenter: toastPresenter) }
      }
      .padding(.md)
    }
    .background(galleryBackground)
    .toastPresenter(toastPresenter)
  }

  @Environment(\.alfTheme) private var theme
  private var galleryBackground: Color { theme.atomColors.bg }
}

/// A titled section in the gallery.
struct GallerySection<Content: View>: View {
  private let title: String
  private let content: Content

  @Environment(\.alfTheme) private var theme

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      Text(title)
        .font(TypeScale.xl.font(weight: "600"))
        .foregroundStyle(theme.atomColors.text)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Every colour x size x shape combination, so the matrix is visible at a glance.
struct ButtonMatrixSection: View {
  private let colors: [ButtonColor] = [
    .primary, .secondary, .secondaryInverted, .negative, .primarySubtle, .negativeSubtle,
  ]
  private let sizes: [ButtonSize] = [.tiny, .small, .medium, .large]

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      ForEach(colors, id: \.self) { color in
        VStack(alignment: .leading, spacing: Spacing.sm) {
          Text(color.rawValue)
            .font(TypeScale.sm.font(weight: "600"))
          HStack(spacing: Spacing.sm) {
            ForEach(sizes, id: \.self) { size in
              Button("Label") {}
                .buttonStyle(.alf(color: color, size: size, shape: .`default`))
            }
          }
          HStack(spacing: Spacing.sm) {
            ForEach(sizes, id: \.self) { size in
              Button("Label") {}
                .buttonStyle(.alf(color: color, size: size, shape: .rectangular))
            }
          }
          HStack(spacing: Spacing.sm) {
            ForEach(sizes, id: \.self) { size in
              Button {} label: { Image(systemName: "heart") }
                .buttonStyle(.alf(color: color, size: size, shape: .round))
            }
            ForEach(sizes, id: \.self) { size in
              Button {} label: { Image(systemName: "heart") }
                .buttonStyle(.alf(color: color, size: size, shape: .square))
            }
          }
        }
      }
      HStack(spacing: Spacing.sm) {
        Button("Disabled") {}
          .buttonStyle(.alf(color: .primary))
          .disabled(true)
        Button("Disabled") {}
          .buttonStyle(.alf(color: .secondary))
          .disabled(true)
      }
    }
  }
}

/// The avatar ladder and the banner.
struct AvatarSection: View {
  private let sizes: [AvatarSize] = [.xs, .sm, .md, .lg, .xl]

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      HStack(alignment: .bottom, spacing: Spacing.md) {
        ForEach(sizes, id: \.self) { size in
          Avatar(
            avatar: nil, handle: "alice.bsky.social", displayName: "Alice", size: size)
        }
      }
      Banner(banner: nil)
        .frame(height: BannerGeometry.defaultHeight)
        .clipShape(.rect(cornerRadius: Radius.md, style: .continuous))
    }
  }
}

/// Plain and rich-text posts.
struct TextPostSection: View {
  var body: some View {
    VStack(spacing: Spacing.md) {
      PostFeedItem(
        data: feedItemViewData(
          GalleryFixtures.post(
            "A short post with no embed, showing the author line, body and engagement row."),
          counts: FeedItemCounts(replyCount: 12, repostCount: 2500, likeCount: 1_234_567)))
      Divider()
      PostFeedItem(
        data: feedItemViewData(
          GalleryFixtures.post(
            "A post with a repost context line.",
            author: GalleryFixtures.profile(handle: "bob.bsky.social", displayName: "Bob")),
          options: FeedItemRenderOptions(contextLine: "Reposted by Alice")))
    }
  }
}

/// One post per embed variant in the v1 matrix.
struct EmbedSection: View {
  var body: some View {
    VStack(spacing: Spacing.md) {
      PostFeedItem(
        data: feedItemViewData(
          GalleryFixtures.post("One image.", embed: GalleryFixtures.images(1))))
      PostFeedItem(
        data: feedItemViewData(
          GalleryFixtures.post("Two images.", embed: GalleryFixtures.images(2))))
      PostFeedItem(
        data: feedItemViewData(
          GalleryFixtures.post("Three images.", embed: GalleryFixtures.images(3))))
      PostFeedItem(
        data: feedItemViewData(
          GalleryFixtures.post("Four images.", embed: GalleryFixtures.images(4))))
      PostFeedItem(
        data: feedItemViewData(
          GalleryFixtures.post("An external link card.", embed: GalleryFixtures.external)))
      PostFeedItem(
        data: feedItemViewData(
          GalleryFixtures.post("A quoted post.", embed: GalleryFixtures.quote())))
      PostFeedItem(
        data: feedItemViewData(
          GalleryFixtures.post("A quote with media.", embed: GalleryFixtures.recordWithMedia())))
      PostFeedItem(
        data: feedItemViewData(
          GalleryFixtures.post("A blocked quote.", embed: GalleryFixtures.blockedQuote)))
      PostFeedItem(
        data: feedItemViewData(GalleryFixtures.post("A video placeholder.", embed: nil)))
      VideoPlaceholder()
    }
  }
}

/// The four moderation outcomes, applied to the same post.
struct ModerationSection: View {
  var body: some View {
    VStack(spacing: Spacing.md) {
      ForEach(GalleryFixtures.moderatedSurfaces(), id: \.0) { label, surface in
        VStack(alignment: .leading, spacing: Spacing.sm) {
          Text(label)
            .font(TypeScale.sm.font(weight: "600"))
          ModerationMask(surface: surface) {
            PostFeedItem(
              data: feedItemViewData(GalleryFixtures.post("Moderated content body.")))
          }
        }
      }
    }
  }
}

/// Empty, error and loading states.
struct ListStateSection: View {
  @State private var showError = true

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      EmptyStateView(strings: .feed, icon: "person.2")
        .frame(height: 220)
      ErrorStateView(
        title: ListStrings.feed.errorTitle,
        message: ListStrings.feed.errorMessage
      ) {}
      .frame(height: 220)
      RetryRow {}
      LoadMoreSpinner()
      VStack(spacing: 0) {
        PostSkeletonRow()
        Divider()
        PostSkeletonRow()
      }
    }
  }
}

/// Buttons that fire each toast flavour.
struct ToastSection: View {
  let presenter: ToastPresenter

  var body: some View {
    HStack(spacing: Spacing.sm) {
      Button("Neutral") { presenter.show("Saved to your bookmarks") }
        .buttonStyle(.alf(color: .secondary, size: .small))
      Button("Success") { presenter.show("Post published", kind: .success) }
        .buttonStyle(.alf(color: .primary, size: .small))
      Button("Error") { presenter.show("Could not send", kind: .error) }
        .buttonStyle(.alf(color: .negative, size: .small))
    }
  }
}

#Preview("Light") {
  ComponentGallery(theme: .light)
}

#Preview("Dark") {
  ComponentGallery(theme: .dark)
}
#endif

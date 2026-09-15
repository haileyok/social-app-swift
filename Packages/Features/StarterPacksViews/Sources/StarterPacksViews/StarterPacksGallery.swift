import DesignSystem
import DesignSystemCore
import StarterPacksLogic
import SwiftUI

/**
 Every starter-pack surface in one navigable screen.

 This is the preview and debug entry point: the app's toolbar mounts it, and the
 individual `#Preview`s below mount each surface directly. Keeping the fixtures
 in one place means a reviewer can see all four states - detail, wizard, share,
 landing - without a network, which the Logic package's tests cannot show and
 the appview does not yet serve.
 */
public struct StarterPacksGallery: View {
  private let theme: ThemePreference

  @State private var section: Section = .detail

  /// The surfaces the gallery can show.
  public enum Section: String, CaseIterable, Hashable, Sendable {
    /// The signed-in pack detail screen.
    case detail
    /// The create wizard.
    case wizard
    /// The share sheet with its QR card.
    case share
    /// The logged-out landing screen.
    case landing
    /// The broken-pack state an owner sees when the backing list is gone.
    case deletedList

    /// The segment's label.
    public var label: String {
      switch self {
      case .detail: "Detail"
      case .wizard: "Wizard"
      case .share: "Share"
      case .landing: "Landing"
      case .deletedList: "Broken"
      }
    }
  }

  /// Creates the gallery.
  public init(theme: ThemePreference = .system) {
    self.theme = theme
  }

  public var body: some View {
    VStack(spacing: 0) {
      picker
      Divider()

      switch section {
      case .detail: detailSurface
      case .wizard: wizardSurface
      case .share: shareSurface
      case .landing: landingSurface
      case .deletedList: deletedListSurface
      }
    }
    .theme(theme)
  }

  private var picker: some View {
    Picker("Surface", selection: $section) {
      ForEach(Section.allCases, id: \.self) { section in
        Text(section.label).tag(section)
      }
    }
    .pickerStyle(.segmented)
    .padding(Spacing.md)
  }

  private var detailSurface: some View {
    NavigationStack {
      StarterPackScreen(
        detail: StarterPacksFixtures.detail(isOwn: true),
        members: StarterPacksFixtures.memberItems(count: 12),
        membership: StarterPackMembership(packURI: "at://sample", isMember: false),
        shareData: StarterPacksFixtures.shareData(detail: StarterPacksFixtures.detail(isOwn: true)),
        onJoin: {},
        onLeave: {},
        onFollowAll: {},
        onShare: {},
        onEdit: {})
      .navigationTitle(StarterPackCopy.screenTitle)
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private var wizardSurface: some View {
    NavigationStack {
      StarterPackWizardScreen(
        wizard: StarterPacksFixtures.wizard(),
        profileResults: StarterPacksFixtures.profileResults(),
        feedResults: StarterPacksFixtures.feedResults())
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private var shareSurface: some View {
    NavigationStack {
      StarterPackShareSheet(
        detail: StarterPacksFixtures.detail(isOwn: true),
        data: StarterPacksFixtures.shareData(detail: StarterPacksFixtures.detail(isOwn: true)))
      .navigationTitle(StarterPackCopy.shareTitle)
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private var landingSurface: some View {
    NavigationStack {
      StarterPackLandingView(state: StarterPacksFixtures.landingState())
    }
  }

  /// The owner-visible broken state: a pack whose backing list is gone.
  private var deletedListSurface: some View {
    NavigationStack {
      StarterPackScreen(
        detail: StarterPackViewBuilder.detail(
          StarterPacksFixtures.packView(
            name: "Bluesky for Art History", memberCount: 0, feedCount: 0),
          viewerDID: StarterPacksFixtures.authorDID),
        isDeletedListOwned: true)
      .navigationTitle(StarterPackCopy.screenTitle)
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

#Preview("Pack detail") {
  NavigationStack {
    StarterPackScreen(
      detail: StarterPacksFixtures.detail(isOwn: true),
      members: StarterPacksFixtures.memberItems(count: 12),
      shareData: StarterPacksFixtures.shareData(detail: StarterPacksFixtures.detail(isOwn: true)))
  }
}

#Preview("Wizard") {
  NavigationStack {
    StarterPackWizardScreen(
      wizard: StarterPacksFixtures.wizard(),
      profileResults: StarterPacksFixtures.profileResults(),
      feedResults: StarterPacksFixtures.feedResults())
  }
}

#Preview("Share") {
  StarterPackShareSheet(
    detail: StarterPacksFixtures.detail(isOwn: true),
    data: StarterPacksFixtures.shareData(detail: StarterPacksFixtures.detail(isOwn: true)))
}

#Preview("Landing") {
  StarterPackLandingView(state: StarterPacksFixtures.landingState())
}

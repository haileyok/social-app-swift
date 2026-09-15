import DesignSystem
import DesignTokens
import Lexicons
import ProfileLogic
import SwiftUI
import UIComponents
import UIComponentsCore

/// The fixture-driven profile surface.
///
/// This is the capture surface the Mac CI screenshots and the app hook mount.
/// It renders ``ProfileScreen`` from ``ProfileFixtures`` data, so every variant
/// (own profile, follow states, blocked, blurred, labeler) can be reviewed
/// without a network or a session, and it carries a picker so a screenshot run
/// can walk the variants.
///
/// ```swift
/// ProfileFixtureSurface()
/// ```
public struct ProfileFixtureSurface: View {
  @AppStorage("profileFixtureVariant") private var storedVariant = Variant.standard.rawValue
  @State private var selection: Variant = .standard

  public init() {}

  /// One reviewable profile variant.
  public enum Variant: String, CaseIterable, Sendable {
    case standard
    case ownProfile
    case following
    case pendingFollow
    case blockedBy
    case knownFollowers
    case labeler
    case emptyFeed

    /// The label the picker shows.
    public var title: String {
      switch self {
      case .standard: "Standard"
      case .ownProfile: "Own profile"
      case .following: "Following"
      case .pendingFollow: "Pending follow"
      case .blockedBy: "Blocked by"
      case .knownFollowers: "Known followers"
      case .labeler: "Labeler"
      case .emptyFeed: "Empty feed"
      }
    }
  }

  public var body: some View {
    NavigationStack {
      ProfileScreen(
        headerData: headerData,
        labeler: labelerData,
        content: ProfileScreenContent(feedItems: feedItems),
        onAction: { _ in })
        .navigationTitle("Profile Views")
        .background(theme.atomColors.bg)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Picker("Variant", selection: $selection) {
              ForEach(Variant.allCases, id: \.self) { variant in
                Text(variant.title).tag(variant)
              }
            }
            .pickerStyle(.menu)
          }
        }
    }
    .onAppear {
      selection = Variant(rawValue: storedVariant) ?? .standard
    }
    .onChange(of: selection) { _, value in
      storedVariant = value.rawValue
    }
  }

  @Environment(\.alfTheme) private var theme

  // MARK: - Variant data

  private var headerData: ProfileHeaderViewData {
    switch selection {
    case .standard: ProfileFixtures.notFollowingHeaderData()
    case .ownProfile: ProfileFixtures.ownProfileHeaderData()
    case .following: ProfileFixtures.followingHeaderData()
    case .pendingFollow: ProfileFixtures.pendingFollowHeaderData()
    case .blockedBy: ProfileFixtures.blockedByHeaderData()
    case .knownFollowers:
      ProfileFixtures.headerData(
        profile: ProfileFixtures.profile(
          viewer: ProfileFixtures.viewer(
            followedBy: "at://did:plc:me/app.bsky.graph.follow/1",
            knownFollowers: ProfileFixtures.knownFollowers())))
    case .labeler:
      ProfileFixtures.headerData(profile: ProfileFixtures.labelerProfile().profile)
    case .emptyFeed:
      ProfileFixtures.notFollowingHeaderData()
    }
  }

  private var labelerData: LabelerProfileViewData? {
    selection == .labeler ? ProfileFixtures.labelerProfile().labeler : nil
  }

  private var feedItems: [ProfileTab: [FeedItemViewData]] {
    guard selection != .emptyFeed else { return [:] }
    return [
      .posts: ProfileFixturePosts.pages(for: .posts, count: 3),
      .replies: ProfileFixturePosts.pages(for: .replies, count: 2),
      .media: ProfileFixturePosts.pages(for: .media, count: 2),
    ]
  }
}

#Preview("Profile fixture surface") {
  ProfileFixtureSurface()
}

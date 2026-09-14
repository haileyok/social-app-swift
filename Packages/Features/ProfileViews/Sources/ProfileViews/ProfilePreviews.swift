import DesignSystem
import DesignTokens
import ProfileLogic
import SwiftUI
import UIComponents

/// Previews for the individual profile views, so a review can inspect a
/// component in isolation from the full screen.
///
/// These are compile-time-verified by the iOS build: a preview that does not
/// type-check fails CI the same way a screen does.
#Preview("Header - follow states") {
  ScrollView {
    VStack(spacing: Spacing.xl) {
      ProfileHeader(data: ProfileFixtures.notFollowingHeaderData())
      ProfileHeader(data: ProfileFixtures.followingHeaderData())
      ProfileHeader(data: ProfileFixtures.pendingFollowHeaderData())
    }
  }
}

#Preview("Header - own profile and labeler") {
  ScrollView {
    VStack(spacing: Spacing.xl) {
      ProfileHeader(data: ProfileFixtures.ownProfileHeaderData())
      ProfileHeader(
        data: ProfileFixtures.headerData(profile: ProfileFixtures.labelerProfile().profile),
        labeler: ProfileFixtures.labelerProfile().labeler)
    }
  }
}

#Preview("Known followers") {
  KnownFollowersLine(knownFollowers: ProfileFixtures.knownFollowers())
    .padding()
}

#Preview("Actor list row") {
  VStack(spacing: 0) {
    ProfileListRow(profile: ProfileFixtures.basic(did: "did:plc:bob", handle: "bob.bsky.social"))
    ProfileListRow(profile: ProfileFixtures.basic(did: "did:plc:carol", handle: "carol.bsky.social"))
  }
}

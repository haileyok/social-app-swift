import Foundation

/// The strings seam for the profile feature.
///
/// Every user-facing string in this package goes through this type rather than
/// being written inline at the call site. That gives the eventual localization
/// pass a single list to work from, and lets the fixture surface assert on the
/// copy without matching view internals.
///
/// The RN app resolves these through Lingui (`msg` / `Trans`). The Swift app has
/// no string catalog wired for this package yet, so the default implementations
/// carry the RN English wording verbatim and a caller may supply its own
/// closure-backed implementation without touching the views.
public protocol ProfileStrings: Sendable {
  /// The tab labels, in the RN app's wording.
  func tabTitle(_ section: String) -> String
  /// The label on the follow action.
  var follow: String { get }
  /// The label while following (the button that unfollows).
  var following: String { get }
  /// The label while a follow or unfollow is in flight.
  var followPending: String { get }
  /// The label on one's own profile.
  var editProfile: String { get }
  /// The label that opens the followers list.
  func followersCount(_ count: String) -> String
  /// The label that opens the follows list.
  func followsCount(_ count: String) -> String
  /// The label for the post count metric.
  func postsCount(_ count: String) -> String
  /// The known-followers line, e.g. "Followed by Alice and 3 others".
  func knownFollowers(_ names: [String], total: Int) -> String
  /// The title of a profile's followers screen.
  var followers: String { get }
  /// The title of a profile's follows screen.
  var follows: String { get }
  /// The banner shown when an account blocks the viewer.
  var blockedByNotice: String { get }
  /// The copy on a blurred header's reveal affordance.
  var showAnyway: String { get }
  /// The title of the edit-profile sheet.
  var editProfileTitle: String { get }
  /// The display-name field's label.
  var displayNameField: String { get }
  /// The description field's label.
  var descriptionField: String { get }
  /// The save action in the edit sheet.
  var save: String { get }
  /// The cancel action in the edit sheet.
  var cancel: String { get }
  /// A validation message for an over-long field.
  func tooLong(field: String, limit: Int) -> String
  /// The empty state for a list with nothing in it.
  func emptyList(_ title: String) -> String
}

/// The default English wording, matching the RN app.
public struct DefaultProfileStrings: ProfileStrings {
  public init() {}

  public func tabTitle(_ section: String) -> String { section }

  public var follow: String { "Follow" }
  public var following: String { "Following" }
  public var followPending: String { "Follow" }
  public var editProfile: String { "Edit Profile" }

  public func followersCount(_ count: String) -> String { "\(count) followers" }
  public func followsCount(_ count: String) -> String { "\(count) following" }
  public func postsCount(_ count: String) -> String { "\(count) posts" }

  public func knownFollowers(_ names: [String], total: Int) -> String {
    switch names.count {
    case 0: "Followed by \(total) people you follow"
    case 1: "Followed by \(names[0])"
    case 2: "Followed by \(names[0]) and \(names[1])"
    default:
      total > names.count
        ? "Followed by \(names[0]), \(names[1]) and \(total - 2) others"
        : "Followed by \(names[0]), \(names[1]) and others"
    }
  }

  public var followers: String { "Followers" }
  public var follows: String { "Following" }
  public var blockedByNotice: String { "This account has blocked you." }
  public var showAnyway: String { "Show" }
  public var editProfileTitle: String { "Edit Profile" }
  public var displayNameField: String { "Display name" }
  public var descriptionField: String { "Description" }
  public var save: String { "Save" }
  public var cancel: String { "Cancel" }

  public func tooLong(field: String, limit: Int) -> String {
    "\(field) is too long. The maximum number of characters is \(limit)."
  }

  public func emptyList(_ title: String) -> String { "No \(title.lowercased()) yet." }
}

/// The strings used when a caller supplies none.
public let defaultProfileStrings: any ProfileStrings = DefaultProfileStrings()

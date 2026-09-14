import Foundation
import Lexicons
import Moderation

/// An actor view, reduced to the fields the profile feature reads.
///
/// The RN app hands raw `ProfileView` / `ProfileViewDetailed` / `ProfileViewBasic`
/// values around and reads whichever fields happen to be present
/// (`'followersCount' in profile` is how it tells a detailed view from a basic
/// one). Swift models that as an enum of the two shapes, so the fields that only
/// a detailed view carries are not silently absent.
public enum ProfileView: Sendable, Hashable {
  /// `app.bsky.actor.defs#profileViewDetailed` - carries the counts.
  case detailed(App.Bsky.ActorDefs_ProfileViewDetailed)
  /// `app.bsky.actor.defs#profileView` - everything but the counts.
  case basic(App.Bsky.ActorDefs_ProfileView)

  /// The actor's DID.
  public var did: String {
    switch self {
    case .detailed(let profile): profile.did.rawValue
    case .basic(let profile): profile.did.rawValue
    }
  }

  /// The actor's handle.
  public var handle: String {
    switch self {
    case .detailed(let profile): profile.handle.rawValue
    case .basic(let profile): profile.handle.rawValue
    }
  }

  /// The viewer's relationship to this actor, when the server supplied one.
  public var viewer: App.Bsky.ActorDefs_ViewerState? {
    switch self {
    case .detailed(let profile): profile.viewer
    case .basic(let profile): profile.viewer
    }
  }

  /// The labels on the actor.
  public var labels: [Com.Atproto.LabelDefs_Label]? {
    switch self {
    case .detailed(let profile): profile.labels
    case .basic(let profile): profile.labels
    }
  }

  /// `followersCount` for a detailed view, `nil` otherwise.
  public var followersCount: Int? {
    switch self {
    case .detailed(let profile): profile.followersCount
    case .basic: nil
    }
  }

  /// `followsCount` for a detailed view, `nil` otherwise.
  public var followsCount: Int? {
    switch self {
    case .detailed(let profile): profile.followsCount
    case .basic: nil
    }
  }

  /// `postsCount` for a detailed view, `nil` otherwise.
  public var postsCount: Int? {
    switch self {
    case .detailed(let profile): profile.postsCount
    case .basic: nil
    }
  }

  /// `associated` for a detailed view, `nil` otherwise.
  public var associated: App.Bsky.ActorDefs_ProfileAssociated? {
    switch self {
    case .detailed(let profile): profile.associated
    case .basic: nil
    }
  }

  /// The detailed view, when this is one.
  public var detailedProfile: App.Bsky.ActorDefs_ProfileViewDetailed? {
    if case .detailed(let profile) = self { return profile }
    return nil
  }
}

extension ProfileView {
  /// Adapts the view to the moderation engine's profile input.
  ///
  /// The engine's ``ProfileViewBasic`` is deliberately a looser shape than the
  /// generated lexicon type (its `labels` are plain structs, its viewer state
  /// carries no list fields), so this is a field-for-field projection rather than
  /// a reinterpretation.
  public var moderationSubject: Moderation.ProfileViewBasic {
    Moderation.ProfileViewBasic(
      did: did,
      handle: handle,
      displayName: displayName,
      avatar: avatarURL,
      viewer: viewer.map(Self.moderationViewer),
      labels: labels.map { labels in
        labels.map {
          Moderation.Label(
            ver: $0.ver,
            src: $0.src.rawValue,
            uri: $0.uri.rawValue,
            cid: $0.cid?.rawValue,
            val: $0.val,
            neg: $0.neg,
            cts: $0.cts.rawValue)
        }
      })
  }

  /// `displayName`, from whichever shape carries it.
  public var displayName: String? {
    switch self {
    case .detailed(let profile): profile.displayName
    case .basic(let profile): profile.displayName
    }
  }

  /// The avatar URL, from whichever shape carries it.
  public var avatarURL: String? {
    switch self {
    case .detailed(let profile): profile.avatar?.rawValue
    case .basic(let profile): profile.avatar?.rawValue
    }
  }

  /// The banner URL, which only a detailed view has.
  public var bannerURL: String? {
    switch self {
    case .detailed(let profile): profile.banner?.rawValue
    case .basic: nil
    }
  }

  /// Projects the generated viewer state onto the engine's input.
  static func moderationViewer(_ viewer: App.Bsky.ActorDefs_ViewerState)
    -> Moderation.ActorViewerState {
    Moderation.ActorViewerState(
      muted: viewer.muted,
      mutedByList: nil,
      blockedBy: viewer.blockedBy,
      blocking: viewer.blocking?.rawValue,
      blockingByList: nil,
      following: viewer.following?.rawValue)
  }
}

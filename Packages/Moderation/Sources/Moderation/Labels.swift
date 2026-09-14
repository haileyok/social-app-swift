/// Default label settings for the globally-known, configurable labels.
public let defaultLabelSettings: [String: LabelPreference] = [
  "porn": .hide,
  "sexual": .warn,
  "nudity": .ignore,
  "graphic-media": .warn,
]

/// The globally-known label definitions, keyed by label value.
public let labels: [String: LabelValueDefinition] = [
  "!hide": LabelValueDefinition(
    identifier: "!hide",
    severity: .alert,
    blurs: .content,
    defaultSetting: .hide,
    flags: [.noOverride, .noSelf],
    behaviors: LabelTargetBehaviors(
      account: ModerationBehavior(
        profileList: .blur,
        profileView: .blur,
        avatar: .blur,
        banner: .blur,
        displayName: .blur,
        contentList: .blur,
        contentView: .blur
      ),
      profile: ModerationBehavior(
        avatar: .blur,
        banner: .blur,
        displayName: .blur
      ),
      content: ModerationBehavior(
        contentList: .blur,
        contentView: .blur
      )
    ),
    definedBy: "app.bsky"
  ),
  "!warn": LabelValueDefinition(
    identifier: "!warn",
    severity: .none,
    blurs: .content,
    defaultSetting: .warn,
    flags: [.noSelf],
    behaviors: LabelTargetBehaviors(
      account: ModerationBehavior(
        profileList: .blur,
        profileView: .blur,
        avatar: .blur,
        banner: .blur,
        contentList: .blur,
        contentView: .blur
      ),
      profile: ModerationBehavior(
        avatar: .blur,
        banner: .blur,
        displayName: .blur
      ),
      content: ModerationBehavior(
        contentList: .blur,
        contentView: .blur
      )
    ),
    definedBy: "app.bsky"
  ),
  "!no-unauthenticated": LabelValueDefinition(
    identifier: "!no-unauthenticated",
    severity: .none,
    blurs: .content,
    defaultSetting: .hide,
    flags: [.noOverride, .unauthed],
    behaviors: LabelTargetBehaviors(
      account: ModerationBehavior(
        profileList: .blur,
        profileView: .blur,
        avatar: .blur,
        banner: .blur,
        displayName: .blur,
        contentList: .blur,
        contentView: .blur
      ),
      profile: ModerationBehavior(
        avatar: .blur,
        banner: .blur,
        displayName: .blur
      ),
      content: ModerationBehavior(
        contentList: .blur,
        contentView: .blur
      )
    ),
    definedBy: "app.bsky"
  ),
  "porn": LabelValueDefinition(
    identifier: "porn",
    severity: .none,
    blurs: .media,
    defaultSetting: .hide,
    flags: [.adult],
    behaviors: LabelTargetBehaviors(
      account: ModerationBehavior(avatar: .blur, banner: .blur),
      profile: ModerationBehavior(avatar: .blur, banner: .blur),
      content: ModerationBehavior(contentMedia: .blur)
    ),
    definedBy: "app.bsky"
  ),
  "sexual": LabelValueDefinition(
    identifier: "sexual",
    severity: .none,
    blurs: .media,
    defaultSetting: .warn,
    flags: [.adult],
    behaviors: LabelTargetBehaviors(
      account: ModerationBehavior(avatar: .blur, banner: .blur),
      profile: ModerationBehavior(avatar: .blur, banner: .blur),
      content: ModerationBehavior(contentMedia: .blur)
    ),
    definedBy: "app.bsky"
  ),
  "nudity": LabelValueDefinition(
    identifier: "nudity",
    severity: .none,
    blurs: .media,
    defaultSetting: .ignore,
    flags: [],
    behaviors: LabelTargetBehaviors(
      account: ModerationBehavior(avatar: .blur, banner: .blur),
      profile: ModerationBehavior(avatar: .blur, banner: .blur),
      content: ModerationBehavior(contentMedia: .blur)
    ),
    definedBy: "app.bsky"
  ),
  "graphic-media": LabelValueDefinition(
    identifier: "graphic-media",
    severity: .none,
    blurs: .media,
    defaultSetting: .warn,
    flags: [.adult],
    behaviors: LabelTargetBehaviors(
      account: ModerationBehavior(avatar: .blur, banner: .blur),
      profile: ModerationBehavior(avatar: .blur, banner: .blur),
      content: ModerationBehavior(contentMedia: .blur)
    ),
    definedBy: "app.bsky"
  ),
  /// Deprecated alias for `graphic-media`.
  "gore": LabelValueDefinition(
    identifier: "gore",
    severity: .none,
    blurs: .media,
    defaultSetting: .warn,
    flags: [.adult],
    behaviors: LabelTargetBehaviors(
      account: ModerationBehavior(avatar: .blur, banner: .blur),
      profile: ModerationBehavior(avatar: .blur, banner: .blur),
      content: ModerationBehavior(contentMedia: .blur)
    ),
    definedBy: "app.bsky"
  ),
]

import Foundation

/// A persisted account, the Swift port of the RN `PersistedAccount`.
///
/// The field set mirrors `src/state/persisted/schema.ts` exactly, including
/// the fields that exist only for backwards compatibility.
public struct PersistedAccount: Codable, Sendable, Equatable {
  public var service: String
  public var did: String
  public var handle: String
  public var email: String?
  public var emailConfirmed: Bool?
  public var emailAuthFactor: Bool?
  /// Optional because it can expire; the account entry outlives the token.
  public var refreshJwt: String?
  /// Optional because it can expire.
  public var accessJwt: String?
  public var signupQueued: Bool?
  /// Optional for backwards compatibility with pre-`active` documents.
  public var active: Bool?
  /// Known values: `takendown`, `suspended`, `deactivated`, or `active`.
  public var status: String?
  /// PDS endpoint from the did document or a pre-refresh stored value.
  public var pdsUrl: String?
  public var isSelfHosted: Bool?

  public init(
    service: String,
    did: String,
    handle: String,
    email: String? = nil,
    emailConfirmed: Bool? = nil,
    emailAuthFactor: Bool? = nil,
    refreshJwt: String? = nil,
    accessJwt: String? = nil,
    signupQueued: Bool? = nil,
    active: Bool? = nil,
    status: String? = nil,
    pdsUrl: String? = nil,
    isSelfHosted: Bool? = nil
  ) {
    self.service = service
    self.did = did
    self.handle = handle
    self.email = email
    self.emailConfirmed = emailConfirmed
    self.emailAuthFactor = emailAuthFactor
    self.refreshJwt = refreshJwt
    self.accessJwt = accessJwt
    self.signupQueued = signupQueued
    self.active = active
    self.status = status
    self.pdsUrl = pdsUrl
    self.isSelfHosted = isSelfHosted
  }
}

/// The current account.
///
/// Historically this held a full account (tokens included). It is now only a
/// `did` reference; the other fields are decoded for backwards compatibility
/// but should not be read by new code.
public struct PersistedCurrentAccount: Codable, Sendable, Equatable {
  public var did: String
  public var service: String?
  public var handle: String?
  public var email: String?
  public var emailConfirmed: Bool?
  public var emailAuthFactor: Bool?
  public var refreshJwt: String?
  public var accessJwt: String?
  public var signupQueued: Bool?
  public var active: Bool?
  public var status: String?
  public var pdsUrl: String?
  public var isSelfHosted: Bool?

  public init(did: String, service: String? = nil, handle: String? = nil) {
    self.did = did
    self.service = service
    self.handle = handle
  }
}

/// The persisted session slice.
public struct PersistedSession: Codable, Sendable, Equatable {
  public var accounts: [PersistedAccount]
  public var currentAccount: PersistedCurrentAccount?

  public init(
    accounts: [PersistedAccount] = [],
    currentAccount: PersistedCurrentAccount? = nil
  ) {
    self.accounts = accounts
    self.currentAccount = currentAccount
  }
}

/// How an external embed renders in the app.
public enum ExternalEmbedOption: String, Codable, Sendable {
  case show
  case hide
}

/// Per-provider external embed preference.
public struct ExternalEmbeds: Codable, Sendable, Equatable {
  public var giphy: ExternalEmbedOption?
  public var tenor: ExternalEmbedOption?
  public var klipy: ExternalEmbedOption?
  public var youtube: ExternalEmbedOption?
  public var youtubeShorts: ExternalEmbedOption?
  public var twitch: ExternalEmbedOption?
  public var vimeo: ExternalEmbedOption?
  public var spotify: ExternalEmbedOption?
  public var appleMusic: ExternalEmbedOption?
  public var soundcloud: ExternalEmbedOption?
  public var flickr: ExternalEmbedOption?
  public var bandcamp: ExternalEmbedOption?

  public init() {}
}

/// The app color mode.
public enum ColorMode: String, Codable, Sendable {
  case system
  case light
  case dark
}

/// The dark-mode theme variant.
public enum DarkTheme: String, Codable, Sendable {
  case dim
  case dark
}

/// Language preferences.
public struct LanguagePrefs: Codable, Sendable, Equatable {
  /// Target language for translating posts (BCP-47, 2-letter).
  public var primaryLanguage: String
  /// Languages the user reads, passed to feeds (BCP-47, 2-letter).
  public var contentLanguages: [String]
  /// Posting language(s), comma-separated.
  public var postLanguage: String
  /// Recent posting languages, used to pre-populate the composer selector.
  public var postLanguageHistory: [String]
  /// UI translation language (BCP-47, with or without region).
  public var appLanguage: String

  public init(
    primaryLanguage: String = "en",
    contentLanguages: [String] = ["en"],
    postLanguage: String = "en",
    postLanguageHistory: [String] = ["en"],
    appLanguage: String = "en"
  ) {
    self.primaryLanguage = primaryLanguage
    self.contentLanguages = contentLanguages
    self.postLanguage = postLanguage
    self.postLanguageHistory = postLanguageHistory
    self.appLanguage = appLanguage
  }
}

/// The reminder slice.
public struct Reminders: Codable, Sendable, Equatable {
  public var lastEmailConfirm: String?

  public init(lastEmailConfirm: String? = nil) {
    self.lastEmailConfirm = lastEmailConfirm
  }
}

/// Invite-copy tracking.
public struct Invites: Codable, Sendable, Equatable {
  public var copiedInvites: [String]

  public init(copiedInvites: [String] = []) {
    self.copiedInvites = copiedInvites
  }
}

/// Onboarding progress.
public struct Onboarding: Codable, Sendable, Equatable {
  public var step: String

  public init(step: String = "Home") {
    self.step = step
  }
}

/// The root persisted document.
///
/// Structurally identical to the RN zod `schema` in
/// `src/state/persisted/schema.ts`. See <doc:TolerantDecoding> for why the
/// Swift decoder does NOT reproduce the TS behavior of discarding the entire
/// document when one field fails validation.
public struct PersistedSchema: Codable, Sendable, Equatable {
  public var colorMode: ColorMode
  public var darkTheme: DarkTheme?
  public var session: PersistedSession
  public var reminders: Reminders
  public var languagePrefs: LanguagePrefs
  public var requireAltTextEnabled: Bool
  public var largeAltBadgeEnabled: Bool?
  public var externalEmbeds: ExternalEmbeds?
  public var invites: Invites
  public var onboarding: Onboarding
  /// Should move to the server.
  public var hiddenPosts: [String]?
  public var useInAppBrowser: Bool?
  /// Deprecated.
  public var lastSelectedHomeFeed: String?
  public var pdsAddressHistory: [String]?
  public var disableHaptics: Bool?
  public var disableAutoplay: Bool?
  public var kawaii: Bool?
  public var hasCheckedForStarterPack: Bool?
  public var subtitlesEnabled: Bool?
  /// Deprecated.
  public var mutedThreads: [String]
  public var trendingDisabled: Bool?
  public var trendingVideoDisabled: Bool?

  public init(
    colorMode: ColorMode = .system,
    darkTheme: DarkTheme? = .dim,
    session: PersistedSession = PersistedSession(),
    reminders: Reminders = Reminders(),
    languagePrefs: LanguagePrefs = LanguagePrefs(),
    requireAltTextEnabled: Bool = false,
    largeAltBadgeEnabled: Bool? = false,
    externalEmbeds: ExternalEmbeds? = ExternalEmbeds(),
    invites: Invites = Invites(),
    onboarding: Onboarding = Onboarding(),
    hiddenPosts: [String]? = [],
    useInAppBrowser: Bool? = nil,
    lastSelectedHomeFeed: String? = nil,
    pdsAddressHistory: [String]? = [],
    disableHaptics: Bool? = false,
    disableAutoplay: Bool? = nil,
    kawaii: Bool? = false,
    hasCheckedForStarterPack: Bool? = false,
    subtitlesEnabled: Bool? = true,
    mutedThreads: [String] = [],
    trendingDisabled: Bool? = false,
    trendingVideoDisabled: Bool? = false
  ) {
    self.colorMode = colorMode
    self.darkTheme = darkTheme
    self.session = session
    self.reminders = reminders
    self.languagePrefs = languagePrefs
    self.requireAltTextEnabled = requireAltTextEnabled
    self.largeAltBadgeEnabled = largeAltBadgeEnabled
    self.externalEmbeds = externalEmbeds
    self.invites = invites
    self.onboarding = onboarding
    self.hiddenPosts = hiddenPosts
    self.useInAppBrowser = useInAppBrowser
    self.lastSelectedHomeFeed = lastSelectedHomeFeed
    self.pdsAddressHistory = pdsAddressHistory
    self.disableHaptics = disableHaptics
    self.disableAutoplay = disableAutoplay
    self.kawaii = kawaii
    self.hasCheckedForStarterPack = hasCheckedForStarterPack
    self.subtitlesEnabled = subtitlesEnabled
    self.mutedThreads = mutedThreads
    self.trendingDisabled = trendingDisabled
    self.trendingVideoDisabled = trendingVideoDisabled
  }

  /// The defaults applied when no document exists yet (RN `defaults`).
  ///
  /// `languagePrefs` is parameterized rather than derived from `Locale`,
  /// because the Persistence package must not depend on device locale APIs
  /// that differ per platform; the app layer supplies the device languages.
  public static func defaults(
    languagePrefs: LanguagePrefs = LanguagePrefs()
  ) -> PersistedSchema {
    PersistedSchema(languagePrefs: languagePrefs)
  }
}

/// Documentation marker for the deliberate divergence from the TS behavior.
///
/// The TS layer (`tryParse` in `src/state/persisted/schema.ts`) runs the whole
/// document through a zod schema and returns `undefined` if ANY field fails.
/// The root state is then replaced with `defaults`, which drops every account
/// and every preference - the user boots logged out because one field was
/// malformed. That is a footgun: one bad write or one schema tightening logs
/// everyone out.
///
/// The Swift port decodes field-by-field. A field that fails to decode falls
/// back to its default (or `nil`) and is recorded as a ``DecodeIssue``, while
/// every other field - crucially, the other accounts - survives. Decoding
/// never throws for shape reasons, so a partially-corrupt document is always
/// recoverable.
public enum TolerantDecoding {}

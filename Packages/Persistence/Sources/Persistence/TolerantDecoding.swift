import Foundation

/// Field-by-field decoding of the root persisted document.
///
/// Every accessor reads one field and falls back to a supplied default when
/// the field is absent, `null`, or the wrong JSON type. Failures are collected
/// as ``DecodeIssue`` values instead of aborting the decode, which is the
/// whole point of the deviation described on ``TolerantDecoding``.
///
/// This is a class rather than a struct so nested decoding can share one issue
/// log without threading an `inout` accumulator through every call.
final class TolerantObject {
  /// The raw members of the object being decoded.
  let members: [String: JSONValue]

  /// The dotted path prefix used when reporting an issue for this object.
  let path: String

  /// The shared issue log for the whole decode.
  private let log: IssueLog

  init(members: [String: JSONValue], path: String = "", log: IssueLog = IssueLog()) {
    self.members = members
    self.path = path
    self.log = log
  }

  private func childPath(_ key: String) -> String {
    path.isEmpty ? key : "\(path).\(key)"
  }

  /// Reads a decodable field, reporting an issue when it is unusable.
  func field<T: Decodable>(_ key: String, as type: T.Type) -> T? {
    guard let raw = members[key] else { return nil }
    guard let value = raw.decoded(as: T.self) else {
      log.record(
        field: childPath(key),
        detail: "value did not decode as \(T.self); using default")
      return nil
    }
    return value
  }

  /// Reads a field that has a default, substituting it on any failure.
  func field<T: Decodable>(_ key: String, default fallback: T) -> T {
    field(key, as: T.self) ?? fallback
  }

  /// Reads a field that is legitimately optional in the schema.
  func optional<T: Decodable>(_ key: String, as type: T.Type) -> T? {
    field(key, as: T.self)
  }

  /// Reads a nested object, if the member is one.
  func object(_ key: String) -> TolerantObject? {
    guard let raw = members[key] else { return nil }
    guard let nested = raw.objectValue else {
      log.record(field: childPath(key), detail: "expected an object; using default")
      return nil
    }
    return TolerantObject(members: nested, path: childPath(key), log: log)
  }

  /// Reads an array of nested objects, skipping (and reporting) elements that
  /// are not objects.
  ///
  /// Skipping rather than failing is the per-item form of the same policy: a
  /// corrupt account entry drops one account, not the array.
  func objectArray(_ key: String) -> [TolerantObject] {
    guard let raw = members[key] else { return [] }
    guard let elements = raw.arrayValue else {
      log.record(field: childPath(key), detail: "expected an array; using default")
      return []
    }
    return elements.enumerated().compactMap { index, element in
      guard let nested = element.objectValue else {
        log.record(
          field: "\(childPath(key))[\(index)]",
          detail: "element was not an object; skipped")
        return nil
      }
      return TolerantObject(
        members: nested, path: "\(childPath(key))[\(index)]", log: log)
    }
  }

  /// Records that this object has no usable `did`, so the owning entry is
  /// dropped. Called only from ``PersistedAccount/decode(from:)``.
  func recordMissingDid() {
    log.record(
      field: childPath("did"), detail: "missing or empty did; account dropped")
  }
}

/// Mutable collector shared by every ``TolerantObject`` in one decode.
final class IssueLog {
  private(set) var issues: [DecodeIssue] = []

  func record(field: String, detail: String) {
    issues.append(DecodeIssue(field: field, detail: detail))
  }
}

extension PersistedAccount {
  /// Decodes one account from a tolerant object, falling back per field.
  ///
  /// `did` is the one field the store cannot synthesize: without it the
  /// account cannot be addressed at all, so the entry is dropped. Every other
  /// field falls back individually.
  static func decode(from object: TolerantObject) -> PersistedAccount? {
    guard let did = object.field("did", as: String.self), !did.isEmpty else {
      object.recordMissingDid()
      return nil
    }
    return PersistedAccount(
      service: object.field("service", default: ""),
      did: did,
      handle: object.field("handle", default: ""),
      email: object.optional("email", as: String.self),
      emailConfirmed: object.optional("emailConfirmed", as: Bool.self),
      emailAuthFactor: object.optional("emailAuthFactor", as: Bool.self),
      refreshJwt: object.optional("refreshJwt", as: String.self),
      accessJwt: object.optional("accessJwt", as: String.self),
      signupQueued: object.optional("signupQueued", as: Bool.self),
      active: object.optional("active", as: Bool.self),
      status: object.optional("status", as: String.self),
      pdsUrl: object.optional("pdsUrl", as: String.self),
      isSelfHosted: object.optional("isSelfHosted", as: Bool.self))
  }
}

extension PersistedSchema {
  /// Decodes the root document tolerantly, returning it alongside every
  /// field-level fallback that was applied.
  ///
  /// This never throws for shape reasons. Invalid UTF-8 or malformed JSON at
  /// the byte level is handled by ``PersistedStore``, which falls back to
  /// defaults when the document cannot be parsed at all.
  public static func decodeTolerantly(
    from raw: JSONValue
  ) -> (schema: PersistedSchema, issues: [DecodeIssue]) {
    guard let members = raw.objectValue else {
      let log = IssueLog()
      log.record(field: "(root)", detail: "expected an object; using defaults")
      return (defaults(), log.issues)
    }
    let log = IssueLog()
    let root = TolerantObject(members: members, log: log)
    var schema = defaults()

    schema.colorMode = root.field("colorMode", default: ColorMode.system)
    schema.darkTheme = root.optional("darkTheme", as: DarkTheme.self)
    schema.requireAltTextEnabled = root.field("requireAltTextEnabled", default: false)
    schema.largeAltBadgeEnabled = root.optional("largeAltBadgeEnabled", as: Bool.self)
    schema.invites = Self.decodeInvites(from: root.object("invites"))
    schema.onboarding = Self.decodeOnboarding(from: root.object("onboarding"))
    schema.hiddenPosts = root.optional("hiddenPosts", as: [String].self)
    schema.useInAppBrowser = root.optional("useInAppBrowser", as: Bool.self)
    schema.lastSelectedHomeFeed = root.optional("lastSelectedHomeFeed", as: String.self)
    schema.pdsAddressHistory = root.optional("pdsAddressHistory", as: [String].self)
    schema.disableHaptics = root.optional("disableHaptics", as: Bool.self)
    schema.disableAutoplay = root.optional("disableAutoplay", as: Bool.self)
    schema.kawaii = root.optional("kawaii", as: Bool.self)
    schema.hasCheckedForStarterPack = root.optional(
      "hasCheckedForStarterPack", as: Bool.self)
    schema.subtitlesEnabled = root.optional("subtitlesEnabled", as: Bool.self)
    schema.mutedThreads = root.field("mutedThreads", default: [String]())
    schema.trendingDisabled = root.optional("trendingDisabled", as: Bool.self)
    schema.trendingVideoDisabled = root.optional("trendingVideoDisabled", as: Bool.self)

    if let reminders = root.object("reminders") {
      schema.reminders = Reminders(
        lastEmailConfirm: reminders.optional("lastEmailConfirm", as: String.self))
    }
    if let languagePrefs = root.object("languagePrefs") {
      schema.languagePrefs = Self.decodeLanguagePrefs(from: languagePrefs)
    }
    if let externalEmbeds = root.object("externalEmbeds") {
      schema.externalEmbeds = Self.decodeExternalEmbeds(from: externalEmbeds)
    }
    schema.session = Self.decodeSession(from: root.object("session"))

    return (schema, log.issues)
  }

  private static func decodeInvites(from object: TolerantObject?) -> Invites {
    guard let object else { return Invites() }
    return Invites(copiedInvites: object.field("copiedInvites", default: [String]()))
  }

  private static func decodeOnboarding(from object: TolerantObject?) -> Onboarding {
    guard let object else { return Onboarding() }
    return Onboarding(step: object.field("step", default: "Home"))
  }

  private static func decodeLanguagePrefs(from object: TolerantObject) -> LanguagePrefs {
    var prefs = LanguagePrefs()
    prefs.primaryLanguage = object.field("primaryLanguage", default: prefs.primaryLanguage)
    prefs.contentLanguages = object.field(
      "contentLanguages", default: prefs.contentLanguages)
    prefs.postLanguage = object.field("postLanguage", default: prefs.postLanguage)
    prefs.postLanguageHistory = object.field(
      "postLanguageHistory", default: prefs.postLanguageHistory)
    prefs.appLanguage = object.field("appLanguage", default: prefs.appLanguage)
    return prefs
  }

  private static func decodeExternalEmbeds(from object: TolerantObject) -> ExternalEmbeds {
    var embeds = ExternalEmbeds()
    embeds.giphy = object.optional("giphy", as: ExternalEmbedOption.self)
    embeds.tenor = object.optional("tenor", as: ExternalEmbedOption.self)
    embeds.klipy = object.optional("klipy", as: ExternalEmbedOption.self)
    embeds.youtube = object.optional("youtube", as: ExternalEmbedOption.self)
    embeds.youtubeShorts = object.optional("youtubeShorts", as: ExternalEmbedOption.self)
    embeds.twitch = object.optional("twitch", as: ExternalEmbedOption.self)
    embeds.vimeo = object.optional("vimeo", as: ExternalEmbedOption.self)
    embeds.spotify = object.optional("spotify", as: ExternalEmbedOption.self)
    embeds.appleMusic = object.optional("appleMusic", as: ExternalEmbedOption.self)
    embeds.soundcloud = object.optional("soundcloud", as: ExternalEmbedOption.self)
    embeds.flickr = object.optional("flickr", as: ExternalEmbedOption.self)
    embeds.bandcamp = object.optional("bandcamp", as: ExternalEmbedOption.self)
    return embeds
  }

  private static func decodeSession(from object: TolerantObject?) -> PersistedSession {
    guard let object else { return PersistedSession() }
    var session = PersistedSession()
    session.accounts = object.objectArray("accounts").compactMap { entry in
      PersistedAccount.decode(from: entry)
    }
    if let current = object.object("currentAccount"),
      let did = current.field("did", as: String.self) {
      session.currentAccount = PersistedCurrentAccount(
        did: did,
        service: current.optional("service", as: String.self),
        handle: current.optional("handle", as: String.self))
    }
    return session
  }
}
